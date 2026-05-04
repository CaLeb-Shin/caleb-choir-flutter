const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
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

const NAVER_CLIENT_ID = defineSecret("NAVER_CLIENT_ID");
const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");
const KAKAO_REST_API_KEY = "1f9fa5991d000ee260fa27298f20ad8d";

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

  const { title, body } = data;

  // FCM 토큰이 있는 모든 사용자 조회
  const usersSnapshot = await admin.firestore().collection("users").get();
  const tokens = [];
  usersSnapshot.docs.forEach((doc) => {
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
