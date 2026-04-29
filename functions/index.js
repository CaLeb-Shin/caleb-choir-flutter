const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");
const os = require("os");
const path = require("path");
const fs = require("fs/promises");
const ffmpeg = require("fluent-ffmpeg");
const ffmpegInstaller = require("@ffmpeg-installer/ffmpeg");

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onObjectFinalized } = require("firebase-functions/v2/storage");

admin.initializeApp();
ffmpeg.setFfmpegPath(ffmpegInstaller.path);

/**
 * 카카오 액세스 토큰을 검증하고 Firebase Custom Token을 생성하는 Cloud Function
 */
exports.createKakaoCustomToken = onCall(async (request) => {
  const { accessToken } = request.data;

  if (!accessToken) {
    throw new HttpsError("invalid-argument", "카카오 액세스 토큰이 필요합니다.");
  }

  try {
    // 카카오 API로 사용자 정보 조회
    const kakaoResponse = await axios.get("https://kapi.kakao.com/v2/user/me", {
      headers: { Authorization: `Bearer ${accessToken}` },
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
 * notifications 컬렉션에 새 문서 생성 시 전체 멤버에게 푸시 알림 전송
 */
exports.sendPushNotification = onDocumentCreated("notifications/{notificationId}", async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const { title, body } = data;

  // FCM 토큰이 있는 모든 사용자 조회
  const usersSnapshot = await admin.firestore().collection("users").get();
  const tokens = [];
  usersSnapshot.docs.forEach((doc) => {
    const token = doc.data().fcmToken;
    if (token) tokens.push(token);
  });

  if (tokens.length === 0) {
    console.log("No FCM tokens found");
    return;
  }

  // 멀티캐스트 메시지 전송
  const message = {
    notification: { title: title || "갈렙찬양대", body: body || "" },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`Sent ${response.successCount}/${tokens.length} notifications`);
  } catch (error) {
    console.error("Push notification error:", error);
  }
});

/**
 * 커뮤니티 영상 원본 업로드 시 12초 이하 MP4로 서버 압축
 */
exports.compressCommunityVideo = onObjectFinalized(
  { memory: "1GiB", timeoutSeconds: 540 },
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
