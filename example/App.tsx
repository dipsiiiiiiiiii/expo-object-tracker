import React, { useState, useEffect } from "react";
import {
  Alert,
  Button,
  SafeAreaView,
  ScrollView,
  Text,
  View,
  StyleSheet,
  Image as RNImage,
  Dimensions,
  TouchableOpacity,
} from "react-native";
import * as DocumentPicker from "expo-document-picker";
import * as FileSystem from "expo-file-system";
import * as VideoThumbnails from "expo-video-thumbnails";
import { Asset } from "expo-asset";
import ExpoObjectTracker, {
  BoundingBox,
  TrackingData,
  EffectConfig,
  PreviewFrame,
  VideoObjectTrackerClass,
  SAMSegmentationResult,
} from "expo-object-tracker";

import SAMObjectSelector from "./SAMObjectSelector";

export default function App() {
  const [videoUri, setVideoUri] = useState<string>("");
  const [thumbnailUri, setThumbnailUri] = useState<string>("");
  const [segmentationResult, setSegmentationResult] = 
    useState<SAMSegmentationResult | null>(null);
  const [selectedPoint, setSelectedPoint] = 
    useState<{x: number, y: number} | null>(null);
  const [processedVideoUri, setProcessedVideoUri] = useState<string>("");
  const [status, setStatus] = useState<string>("Initializing...");
  const [showSAMSelector, setShowSAMSelector] = useState<boolean>(false);
  const [videoResolution, setVideoResolution] = useState<{
    width: number;
    height: number;
  } | null>(null);
  const [modelLoaded, setModelLoaded] = useState<boolean>(false);

  // Create VideoObjectTracker instance
  const videoObjectTracker = new VideoObjectTrackerClass();

  const { width: screenWidth } = Dimensions.get("window");
  const thumbnailWidth = screenWidth - 40;
  const thumbnailHeight = (thumbnailWidth * 9) / 16; // 16:9 비율

  // 앱 시작 시 모델 로드 (SAM 모델은 모듈에 내장됨)
  useEffect(() => {
    const initializeApp = async () => {
      try {
        setStatus("Initializing SAM model...");
        
        // SAM 모델은 iOS 모듈에 내장되어 있으므로 별도 로드 불필요
        // 테스트용으로 간단한 초기화만 수행
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        setModelLoaded(true);
        setStatus("Ready - SAM model initialized");
        console.log("SAM model ready");
      } catch (error) {
        console.error("Failed to initialize SAM model:", error);
        setStatus("Failed to initialize SAM model");
        Alert.alert("Error", "Failed to initialize SAM model.");
      }
    };
    
    initializeApp();
  }, []);

  // 비디오 선택
  const selectVideo = async () => {
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: "video/*",
        copyToCacheDirectory: true,
      });

      if (result.assets && result.assets.length > 0) {
        const uri = result.assets[0].uri;
        await loadVideo(uri);
      }
    } catch (error) {
      setStatus("Video selection failed");
      Alert.alert("Error", "Failed to select video");
      console.error("Video selection error:", error);
    }
  };

  // 테스트 비디오 로드
  const loadTestVideo = async () => {
    try {
      setStatus("Loading test video...");

      // assets에서 test-video.mp4 로드
      const asset = Asset.fromModule(require("./assets/test-video.mp4"));
      await asset.downloadAsync();

      await loadVideo(asset.localUri || asset.uri);
    } catch (error) {
      setStatus("Test video loading failed");
      Alert.alert("Error", "Failed to load test video");
      console.error("Test video loading error:", error);
    }
  };

  // 공통 비디오 로딩 로직
  const loadVideo = async (uri: string) => {
    try {
      setVideoUri(uri);
      setStatus("Generating thumbnail...");

      // 썸네일 생성
      const { uri: thumbnail } = await VideoThumbnails.getThumbnailAsync(uri, {
        time: 0,
        quality: 0.8,
      });

      setThumbnailUri(thumbnail);

      // 비디오 해상도 가져오기
      const resolution = await videoObjectTracker.getVideoResolution(uri);
      setVideoResolution(resolution);
      console.log("Video resolution:", resolution);

      setStatus("Video loaded - Ready to select object");
      console.log("Video loaded:", uri);
      console.log("Thumbnail:", thumbnail);

      // 이전 결과들 초기화
      setSegmentationResult(null);
      setSelectedPoint(null);
      setProcessedVideoUri("");
    } catch (error) {
      setStatus("Video processing failed");
      Alert.alert("Error", "Failed to process video");
      console.error("Video processing error:", error);
    }
  };

  // SAM 객체 선택 화면 표시
  const showSAMObjectSelection = () => {
    if (!thumbnailUri) {
      Alert.alert("Error", "Please select a video first");
      return;
    }
    setShowSAMSelector(true);
  };

  // SAM 세그먼테이션 완료 콜백
  const onObjectSegmented = (result: SAMSegmentationResult, point: {x: number, y: number}) => {
    setSegmentationResult(result);
    setSelectedPoint(point);
    setShowSAMSelector(false);
    setStatus(`Object segmented with ${Math.round(result.confidence * 100)}% confidence`);
    console.log("SAM Segmentation Result:", result);
    console.log("Selected Point:", point);
  };

  // 효과 적용하기
  const applyEffectToSegmentation = async () => {
    if (!segmentationResult) {
      Alert.alert("Error", "No segmentation result available");
      return;
    }

    try {
      setStatus("Applying effect to segmented object...");
      
      // 여기서 실제 효과 적용 로직 구현
      // 현재는 placeholder
      console.log("Applying effect with mask:", segmentationResult.maskUri);
      
      // 임시로 성공 메시지
      await new Promise(resolve => setTimeout(resolve, 1000));
      setStatus("Effect applied successfully!");
      Alert.alert("Success", "Effect applied to the segmented object!");
      
    } catch (error) {
      setStatus("Failed to apply effect");
      Alert.alert("Error", "Failed to apply effect: " + error);
    }
  };

  // 객체 추적
  const trackObject = async () => {
    if (!objectId) {
      Alert.alert("Error", "Please select object first");
      return;
    }

    try {
      setStatus("Tracking object...");

      const results = await ExpoObjectTracker.trackObject(videoUri, objectId);
      setTrackingResults(results);
      setStatus(`Tracking completed - ${results.length} frames`);

      // 미리보기 프레임 생성 (5개 프레임)
      setStatus("Generating preview frames...");
      const frames = await ExpoObjectTracker.generatePreviewFrames(
        videoUri,
        results,
        5
      );
      setPreviewFrames(frames);

      setStatus(`Tracking completed - Ready for effects preview`);
      Alert.alert("Success", `Tracked object in ${results.length} frames`);
      console.log("Tracking results:", results.slice(0, 5)); // 첫 5프레임만 로그
    } catch (error) {
      setStatus("Tracking failed");
      Alert.alert("Error", "Failed to track object: " + error);
      console.error("Object tracking error:", error);
    }
  };

  // 효과 미리보기
  const previewEffect = async (
    effectConfig: EffectConfig,
    effectName: string
  ) => {
    if (previewFrames.length === 0) {
      Alert.alert("Error", "Please track object first");
      return;
    }

    try {
      setStatus(`Generating ${effectName} preview...`);
      setCurrentPreviewEffect(effectConfig);

      const newPreviewImages: { [key: string]: string } = {};

      // 각 미리보기 프레임에 효과 적용
      for (const frame of previewFrames) {
        const processedUri = await ExpoObjectTracker.applyEffectToFrame(
          frame.imageUri,
          frame.boundingBox,
          effectConfig
        );
        newPreviewImages[`${effectName}-${frame.frameIndex}`] = processedUri;
      }

      setPreviewImages(newPreviewImages);
      setStatus(`${effectName} preview ready`);
    } catch (error) {
      setStatus("Preview generation failed");
      Alert.alert(
        "Error",
        `Failed to generate ${effectName} preview: ` + error
      );
      console.error("Preview generation error:", error);
    }
  };

  // 최종 비디오 저장
  const saveVideo = async () => {
    if (!currentPreviewEffect || trackingResults.length === 0) {
      Alert.alert("Error", "Please preview an effect first");
      return;
    }

    try {
      setStatus("Saving video with effects...");

      const processedUri = await ExpoObjectTracker.applyEffectToTrackedObject(
        videoUri,
        trackingResults,
        currentPreviewEffect
      );

      setProcessedVideoUri(processedUri);
      setStatus("Video saved successfully");

      Alert.alert("Success", `Video saved at: ${processedUri}`);
      console.log("Processed video URI:", processedUri);
    } catch (error) {
      setStatus("Video save failed");
      Alert.alert("Error", "Failed to save video: " + error);
      console.error("Video save error:", error);
    }
  };

  // 각 효과별 미리보기 핸들러들
  const previewBlurEffect = () =>
    previewEffect({ type: "blur", intensity: 8 }, "blur");
  const previewMosaicEffect = () =>
    previewEffect({ type: "mosaic", blockSize: 15 }, "mosaic");
  const previewEmojiEffect = () =>
    previewEffect({ type: "emoji", emoji: "😎", scale: 1.5 }, "emoji");
  const previewColorEffect = () =>
    previewEffect({ type: "color", color: "#FF0000", opacity: 0.7 }, "color");

  // SAM 객체 선택기 표시
  if (showSAMSelector && thumbnailUri) {
    return (
      <SafeAreaView style={styles.container}>
        <SAMObjectSelector
          thumbnailUri={thumbnailUri}
          videoUri={videoUri}
          imageWidth={thumbnailWidth}
          imageHeight={thumbnailHeight}
          onObjectSegmented={onObjectSegmented}
          onCancel={() => setShowSAMSelector(false)}
        />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.container}>
        <Text style={styles.header}>🤖 AI 객체 세그먼테이션 & 블러</Text>

        <Group name="Status">
          <Text style={styles.statusText}>{status}</Text>
        </Group>

        <Group name="1. 비디오 선택">
          <View style={styles.effectButtonsContainer}>
            <Button 
              title="갤러리에서 선택" 
              onPress={selectVideo} 
              disabled={!modelLoaded}
            />
            <Button 
              title="테스트 비디오 사용" 
              onPress={loadTestVideo} 
              disabled={!modelLoaded}
            />
          </View>
          {!modelLoaded ? (
            <Text style={styles.infoText}>SAM 모델 초기화 중...</Text>
          ) : videoUri ? (
            <Text style={styles.infoText}>✅ 비디오 로드됨</Text>
          ) : null}
        </Group>

        <Group name="2. AI 객체 선택">
          <Button
            title="🎯 객체 터치해서 선택하기"
            onPress={showSAMObjectSelection}
            disabled={!thumbnailUri}
          />
          <Text style={styles.hintText}>
            💡 Segment Anything AI가 터치한 객체를 정밀하게 찾습니다
          </Text>
          
          {segmentationResult ? (
            <View>
              <Text style={styles.infoText}>✅ 객체 세그먼테이션 완료!</Text>
              <Text style={styles.resultText}>
                신뢰도: {Math.round(segmentationResult.confidence * 100)}%
              </Text>
              <Text style={styles.resultText}>
                선택된 위치: ({selectedPoint?.x.toFixed(0)}, {selectedPoint?.y.toFixed(0)})
              </Text>
            </View>
          ) : null}
        </Group>

        {segmentationResult && (
          <Group name="3. 효과 적용">
            <View style={styles.effectButtonsContainer}>
              <Button
                title="🌀 블러 효과"
                onPress={applyEffectToSegmentation}
              />
              <Button
                title="🔳 모자이크"
                onPress={applyEffectToSegmentation}
              />
            </View>
            <Text style={styles.hintText}>
              선택된 객체 영역에만 효과가 정밀하게 적용됩니다
            </Text>
          </Group>
        )}

        {processedVideoUri && (
          <Group name="결과">
            <Text style={styles.infoText}>✅ 효과 적용 완료!</Text>
            <Text style={styles.resultText}>
              처리된 비디오: {processedVideoUri}
            </Text>
          </Group>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function Group(props: { name: string; children: React.ReactNode }) {
  return (
    <View style={styles.group}>
      <Text style={styles.groupHeader}>{props.name}</Text>
      {props.children}
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    fontSize: 24,
    fontWeight: "bold" as const,
    margin: 20,
    textAlign: "center" as const,
    color: "#333",
  },
  groupHeader: {
    fontSize: 18,
    fontWeight: "bold" as const,
    marginBottom: 15,
    color: "#444",
  },
  group: {
    margin: 15,
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 20,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  container: {
    flex: 1,
    backgroundColor: "#f5f5f5",
  },
  statusText: {
    fontSize: 16,
    fontWeight: "500" as const,
    color: "#007AFF",
    textAlign: "center" as const,
  },
  infoText: {
    fontSize: 14,
    color: "#28a745",
    marginTop: 10,
    textAlign: "center" as const,
  },
  resultText: {
    fontSize: 12,
    color: "#666",
    marginTop: 5,
  },
  selectorContainer: {
    flex: 1,
    padding: 20,
    alignItems: "center" as const,
  },
  instructionText: {
    fontSize: 16,
    color: "#666",
    textAlign: "center" as const,
    marginBottom: 20,
  },
  buttonContainer: {
    marginTop: 20,
    width: "100%",
  },
  effectButtonsContainer: {
    flexDirection: "row" as const,
    justifyContent: "space-around",
    marginBottom: 10,
  },
  previewContainer: {
    marginTop: 15,
    padding: 10,
    backgroundColor: "#f8f8f8",
    borderRadius: 8,
  },
  previewTitle: {
    fontSize: 14,
    fontWeight: "600" as const,
    marginBottom: 10,
    color: "#333",
  },
  previewImage: {
    width: 120,
    height: 90,
    marginRight: 10,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: "#ddd",
  },
  previewImageContainer: {
    marginBottom: 20,
    borderRadius: 8,
    overflow: "hidden",
    borderWidth: 2,
    borderColor: "#4CAF50",
  },
  detectionInfo: {
    backgroundColor: "white",
    padding: 15,
    borderRadius: 8,
    marginBottom: 20,
    alignItems: "center" as const,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
  },
  detectionText: {
    fontSize: 14,
    color: "#333",
    marginBottom: 5,
    fontWeight: "500" as const,
  },
  confirmButtonContainer: {
    flexDirection: "row" as const,
    justifyContent: "space-around",
    width: "100%",
    maxWidth: 300,
  },
  retryButton: {
    backgroundColor: "#FF9800",
  },
  button: {
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
    minWidth: 80,
    alignItems: "center" as const,
    margin: 5,
  },
  buttonText: {
    color: "white",
    fontSize: 16,
    fontWeight: "600" as const,
  },
  confirmButton: {
    backgroundColor: "#4CAF50",
  },
  hintText: {
    fontSize: 12,
    color: "#6c757d",
    textAlign: "center" as const,
    marginTop: 8,
    fontStyle: "italic" as const,
  },
});
