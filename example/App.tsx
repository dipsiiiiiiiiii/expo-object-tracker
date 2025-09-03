import React, { useState } from "react";
import {
  Alert,
  Button,
  SafeAreaView,
  ScrollView,
  Text,
  View,
  StyleSheet,
  Image,
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
} from "expo-object-tracker";

import ObjectSelector from "./ObjectSelector";

export default function App() {
  const [videoUri, setVideoUri] = useState<string>("");
  const [thumbnailUri, setThumbnailUri] = useState<string>("");
  const [objectId, setObjectId] = useState<string>("");
  const [selectedBoundingBox, setSelectedBoundingBox] =
    useState<BoundingBox | null>(null);
  const [trackingResults, setTrackingResults] = useState<TrackingData[]>([]);
  const [previewFrames, setPreviewFrames] = useState<PreviewFrame[]>([]);
  const [currentPreviewEffect, setCurrentPreviewEffect] =
    useState<EffectConfig | null>(null);
  const [previewImages, setPreviewImages] = useState<{ [key: string]: string }>(
    {}
  );
  const [processedVideoUri, setProcessedVideoUri] = useState<string>("");
  const [status, setStatus] = useState<string>("Ready");
  const [showObjectSelector, setShowObjectSelector] = useState<boolean>(false);
  const [showObjectPreview, setShowObjectPreview] = useState<boolean>(false);
  const [detectedObjectPreview, setDetectedObjectPreview] =
    useState<string>("");
  const [videoResolution, setVideoResolution] = useState<{
    width: number;
    height: number;
  } | null>(null);

  const { width: screenWidth } = Dimensions.get("window");
  const thumbnailWidth = screenWidth - 40;
  const thumbnailHeight = (thumbnailWidth * 9) / 16; // 16:9 비율

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
      const resolution = await ExpoObjectTracker.getVideoResolution(uri);
      setVideoResolution(resolution);
      console.log("Video resolution:", resolution);

      setStatus("Video loaded - Ready to select object");
      console.log("Video loaded:", uri);
      console.log("Thumbnail:", thumbnail);

      // 이전 결과들 초기화
      setObjectId("");
      setSelectedBoundingBox(null);
      setTrackingResults([]);
      setProcessedVideoUri("");
    } catch (error) {
      setStatus("Video processing failed");
      Alert.alert("Error", "Failed to process video");
      console.error("Video processing error:", error);
    }
  };

  // 객체 선택 화면 표시
  const showObjectSelection = () => {
    if (!thumbnailUri) {
      Alert.alert("Error", "Please select a video first");
      return;
    }
    setShowObjectSelector(true);
  };

  // 바운딩 박스 선택 완료
  const onBoundingBoxSelected = async (boundingBox: BoundingBox) => {
    try {
      setStatus("Selecting object...");
      setSelectedBoundingBox(boundingBox);

      const id = await ExpoObjectTracker.selectObject(
        videoUri,
        0, // 첫 번째 프레임
        boundingBox
      );

      setObjectId(id);

      // 객체 인식 미리보기 생성
      setStatus("Generating object preview...");
      const previewUri = await ExpoObjectTracker.generateObjectPreview(
        videoUri,
        id
      );
      setDetectedObjectPreview(previewUri);

      setShowObjectSelector(false);
      setShowObjectPreview(true);
      setStatus("Object detected - Please confirm");
      console.log("Object ID:", id);
      console.log("Bounding Box:", boundingBox);
    } catch (error) {
      setStatus("Object selection failed");
      Alert.alert("Error", "Failed to select object: " + error);
      console.error("Object selection error:", error);
    }
  };

  // 객체 인식 확인
  const confirmObjectDetection = () => {
    setShowObjectPreview(false);
    setStatus("Object confirmed - Ready to track");
    Alert.alert("Success", "Object detection confirmed");
  };

  // 객체 다시 선택
  const retryObjectSelection = () => {
    setShowObjectPreview(false);
    setShowObjectSelector(true);
    setObjectId("");
    setSelectedBoundingBox(null);
    setDetectedObjectPreview("");
    setStatus("Ready to select object again");
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

  if (showObjectSelector && thumbnailUri) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.selectorContainer}>
          <Text style={styles.header}>객체 선택하기</Text>
          <Text style={styles.instructionText}>
            블러 처리할 객체를 드래그해서 선택하세요
          </Text>

          <ObjectSelector
            thumbnailUri={thumbnailUri}
            videoUri={videoUri}
            imageWidth={thumbnailWidth}
            imageHeight={thumbnailHeight}
            videoResolution={videoResolution}
            onBoundingBoxChange={onBoundingBoxSelected}
            onObjectDetected={(detections, selectedBox) => {
              console.log('Objects detected:', detections);
              console.log('In selected region:', selectedBox);
            }}
            onProcessingComplete={(results, processedVideoUri) => {
              console.log('Processing complete:', results.length, 'tracked objects');
              if (processedVideoUri) {
                console.log('Processed video:', processedVideoUri);
              }
            }}
            onCancel={() => setShowObjectSelector(false)}
          />
        </View>
      </SafeAreaView>
    );
  }

  if (showObjectPreview && detectedObjectPreview) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.selectorContainer}>
          <Text style={styles.header}>객체 인식 확인</Text>
          <Text style={styles.instructionText}>
            Vision Framework가 인식한 객체입니다. 맞다면 확인을 눌러주세요.
          </Text>

          <View style={styles.previewImageContainer}>
            <Image
              source={{ uri: detectedObjectPreview }}
              style={{
                width: thumbnailWidth,
                height: thumbnailHeight,
              }}
              resizeMode="contain"
            />
          </View>

          {selectedBoundingBox && (
            <View style={styles.detectionInfo}>
              <Text style={styles.detectionText}>
                인식된 영역 크기: {Math.round(selectedBoundingBox.width)} ×{" "}
                {Math.round(selectedBoundingBox.height)}
              </Text>
              <Text style={styles.detectionText}>
                위치: ({Math.round(selectedBoundingBox.x)},{" "}
                {Math.round(selectedBoundingBox.y)})
              </Text>
            </View>
          )}

          <View style={styles.confirmButtonContainer}>
            <TouchableOpacity
              style={[styles.button, styles.retryButton]}
              onPress={retryObjectSelection}
            >
              <Text style={styles.buttonText}>다시 선택</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.button, styles.confirmButton]}
              onPress={confirmObjectDetection}
            >
              <Text style={styles.buttonText}>확인</Text>
            </TouchableOpacity>
          </View>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.container}>
        <Text style={styles.header}>객체 추적 & 블러 처리</Text>

        <Group name="Status">
          <Text style={styles.statusText}>{status}</Text>
        </Group>

        <Group name="1. 비디오 선택">
          <View style={styles.effectButtonsContainer}>
            <Button title="갤러리에서 선택" onPress={selectVideo} />
            <Button title="테스트 비디오 사용" onPress={loadTestVideo} />
          </View>
          {videoUri ? (
            <Text style={styles.infoText}>✓ 비디오 로드됨</Text>
          ) : null}
        </Group>

        <Group name="2. 추적할 객체 선택">
          <Button
            title="객체 영역 선택하기"
            onPress={showObjectSelection}
            disabled={!thumbnailUri}
          />
          {objectId ? (
            <View>
              <Text style={styles.infoText}>✓ 객체 영역 선택됨</Text>
              {selectedBoundingBox && (
                <Text style={styles.resultText}>
                  위치: ({Math.round(selectedBoundingBox.x)},{" "}
                  {Math.round(selectedBoundingBox.y)}) 크기:{" "}
                  {Math.round(selectedBoundingBox.width)}×
                  {Math.round(selectedBoundingBox.height)}
                </Text>
              )}
            </View>
          ) : null}
        </Group>

        <Group name="3. 객체 추적">
          <Button
            title="객체 추적하기"
            onPress={trackObject}
            disabled={!objectId}
          />
          {trackingResults.length > 0 ? (
            <Text style={styles.infoText}>
              ✓ {trackingResults.length}프레임에서 추적됨
            </Text>
          ) : null}
        </Group>

        <Group name="4. 효과 미리보기">
          <View style={styles.effectButtonsContainer}>
            <Button
              title="블러"
              onPress={previewBlurEffect}
              disabled={previewFrames.length === 0}
            />
            <Button
              title="모자이크"
              onPress={previewMosaicEffect}
              disabled={previewFrames.length === 0}
            />
          </View>
          <View style={styles.effectButtonsContainer}>
            <Button
              title="이모지 😎"
              onPress={previewEmojiEffect}
              disabled={previewFrames.length === 0}
            />
            <Button
              title="빨간색"
              onPress={previewColorEffect}
              disabled={previewFrames.length === 0}
            />
          </View>

          {/* 미리보기 이미지들 */}
          {Object.keys(previewImages).length > 0 && (
            <View style={styles.previewContainer}>
              <Text style={styles.previewTitle}>효과 미리보기:</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false}>
                {Object.entries(previewImages).map(([key, uri]) => (
                  <Image
                    key={key}
                    source={{ uri }}
                    style={styles.previewImage}
                    resizeMode="contain"
                  />
                ))}
              </ScrollView>
            </View>
          )}
        </Group>

        {currentPreviewEffect && (
          <Group name="5. 비디오 저장">
            <Button
              title="효과 적용된 비디오 저장하기"
              onPress={saveVideo}
              disabled={!currentPreviewEffect}
            />
            {processedVideoUri ? (
              <Text style={styles.infoText}>✓ 비디오 저장 완료</Text>
            ) : null}
          </Group>
        )}

        {processedVideoUri && (
          <Group name="결과">
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
});
