const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");
const os = require("os");
const path = require("path");
const fs = require("fs/promises");
const { execFile } = require("child_process");
const { promisify } = require("util");
const ffmpeg = require("fluent-ffmpeg");
const ffmpegInstaller = require("@ffmpeg-installer/ffmpeg");

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onObjectFinalized } = require("firebase-functions/v2/storage");

admin.initializeApp();
ffmpeg.setFfmpegPath(ffmpegInstaller.path);
const execFileAsync = promisify(execFile);

const NAVER_CLIENT_ID = defineSecret("NAVER_CLIENT_ID");
const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");
const KAKAO_REST_API_KEY = "1f9fa5991d000ee260fa27298f20ad8d";
const BOOTSTRAP_ADMIN_EMAIL = "sinbun001@gmail.com";

const isChurchAdmin = async (scanner, churchId, authToken = {}) => {
  if (!scanner || !churchId) return false;
  if (scanner.isPlatformAdmin === true) return true;
  if ((authToken.email || "").toLowerCase() === BOOTSTRAP_ADMIN_EMAIL) {
    return true;
  }
  if (
    scanner.churchId === churchId &&
    ["admin", "church_admin"].includes(scanner.role)
  ) {
    return true;
  }

  const churchDoc = await admin.firestore().collection("churches").doc(churchId).get();
  const adminUids = churchDoc.exists ? churchDoc.data()?.adminUids || [] : [];
  return adminUids.includes(scanner.uid);
};

const canScanAttendance = async ({ scanner, targetUser, churchId, authToken }) => {
  if (await isChurchAdmin(scanner, churchId, authToken)) {
    return true;
  }

  if (scanner?.role !== "part_leader") {
    return false;
  }

  const scannerPart = scanner.partLeaderFor || scanner.part || null;
  return Boolean(scannerPart && targetUser?.part === scannerPart);
};

const authorFields = (userData = {}) => ({
  userName: userData.name || "",
  userPart: userData.part || "",
  userGeneration: userData.generation || "",
  userImageUrl: userData.profileImageUrl || userData.imageUrl || null,
});

const HARMONY_PARTS = ["soprano", "alto", "tenor", "bass"];
const HARMONY_PART_LABELS = {
  soprano: "소프라노",
  alto: "알토",
  tenor: "테너",
  bass: "베이스",
};

const lyricLinesFromText = (text = "") =>
  String(text || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

const lyricLinesForAutoTiming = (text = "") => {
  const sectionPattern = /^(intro|inter|interlude|verse|chorus|bridge|outro|ending|간주|전주)\s*\d*$/i;
  return String(text || "")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line, index) => {
      if (!line) return false;
      if (index === 0 && /^\d{2}\.\d{2}\.\d{2}_/.test(line)) return false;
      return !sectionPattern.test(line);
    });
};

const plainLyricsTimelineFromText = (text = "") =>
  lyricLinesForAutoTiming(text).map((line, index) => ({
    timeSec: index * 3.2,
    text: line,
  }));

const lyricsTimelineFromValue = (value) => {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => ({
      timeSec: Number(entry?.timeSec || entry?.time || 0),
      text: String(entry?.text || entry?.lyric || "").trim(),
    }))
    .filter((entry) => entry.text)
    .sort((a, b) => a.timeSec - b.timeSec);
};

const lyricsTimelineFromText = (text = "") => {
  const entries = [];
  const pattern = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]\s*(.*)/;
  String(text || "")
    .split(/\r?\n/)
    .forEach((line) => {
      const match = pattern.exec(line.trim());
      if (!match) return;
      const minutes = Number.parseInt(match[1] || "0", 10) || 0;
      const seconds = Number.parseInt(match[2] || "0", 10) || 0;
      const fractionText = match[3] || "";
      const fraction = fractionText
        ? (Number.parseInt(fractionText, 10) || 0) / (10 ** fractionText.length)
        : 0;
      const lyric = String(match[4] || "").trim();
      if (!lyric) return;
      entries.push({ timeSec: minutes * 60 + seconds + fraction, text: lyric });
    });
  if (entries.length > 0) return entries.sort((a, b) => a.timeSec - b.timeSec);
  return plainLyricsTimelineFromText(text);
};

const lyricLineForSegment = (timeline, fallbackLines, index, startSec, endSec) => {
  if (timeline.length > 0) {
    const inSegment = timeline.find((entry) => {
      const timeSec = Number(entry.timeSec || 0);
      return timeSec >= startSec && (endSec <= startSec || timeSec < endSec);
    });
    if (inSegment?.text) return inSegment.text;
  }
  return fallbackLines[index] || "";
};

const nextLyricLineForSegment = (timeline, fallbackLines, index, endSec) => {
  if (timeline.length > 0) {
    const next = timeline.find((entry) => Number(entry.timeSec || 0) >= endSec);
    if (next?.text) return next.text;
  }
  return fallbackLines[index + 1] || "";
};

const pickHarmonyAssignee = async ({
  db,
  churchId,
  part,
  sourcePollId = "",
  excludeUserIds = new Set(),
}) => {
  const safePart = String(part || "").trim();
  if (!churchId || !safePart) return null;

  let attendeeIds = null;
  const pollId = String(sourcePollId || "").trim();
  if (pollId) {
    const votesSnapshot = await db
      .collection("poll_votes")
      .where("pollId", "==", pollId)
      .get();
    attendeeIds = new Set();
    votesSnapshot.docs.forEach((doc) => {
      const vote = doc.data() || {};
      const voterId = String(vote.userId || vote.voterId || "").trim();
      if (
        vote.churchId === churchId &&
        vote.choice === "attend" &&
        voterId &&
        !excludeUserIds.has(voterId)
      ) {
        attendeeIds.add(voterId);
      }
    });
    if (attendeeIds.size === 0) return null;
  }

  const usersSnapshot = await db
    .collection("users")
    .where("churchId", "==", churchId)
    .get();
  const candidates = usersSnapshot.docs
    .filter((doc) => {
      const user = doc.data() || {};
      return (
        user.part === safePart &&
        user.approvalStatus === "approved" &&
        !excludeUserIds.has(doc.id) &&
        (!attendeeIds || attendeeIds.has(doc.id))
      );
    })
    .map((doc) => ({ id: doc.id, ...doc.data() }));

  if (candidates.length === 0) return null;
  return candidates[Math.floor(Math.random() * candidates.length)];
};

const createHarmonyRelayNotification = async ({
  db,
  churchId,
  toUserId,
  relayId,
  title,
  body,
  sentBy,
}) => {
  if (!toUserId) return;
  await db.collection("notifications").add({
    churchId,
    toUserId,
    title,
    body,
    type: "harmony_relay",
    relayId,
    sentAt: admin.firestore.FieldValue.serverTimestamp(),
    sentBy,
  });
};

const parseFfmpegDuration = (text = "") => {
  const match = text.match(/Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/);
  if (!match) return 0;
  return (
    Number(match[1]) * 3600 +
    Number(match[2]) * 60 +
    Number(match[3])
  );
};

const parseSilences = (text = "") => {
  const starts = [];
  const ends = [];
  for (const match of text.matchAll(/silence_start:\s*([\d.]+)/g)) {
    starts.push(Number(match[1]));
  }
  for (const match of text.matchAll(/silence_end:\s*([\d.]+)\s*\|\s*silence_duration:\s*([\d.]+)/g)) {
    ends.push({
      end: Number(match[1]),
      duration: Number(match[2]),
      start: Number(match[1]) - Number(match[2]),
    });
  }
  return ends.length > 0
    ? ends
    : starts.map((start) => ({ start, end: start, duration: 0 }));
};

const pushSegment = (segments, startSec, endSec) => {
  const start = Math.max(0, Number(startSec.toFixed(2)));
  const end = Math.max(start, Number(endSec.toFixed(2)));
  if (end - start < 4) return;
  segments.push({
    id: `seg-${String(segments.length + 1).padStart(2, "0")}`,
    order: segments.length + 1,
    label: `${segments.length + 1}소절`,
    startSec: start,
    endSec: end,
    durationSec: Number((end - start).toFixed(2)),
  });
};

const splitLongRegion = (segments, startSec, endSec) => {
  const duration = endSec - startSec;
  if (duration <= 0) return;
  if (duration <= 28) {
    pushSegment(segments, startSec, endSec);
    return;
  }
  const chunkCount = Math.min(12, Math.max(2, Math.round(duration / 18)));
  const chunk = duration / chunkCount;
  for (let index = 0; index < chunkCount; index += 1) {
    pushSegment(segments, startSec + chunk * index, startSec + chunk * (index + 1));
  }
};

const fallbackSegments = (durationSec) => {
  const safeDuration = Math.max(20, durationSec || 80);
  const count = Math.min(14, Math.max(4, Math.round(safeDuration / 18)));
  const chunk = safeDuration / count;
  const segments = [];
  for (let index = 0; index < count; index += 1) {
    pushSegment(segments, chunk * index, chunk * (index + 1));
  }
  return segments;
};

const buildSegmentsFromSilence = (silences, durationSec) => {
  if (!durationSec || durationSec < 8 || silences.length === 0) {
    return fallbackSegments(durationSec);
  }
  const segments = [];
  let cursor = 0;
  const sortedSilences = silences
    .filter((item) => Number.isFinite(item.start) && Number.isFinite(item.end))
    .sort((a, b) => a.start - b.start);

  for (const silence of sortedSilences) {
    if (silence.duration >= 0.35 && silence.start - cursor >= 4) {
      splitLongRegion(segments, cursor, Math.max(cursor, silence.start));
      cursor = Math.max(cursor, silence.end);
    }
  }
  if (durationSec - cursor >= 4) {
    splitLongRegion(segments, cursor, durationSec);
  }

  if (segments.length < 3) return fallbackSegments(durationSec);
  return segments.slice(0, 18).map((segment, index) => ({
    ...segment,
    id: `seg-${String(index + 1).padStart(2, "0")}`,
    order: index + 1,
    label: `${index + 1}소절`,
  }));
};

const tempAudioPath = (url) => {
  const cleanPath = new URL(url).pathname;
  const ext = path.extname(cleanPath).split("?")[0] || ".audio";
  return path.join(
    os.tmpdir(),
    `harmony_${Date.now()}_${crypto.randomBytes(5).toString("hex")}${ext}`,
  );
};

const analyzeAudioUrl = async (audioUrl) => {
  if (!audioUrl) return { durationSec: 0, source: "none", segments: [] };
  const inputPath = tempAudioPath(audioUrl);
  try {
    const response = await axios.get(audioUrl, {
      responseType: "arraybuffer",
      timeout: 90000,
      maxContentLength: 80 * 1024 * 1024,
    });
    await fs.writeFile(inputPath, response.data);
    const result = await execFileAsync(
      ffmpegInstaller.path,
      [
        "-hide_banner",
        "-i",
        inputPath,
        "-af",
        "silencedetect=noise=-34dB:d=0.45",
        "-f",
        "null",
        "-",
      ],
      { timeout: 180000, maxBuffer: 12 * 1024 * 1024 },
    );
    const stderr = result.stderr || "";
    const durationSec = parseFfmpegDuration(stderr);
    const silences = parseSilences(stderr);
    const segments = buildSegmentsFromSilence(silences, durationSec);
    return {
      durationSec: Number((durationSec || 0).toFixed(2)),
      source: silences.length > 0 ? "ffmpeg-silencedetect" : "duration-fallback",
      segments,
    };
  } catch (error) {
    const stderr = error?.stderr || "";
    const durationSec = parseFfmpegDuration(stderr);
    if (durationSec > 0) {
      return {
        durationSec: Number(durationSec.toFixed(2)),
        source: "duration-fallback",
        segments: fallbackSegments(durationSec),
      };
    }
    console.error("Harmony audio analysis failed:", error);
    throw new HttpsError("internal", "음원 구간 분석에 실패했습니다.");
  } finally {
    await fs.unlink(inputPath).catch(() => {});
  }
};

exports.analyzeSheetMusicForHarmony = onCall(
  { memory: "1GiB", timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const { churchId, sheetMusicId } = request.data || {};
    if (!churchId || !sheetMusicId) {
      throw new HttpsError("invalid-argument", "악보 정보가 올바르지 않습니다.");
    }

    const db = admin.firestore();
    const [adminDoc, sheetDoc] = await Promise.all([
      db.collection("users").doc(request.auth.uid).get(),
      db.collection("sheet_music").doc(String(sheetMusicId)).get(),
    ]);
    if (!adminDoc.exists) {
      throw new HttpsError("permission-denied", "관리자 프로필을 찾을 수 없습니다.");
    }
    if (!sheetDoc.exists) {
      throw new HttpsError("not-found", "악보를 찾을 수 없습니다.");
    }
    const adminUser = { uid: request.auth.uid, ...adminDoc.data() };
    const sheet = sheetDoc.data() || {};
    if (sheet.churchId !== churchId) {
      throw new HttpsError("permission-denied", "다른 교회 악보입니다.");
    }
    if (!(await isChurchAdmin(adminUser, churchId, request.auth.token))) {
      throw new HttpsError("permission-denied", "악보 분석 권한이 없습니다.");
    }

    const sheetRef = sheetDoc.ref;
    await sheetRef.update({
      harmonyAnalysisStatus: "processing",
      harmonyAnalysisStartedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      const partFiles = sheet.partFiles || {};
      const globalGuideUrl = sheet.audioUrl || "";
      const parts = {};

      for (const part of HARMONY_PARTS) {
        const partFile = partFiles[part] || {};
        const audioUrl = partFile.guideAudioUrl || globalGuideUrl;
        if (!audioUrl) continue;
        const analyzed = await analyzeAudioUrl(audioUrl);
        parts[part] = analyzed.segments.map((segment) => ({
          ...segment,
          part,
          partLabel: HARMONY_PART_LABELS[part] || part,
          audioSource: partFile.guideAudioUrl ? "part-guide" : "global-guide",
          sourceAudioUrl: audioUrl,
        }));
      }

      const totalSegments = Object.values(parts).reduce(
        (total, segments) => total + segments.length,
        0,
      );
      if (totalSegments === 0) {
        throw new HttpsError(
          "failed-precondition",
          "분석할 가이드 음원이 없습니다.",
        );
      }

      await sheetRef.update({
        harmonyAnalysisStatus: "ready",
        harmonySegments: {
          version: 1,
          source: "ffmpeg-silencedetect",
          generatedAt: admin.firestore.Timestamp.now(),
          partCount: Object.keys(parts).length,
          totalSegments,
          parts,
        },
        harmonyAnalysisError: admin.firestore.FieldValue.delete(),
        harmonyAnalysisFinishedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        status: "ready",
        partCount: Object.keys(parts).length,
        totalSegments,
      };
    } catch (error) {
      const message =
        error instanceof HttpsError
          ? error.message
          : error?.message || "음원 구간 분석에 실패했습니다.";
      await sheetRef.update({
        harmonyAnalysisStatus: "failed",
        harmonyAnalysisError: message,
        harmonyAnalysisFinishedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", message);
    }
  },
);

exports.createHarmonyRelaysForSheetMusic = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }

  const { churchId, sheetMusicId } = request.data || {};
  if (!churchId || !sheetMusicId) {
    throw new HttpsError("invalid-argument", "악보 정보가 올바르지 않습니다.");
  }

  const db = admin.firestore();
  const [adminDoc, sheetDoc] = await Promise.all([
    db.collection("users").doc(request.auth.uid).get(),
    db.collection("sheet_music").doc(String(sheetMusicId)).get(),
  ]);
  if (!adminDoc.exists) {
    throw new HttpsError("permission-denied", "관리자 프로필을 찾을 수 없습니다.");
  }
  if (!sheetDoc.exists) {
    throw new HttpsError("not-found", "악보를 찾을 수 없습니다.");
  }

  const adminUser = { uid: request.auth.uid, ...adminDoc.data() };
  const sheet = sheetDoc.data() || {};
  if (sheet.churchId !== churchId) {
    throw new HttpsError("permission-denied", "다른 교회 악보입니다.");
  }
  if (!(await isChurchAdmin(adminUser, churchId, request.auth.token))) {
    throw new HttpsError("permission-denied", "하모니 릴레이 생성 권한이 없습니다.");
  }

  const partFiles = sheet.partFiles || {};
  const harmonyParts = sheet.harmonySegments?.parts || {};
  const sourcePollId = String(sheet.sourcePollId || "").trim();
  const sourceEventId = String(sheet.sourceEventId || sheet.sourceScheduleId || "").trim();
  const songTitle = sheet.songTitle || sheet.title || "오늘의 가이드";
  const sheetDate = sheet.sheetDate || sheet.scheduleDate || "";
  const lyricsText = String(sheet.lyricsText || "").trim();
  const storedLyricsTimeline = lyricsTimelineFromValue(sheet.lyricsTimeline);
  const lyricsTimeline = storedLyricsTimeline.length > 0
    ? storedLyricsTimeline
    : lyricsTimelineFromText(lyricsText);
  const lyricLines = lyricLinesFromText(lyricsText);
  const notifiedUsers = new Set();
  let createdCount = 0;
  let updatedCount = 0;
  let assigneeCount = 0;

  for (const part of HARMONY_PARTS) {
    const segments = Array.isArray(harmonyParts[part]) ? harmonyParts[part] : [];
    if (segments.length === 0) continue;

    const partFile = partFiles[part] || {};
    const missionGroupId = `${sheetDoc.id}_${part}`;
    const existingSnapshot = await db
      .collection("harmony_relays")
      .where("missionGroupId", "==", missionGroupId)
      .get();
    const existingBySegment = {};
    existingSnapshot.docs.forEach((doc) => {
      const relay = doc.data() || {};
      if (relay.churchId === churchId && relay.part === part) {
        existingBySegment[String(relay.segmentId || "")] = doc;
      }
    });

    const guideAudioUrl = partFile.guideAudioUrl || sheet.audioUrl || "";
    const guideAudioFileName = partFile.guideAudioFileName || sheet.audioFileName || "";
    const mrAudioUrl = partFile.mrAudioUrl || sheet.mrAudioUrl || "";
    const mrAudioFileName = partFile.mrAudioFileName || sheet.mrAudioFileName || "";
    const sourceSheetUrl = partFile.sheetUrl || sheet.fileUrl || "";
    const partLyricsText = String(partFile.lyricsText || lyricsText).trim();
    const storedPartLyricsTimeline = lyricsTimelineFromValue(partFile.lyricsTimeline);
    const partLyricsTimeline = storedPartLyricsTimeline.length > 0
      ? storedPartLyricsTimeline
      : partLyricsText === lyricsText
        ? lyricsTimeline
        : lyricsTimelineFromText(partLyricsText);
    const partLyricLines = partLyricsText === lyricsText
      ? lyricLines
      : lyricLinesFromText(partLyricsText);
    let handoffSeeded = false;

    for (let index = 0; index < segments.length; index += 1) {
      const rawSegment = segments[index] || {};
      const segmentId = rawSegment.id || `seg-${String(index + 1).padStart(2, "0")}`;
      const segmentLabel = rawSegment.label || `${index + 1}소절`;
      const existingDoc = existingBySegment[segmentId];
      const existingRelay = existingDoc ? existingDoc.data() || {} : {};
      const existingAssigneeId = String(existingRelay.currentAssigneeId || "").trim();
      const existingCompleted = String(existingRelay.status || "") === "completed";
      const existingAssignee =
        existingDoc && !handoffSeeded && !existingAssigneeId && !existingCompleted
          ? await pickHarmonyAssignee({
              db,
              churchId,
              part,
              sourcePollId,
              excludeUserIds: new Set([request.auth.uid]),
            })
          : null;
      if (existingAssignee) assigneeCount += 1;
      const commonUpdate = {
        guideAudioUrl,
        guideAudioFileName,
        mrAudioUrl,
        mrAudioFileName,
        sourceSheetMusicId: sheetDoc.id,
        sourceTitle: songTitle,
        sourceDate: sheetDate,
        sourceSheetUrl,
        sourcePollId,
        sourceEventId,
        lyricsText: partLyricsText,
        lyricsTimeline: partLyricsTimeline,
        lyricsLine: lyricLineForSegment(
          partLyricsTimeline,
          partLyricLines,
          index,
          Number(rawSegment.startSec || 0),
          Number(rawSegment.endSec || 0),
        ),
        nextLyricsLine: nextLyricLineForSegment(
          partLyricsTimeline,
          partLyricLines,
          index,
          Number(rawSegment.endSec || 0),
        ),
        missionTotalSegments: segments.length,
        segmentOrder: Number(rawSegment.order || index + 1),
        segmentStartSec: Number(rawSegment.startSec || 0),
        segmentEndSec: Number(rawSegment.endSec || 0),
        segmentDurationSec: Number(rawSegment.durationSec || 0),
        ...(existingAssignee
          ? {
              currentAssigneeId: existingAssignee.id || "",
              currentAssigneeName: existingAssignee.name || "",
              assignedAt: admin.firestore.FieldValue.serverTimestamp(),
            }
          : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (existingDoc) {
        await existingDoc.ref.update(commonUpdate);
        updatedCount += 1;
        if (existingAssignee?.id && !notifiedUsers.has(existingAssignee.id)) {
          notifiedUsers.add(existingAssignee.id);
          await createHarmonyRelayNotification({
            db,
            churchId,
            toUserId: existingAssignee.id,
            relayId: existingDoc.id,
            title: "하모니 릴레이 미션이 열렸어요",
            body: `${songTitle} ${segmentLabel}을 이어서 불러주세요.`,
            sentBy: request.auth.uid,
          });
        }
        if (!existingCompleted && (existingAssigneeId || existingAssignee)) {
          handoffSeeded = true;
        }
        continue;
      }

      const assignee = handoffSeeded
        ? null
        : await pickHarmonyAssignee({
            db,
            churchId,
            part,
            sourcePollId,
            excludeUserIds: new Set([request.auth.uid]),
          });
      if (assignee) assigneeCount += 1;

      const relayRef = await db.collection("harmony_relays").add({
        churchId,
        userId: request.auth.uid,
        part,
        title: `${songTitle} 릴레이`,
        segmentLabel,
        guide: sheet.conductorComment || "",
        guideAudioUrl,
        guideAudioFileName,
        mrAudioUrl,
        mrAudioFileName,
        sourceSheetMusicId: sheetDoc.id,
        sourceTitle: songTitle,
        sourceDate: sheetDate,
        sourceSheetUrl,
        sourcePollId,
        sourceEventId,
        lyricsText: partLyricsText,
        lyricsTimeline: partLyricsTimeline,
        lyricsLine: lyricLineForSegment(
          partLyricsTimeline,
          partLyricLines,
          index,
          Number(rawSegment.startSec || 0),
          Number(rawSegment.endSec || 0),
        ),
        nextLyricsLine: nextLyricLineForSegment(
          partLyricsTimeline,
          partLyricLines,
          index,
          Number(rawSegment.endSec || 0),
        ),
        missionGroupId,
        missionTotalSegments: segments.length,
        segmentId,
        segmentOrder: Number(rawSegment.order || index + 1),
        segmentStartSec: Number(rawSegment.startSec || 0),
        segmentEndSec: Number(rawSegment.endSec || 0),
        segmentDurationSec: Number(rawSegment.durationSec || 0),
        status: "open",
        currentAssigneeId: assignee?.id || "",
        currentAssigneeName: assignee?.name || "",
        assignedAt: assignee
          ? admin.firestore.FieldValue.serverTimestamp()
          : null,
        clipCount: 0,
        ...authorFields(adminUser),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      createdCount += 1;

      if (assignee?.id && !notifiedUsers.has(assignee.id)) {
        notifiedUsers.add(assignee.id);
        await createHarmonyRelayNotification({
          db,
          churchId,
          toUserId: assignee.id,
          relayId: relayRef.id,
          title: "하모니 릴레이 미션이 열렸어요",
          body: `${songTitle} ${segmentLabel}을 이어서 불러주세요.`,
          sentBy: request.auth.uid,
        });
      }
      if (assignee) handoffSeeded = true;
    }
  }

  await sheetDoc.ref.update({
    harmonyRelayStatus: "ready",
    harmonyRelayCreatedAt: admin.firestore.FieldValue.serverTimestamp(),
    harmonyRelayUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    createdCount,
    updatedCount,
    assigneeCount,
    sourcePollId,
  };
});

exports.deleteScheduleEvent = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }

  const { churchId, eventId } = request.data || {};
  if (!churchId || !eventId) {
    throw new HttpsError("invalid-argument", "churchId와 eventId가 필요합니다.");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("users").doc(request.auth.uid).get();
  const adminUser = adminDoc.exists
    ? { uid: request.auth.uid, ...adminDoc.data() }
    : { uid: request.auth.uid };

  if (!(await isChurchAdmin(adminUser, String(churchId), request.auth.token))) {
    throw new HttpsError("permission-denied", "관리자 권한이 필요합니다.");
  }

  const eventRef = db.collection("events").doc(String(eventId));
  const eventDoc = await eventRef.get();
  if (!eventDoc.exists) {
    return { deleted: false, reason: "not-found" };
  }

  const event = eventDoc.data() || {};
  if (event.churchId !== churchId) {
    throw new HttpsError("permission-denied", "선택한 교회의 일정만 삭제할 수 있습니다.");
  }

  const refsByPath = new Map();
  const addRef = (ref) => refsByPath.set(ref.path, ref);
  const addDocIfSameChurch = async (collectionName, id) => {
    if (!id) return null;
    const ref = db.collection(collectionName).doc(String(id));
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.churchId !== churchId) return null;
    addRef(ref);
    return { ref, data: snap.data() || {} };
  };
  const addQuery = async (collectionName, field, value) => {
    if (!value) return [];
    const snap = await db
      .collection(collectionName)
      .where("churchId", "==", churchId)
      .where(field, "==", value)
      .get();
    return snap.docs.map((docSnap) => {
      addRef(docSnap.ref);
      return { ref: docSnap.ref, data: docSnap.data() || {} };
    });
  };

  const attendanceDocs = [];
  const pollIds = new Set();
  const chartIds = new Set();

  const preferredAttendance = await addDocIfSameChurch(
    "attendance_sessions",
    event.attendanceSessionId,
  );
  if (preferredAttendance) attendanceDocs.push(preferredAttendance);
  attendanceDocs.push(...await addQuery("attendance_sessions", "sourceEventId", eventId));
  attendanceDocs.forEach((item) => {
    if (item.data.pollId) pollIds.add(String(item.data.pollId));
  });

  if (event.pollId) pollIds.add(String(event.pollId));
  const eventPolls = await addQuery("polls", "sourceEventId", eventId);
  eventPolls.forEach((item) => pollIds.add(item.ref.id));
  for (const attendance of attendanceDocs) {
    const sessionId = attendance.ref.id;
    const linkedPolls = [
      ...await addQuery("polls", "sourceAttendanceSessionId", sessionId),
      ...await addQuery("polls", "sourceSessionId", sessionId),
    ];
    linkedPolls.forEach((item) => pollIds.add(item.ref.id));
    await addQuery("attendance", "sessionId", sessionId);
  }
  for (const pollId of pollIds) {
    await addDocIfSameChurch("polls", pollId);
    await addQuery("poll_votes", "pollId", pollId);
  }

  if (event.seatingChartId) chartIds.add(String(event.seatingChartId));
  const eventCharts = await addQuery("seating_charts", "sourceEventId", eventId);
  eventCharts.forEach((item) => chartIds.add(item.ref.id));
  for (const chartId of chartIds) {
    await addDocIfSameChurch("seating_charts", chartId);
    await addQuery("seat_assignments", "chartId", chartId);
  }

  addRef(eventRef);
  const refs = Array.from(refsByPath.values());
  for (let index = 0; index < refs.length; index += 450) {
    const batch = db.batch();
    refs.slice(index, index + 450).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }

  return {
    deleted: true,
    deletedCount: refs.length,
    eventId,
  };
});

exports.scanAttendanceQr = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }

  const { churchId, sessionId, userId, scannerMode } = request.data || {};
  if (!churchId || !sessionId || !userId) {
    throw new HttpsError("invalid-argument", "출석 QR 정보가 올바르지 않습니다.");
  }

  const db = admin.firestore();
  const scannerUid = request.auth.uid;
  const scannerRef = db.collection("users").doc(scannerUid);
  const targetRef = db.collection("users").doc(String(userId));
  const sessionRef = db.collection("attendance_sessions").doc(String(sessionId));

  const [scannerDoc, targetDoc, sessionDoc] = await Promise.all([
    scannerRef.get(),
    targetRef.get(),
    sessionRef.get(),
  ]);

  if (!scannerDoc.exists) {
    throw new HttpsError("permission-denied", "승인된 프로필을 찾을 수 없습니다.");
  }
  if (!targetDoc.exists) {
    throw new HttpsError("not-found", "해당 단원을 찾을 수 없습니다.");
  }
  if (!sessionDoc.exists) {
    throw new HttpsError("not-found", "출석 세션을 찾을 수 없습니다.");
  }

  const scanner = { uid: scannerUid, ...scannerDoc.data() };
  const targetUser = targetDoc.data() || {};
  const session = sessionDoc.data() || {};

  if (
    scanner.churchId !== churchId ||
    targetUser.churchId !== churchId ||
    session.churchId !== churchId
  ) {
    throw new HttpsError("permission-denied", "다른 교회 출석 QR입니다.");
  }
  if (session.isOpen !== true) {
    throw new HttpsError("failed-precondition", "마감된 출석 세션입니다.");
  }

  const permitted = await canScanAttendance({
    scanner,
    targetUser,
    churchId,
    authToken: request.auth.token,
  });
  if (!permitted) {
    throw new HttpsError("permission-denied", "이 단원을 출석 처리할 권한이 없습니다.");
  }

  const attendanceRef = db.collection("attendance").doc(`${sessionId}_${userId}`);
  const result = await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(attendanceRef);
    if (existing.exists) {
      return { alreadyCheckedIn: true };
    }

    transaction.set(attendanceRef, {
      churchId,
      userId: String(userId),
      sessionId: String(sessionId),
      ...authorFields(targetUser),
      checkedInAt: admin.firestore.FieldValue.serverTimestamp(),
      checkedInBy: scannerUid,
      scannerMode:
        scannerMode ||
        (scanner.role === "part_leader" ? "mobile_part_leader" : "mobile_admin"),
    });
    return { alreadyCheckedIn: false };
  });

  return {
    ...result,
    userName: targetUser.name || "",
  };
});

/**
 * 카카오 액세스 토큰 또는 웹 authorization code를 검증하고 Firebase Custom Token을 생성한다.
 */
exports.createKakaoCustomToken = onCall(async (request) => {
  const { accessToken, code, redirectUri } = request.data || {};

  if (!accessToken && (!code || !redirectUri)) {
    throw new HttpsError("invalid-argument", "카카오 인증 정보가 필요합니다.");
  }

  try {
    let kakaoAccessToken = accessToken;
    if (!kakaoAccessToken) {
      const tokenParams = new URLSearchParams({
        grant_type: "authorization_code",
        client_id: KAKAO_REST_API_KEY,
        redirect_uri: redirectUri,
        code,
      });

      const tokenResponse = await axios.post(
        "https://kauth.kakao.com/oauth/token",
        tokenParams.toString(),
        {
          headers: {
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
          },
        },
      );
      kakaoAccessToken = tokenResponse.data?.access_token;
    }

    if (!kakaoAccessToken) {
      throw new HttpsError("unauthenticated", "카카오 액세스 토큰을 받을 수 없습니다.");
    }

    // 카카오 API로 사용자 정보 조회
    const kakaoResponse = await axios.get("https://kapi.kakao.com/v2/user/me", {
      headers: { Authorization: `Bearer ${kakaoAccessToken}` },
    });

    const kakaoUser = kakaoResponse.data;
    const kakaoUid = `kakao:${kakaoUser.id}`;
    const email = kakaoUser.kakao_account?.email || null;
    const nickname =
      kakaoUser.kakao_account?.profile?.nickname ||
      kakaoUser.properties?.nickname ||
      null;
    const profileImage =
      kakaoUser.kakao_account?.profile?.profile_image_url ||
      kakaoUser.properties?.profile_image ||
      null;

    // Firebase 사용자 생성 또는 업데이트
    let firebaseUser;
    try {
      firebaseUser = await admin.auth().getUser(kakaoUid);
      // 기존 사용자 정보 업데이트
      await admin.auth().updateUser(kakaoUid, {
        ...(nickname && { displayName: nickname }),
        ...(profileImage && { photoURL: profileImage }),
      });
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        // 새 사용자 생성
        firebaseUser = await admin.auth().createUser({
          uid: kakaoUid,
          ...(email && { email }),
          ...(nickname && { displayName: nickname }),
          ...(profileImage && { photoURL: profileImage }),
        });
      } else {
        throw error;
      }
    }

    // Firebase Custom Token 생성
    const customToken = await admin.auth().createCustomToken(kakaoUid);

    return { token: customToken };
  } catch (error) {
    console.error("Kakao auth error:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "카카오 인증 처리 중 오류가 발생했습니다.");
  }
});

/**
 * 네이버 OAuth authorization code를 검증하고 Firebase Custom Token을 생성한다.
 * NAVER_CLIENT_ID / NAVER_CLIENT_SECRET Firebase Secret Manager 값이 필요하다.
 */
exports.createNaverCustomToken = onCall(
  { secrets: [NAVER_CLIENT_ID, NAVER_CLIENT_SECRET] },
  async (request) => {
  const { code, state, redirectUri } = request.data || {};
  const clientId = NAVER_CLIENT_ID.value();
  const clientSecret = NAVER_CLIENT_SECRET.value();

  if (!clientId || !clientSecret) {
    throw new HttpsError(
      "failed-precondition",
      "네이버 로그인 환경변수가 설정되지 않았습니다.",
    );
  }
  if (!code || !state || !redirectUri) {
    throw new HttpsError("invalid-argument", "네이버 인증 코드가 필요합니다.");
  }

  try {
    const tokenResponse = await axios.get("https://nid.naver.com/oauth2.0/token", {
      params: {
        grant_type: "authorization_code",
        client_id: clientId,
        client_secret: clientSecret,
        code,
        state,
      },
    });

    const accessToken = tokenResponse.data?.access_token;
    if (!accessToken) {
      throw new HttpsError("unauthenticated", "네이버 액세스 토큰을 받을 수 없습니다.");
    }

    const profileResponse = await axios.get("https://openapi.naver.com/v1/nid/me", {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    const naverProfile = profileResponse.data?.response;
    if (!naverProfile?.id) {
      throw new HttpsError("unauthenticated", "네이버 사용자 정보를 확인할 수 없습니다.");
    }

    const naverUid = `naver:${naverProfile.id}`;
    const email = naverProfile.email || null;
    const nickname = naverProfile.nickname || naverProfile.name || null;
    const profileImage = naverProfile.profile_image || null;

    try {
      await admin.auth().getUser(naverUid);
      await admin.auth().updateUser(naverUid, {
        ...(nickname && { displayName: nickname }),
        ...(profileImage && { photoURL: profileImage }),
      });
    } catch (error) {
      if (error.code === "auth/user-not-found") {
        await admin.auth().createUser({
          uid: naverUid,
          ...(email && { email }),
          ...(nickname && { displayName: nickname }),
          ...(profileImage && { photoURL: profileImage }),
        });
      } else {
        throw error;
      }
    }

    const customToken = await admin.auth().createCustomToken(naverUid);
    return { token: customToken };
  } catch (error) {
    console.error("Naver auth error:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "네이버 인증 처리 중 오류가 발생했습니다.");
  }
});

/**
 * notifications 컬렉션에 새 문서 생성 시 전체 멤버에게 푸시 알림 전송
 */
exports.sendPushNotification = onDocumentCreated("notifications/{notificationId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const { title, body, churchId, toUserId } = data;

  if (!churchId) {
    console.warn("Notification skipped: missing churchId");
    return;
  }

  let userDocs = [];
  if (toUserId) {
    const userDoc = await admin.firestore().collection("users").doc(String(toUserId)).get();
    if (userDoc.exists && userDoc.data()?.churchId === churchId) {
      userDocs = [userDoc];
    }
  } else {
    const usersSnapshot = await admin
      .firestore()
      .collection("users")
      .where("churchId", "==", churchId)
      .get();
    userDocs = usersSnapshot.docs;
  }
  const tokens = [];
  userDocs.forEach((doc) => {
    const user = doc.data();
    const token = user.fcmToken;
    if (token) tokens.push(token);

    const tokenMap = user.fcmTokens || {};
    Object.entries(tokenMap).forEach(([tokenKey, tokenData]) => {
      if (!tokenKey) return;
      if (tokenData && tokenData.enabled === false) return;
      tokens.push(tokenKey);
    });
  });

  const uniqueTokens = [...new Set(tokens)];

  if (uniqueTokens.length === 0) {
    console.log("No FCM tokens found");
    return;
  }

  // 멀티캐스트 메시지 전송
  const message = {
    notification: { title: title || "갈렙찬양대", body: body || "" },
    tokens: uniqueTokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Sent ${response.successCount}/${uniqueTokens.length} notifications`);
  } catch (error) {
    console.error("Push notification error:", error);
  }
});

/**
 * 커뮤니티 영상 원본 업로드 시 12초 이하 MP4로 서버 압축
 */
exports.compressCommunityVideo = onObjectFinalized(
  { region: "us-east1", memory: "1GiB", timeoutSeconds: 540 },
  async (event) => {
    const object = event.data;
    const filePath = object.name || "";
    const contentType = object.contentType || "";

    if (!filePath.startsWith("post_videos/source/")) return;
    if (!contentType.startsWith("video/")) return;

    const metadata = object.metadata || {};
    const postId = metadata.postId;
    if (!postId) {
      console.warn("Video source uploaded without postId metadata", filePath);
      return;
    }

    const bucket = admin.storage().bucket(object.bucket);
    const sourceFile = bucket.file(filePath);
    const inputPath = path.join(os.tmpdir(), path.basename(filePath));
    const outputName = `${postId}_${Date.now()}.mp4`;
    const outputPath = path.join(os.tmpdir(), outputName);
    const storageOutputPath = `post_videos/processed/${outputName}`;
    const postRef = admin.firestore().collection("posts").doc(postId);

    const trimStartSec = Math.max(0, Number(metadata.trimStartSec || 0));
    const requestedEndSec = Number(metadata.trimEndSec || trimStartSec + 12);
    const trimEndSec = Math.max(trimStartSec + 1, requestedEndSec);
    const durationSec = Math.min(12, trimEndSec - trimStartSec);

    try {
      await postRef.update({
        videoStatus: "processing",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await sourceFile.download({ destination: inputPath });
      await new Promise((resolve, reject) => {
        ffmpeg(inputPath)
          .setStartTime(trimStartSec)
          .duration(durationSec)
          .videoCodec("libx264")
          .audioCodec("aac")
          .outputOptions([
            "-vf",
            "scale='min(720,iw)':-2",
            "-preset",
            "veryfast",
            "-crf",
            "30",
            "-movflags",
            "+faststart",
            "-pix_fmt",
            "yuv420p",
            "-b:a",
            "96k",
          ])
          .format("mp4")
          .on("end", resolve)
          .on("error", reject)
          .save(outputPath);
      });

      const token = crypto.randomUUID();
      await bucket.upload(outputPath, {
        destination: storageOutputPath,
        metadata: {
          contentType: "video/mp4",
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });

      const encodedPath = encodeURIComponent(storageOutputPath);
      const videoUrl =
        `https://firebasestorage.googleapis.com/v0/b/${object.bucket}/o/${encodedPath}?alt=media&token=${token}`;

      await postRef.update({
        mediaType: "video",
        videoStatus: "ready",
        videoUrl,
        videoStoragePath: storageOutputPath,
        videoDurationSeconds: durationSec,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error("Community video compression failed:", error);
      await postRef.update({
        videoStatus: "failed",
        videoError: String(error.message || error),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } finally {
      await Promise.allSettled([fs.unlink(inputPath), fs.unlink(outputPath)]);
    }
  }
);
