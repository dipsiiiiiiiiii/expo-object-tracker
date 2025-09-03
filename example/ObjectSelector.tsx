import React, { useState } from "react";
import { View, Image, StyleSheet, Text, TouchableOpacity, Alert, ActivityIndicator, ScrollView } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { useSharedValue } from "react-native-reanimated";
import { BoundingBox, VideoObjectTrackerClass, SAMSegmentationResult } from "expo-object-tracker";

interface ObjectSelectorProps {
  thumbnailUri: string;
  videoUri: string;
  imageWidth: number;
  imageHeight: number;
  videoResolution: { width: number; height: number } | null;
  onBoundingBoxChange: (boundingBox: BoundingBox) => void;
  onObjectSegmented: (segmentationResult: SAMSegmentationResult, selectedPoint: {x: number, y: number}) => void;
  onProcessingComplete: (segmentationResult: SAMSegmentationResult, processedVideoUri?: string) => void;
  onCancel: () => void;
}

export default function ObjectSelector({
  thumbnailUri,
  videoUri,
  imageWidth,
  imageHeight,
  videoResolution,
  onBoundingBoxChange,
  onObjectSegmented,
  onProcessingComplete,
  onCancel,
}: ObjectSelectorProps) {
  const [segmentationResult, setSegmentationResult] = useState<SAMSegmentationResult | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [processingStatus, setProcessingStatus] = useState<string>('');
  const [selectedPoint, setSelectedPoint] = useState<{x: number, y: number} | null>(null);

  // scaledBox를 즉시 접근 가능한 SharedValue로 저장
  const scaledBoxShared = useSharedValue<BoundingBox | null>(null);

  // Create VideoObjectTracker instance
  const videoObjectTracker = new VideoObjectTrackerClass();

  // 전체 이미지에서 모든 객체 감지
  const detectAllObjects = async () => {
    console.log('Debug - detectAllObjects called');
    console.log('videoUri:', videoUri);
    
    if (!videoUri) {
      Alert.alert('오류', 'videoUri가 없습니다.');
      return;
    }

    setIsProcessing(true);
    setProcessingStatus('전체 이미지에서 객체를 감지하는 중...');

    try {
      
      // 첫 번째 프레임에서 모든 객체 감지 (confidence 0.5 이상만)
      const allDetections = await videoObjectTracker.detectObjectsInFrame(videoUri, 0);
      const filteredDetections = allDetections.filter(detection => detection.confidence >= 0.5);
      
      console.log('All detections count:', allDetections.length);
      console.log('Filtered detections (confidence >= 0.5):', filteredDetections);
      setDetectedObjects(filteredDetections);
      
      if (filteredDetections.length > 0) {
        setProcessingStatus(`${filteredDetections.length}개의 객체를 발견했습니다!`);
        onObjectDetected(filteredDetections, { x: 0, y: 0, width: videoResolution?.width || 1280, height: videoResolution?.height || 720 });
      } else {
        setProcessingStatus('이미지에서 객체를 찾을 수 없습니다.');
        Alert.alert('알림', '이미지에서 객체를 찾을 수 없습니다.');
      }
    } catch (error) {
      console.error('Object detection failed:', error);
      Alert.alert('오류', `객체 감지 중 오류가 발생했습니다: ${error}`);
      setProcessingStatus('객체 감지 실패');
    } finally {
      setIsProcessing(false);
    }
  };

  // 객체 추적 및 비디오 처리 시작
  const startTracking = async (detections: DetectedObject[]) => {
    setIsProcessing(true);
    setProcessingStatus('객체 추적 및 비디오 처리 중...');
    setProcessingProgress(0);

    try {
      // 가장 높은 confidence를 가진 객체의 클래스를 타겟으로 설정
      const topDetection = detections.reduce((prev, current) => 
        prev.confidence > current.confidence ? prev : current
      );

      const results = await VideoObjectTracker.detectAndTrackObjects(
        videoUri,
        {
          targetClassName: topDetection.className,
          minConfidence: 0.3,
          detectionInterval: 1 // 매 프레임 감지로 최고 정확도
        },
        (progress, status) => {
          setProcessingProgress(progress);
          setProcessingStatus(status);
        }
      );

      setProcessingStatus('비디오 처리 완료!');
      onProcessingComplete(results);
      
      Alert.alert(
        '처리 완료',
        `총 ${results.length}개의 추적 결과를 생성했습니다.`,
        [{ text: '확인' }]
      );

    } catch (error) {
      console.error('Tracking failed:', error);
      Alert.alert('오류', '객체 추적 중 오류가 발생했습니다.');
      setProcessingStatus('추적 실패');
    } finally {
      setIsProcessing(false);
    }
  };


  const clearSelection = () => {
    scaledBoxShared.value = null; // SharedValue도 초기화
    setDetectedObjects([]);
    setSelectedObjectIndex(-1);
    setProcessingStatus('');
    setProcessingProgress(0);
  };

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <View style={styles.container}>
        <Text style={styles.instructionText}>
          {detectedObjects.length === 0 ? '전체 이미지에서 객체를 감지합니다' : '추적할 객체를 탭해서 선택하세요'}
        </Text>
        
        <View style={styles.imageContainer}>
          <Image
            source={{ uri: thumbnailUri }}
            style={{
              width: imageWidth,
              height: imageHeight,
            }}
            resizeMode="contain"
          />
          
          {/* 선택된 객체의 바운딩 박스와 세그멘테이션 마스크 표시 */}
          {selectedObjectIndex >= 0 && detectedObjects[selectedObjectIndex] && videoResolution && (() => {
            const obj = detectedObjects[selectedObjectIndex];
            const scaleX = imageWidth / videoResolution.width;
            const scaleY = imageHeight / videoResolution.height;
            
            const displayBox = {
              x: obj.boundingBox.x * scaleX,
              y: obj.boundingBox.y * scaleY,
              width: obj.boundingBox.width * scaleX,
              height: obj.boundingBox.height * scaleY,
            };

            return (
              <View style={{ position: 'absolute' }}>
                {/* Segmentation mask if available */}
                {obj.segmentationMask && (
                  <Image
                    source={{ uri: obj.segmentationMask }}
                    style={[
                      styles.segmentationMask,
                      {
                        left: displayBox.x,
                        top: displayBox.y,
                        width: displayBox.width,
                        height: displayBox.height,
                      },
                    ]}
                    resizeMode="stretch"
                  />
                )}
                
                {/* Bounding box */}
                <View
                  style={[
                    styles.selectedDetectedObject,
                    {
                      left: displayBox.x,
                      top: displayBox.y,
                      width: displayBox.width,
                      height: displayBox.height,
                    },
                  ]}
                />
              </View>
            );
          })()}
        </View>

        {/* 감지된 객체들의 가로 스크롤 리스트 */}
        {detectedObjects.length > 0 && (
          <View style={styles.objectListContainer}>
            <Text style={styles.objectListTitle}>감지된 객체 ({detectedObjects.length}개)</Text>
            <ScrollView 
              horizontal 
              showsHorizontalScrollIndicator={false}
              style={styles.objectScrollView}
              contentContainerStyle={styles.objectScrollContent}
            >
              {detectedObjects.map((obj, index) => (
                <TouchableOpacity
                  key={index}
                  style={[
                    styles.objectCard,
                    selectedObjectIndex === index && styles.objectCardSelected
                  ]}
                  onPress={() => setSelectedObjectIndex(index)}
                >
                  <View style={styles.objectCardContent}>
                    <Text style={styles.objectCardClassName}>{obj.className}</Text>
                    <Text style={styles.objectCardConfidence}>
                      {(obj.confidence * 100).toFixed(1)}%
                    </Text>
                    <Text style={styles.objectCardSize}>
                      {Math.round(obj.boundingBox.width)}×{Math.round(obj.boundingBox.height)}
                    </Text>
                    {obj.segmentationMask && (
                      <Text style={styles.objectCardMask}>🎭 Seg</Text>
                    )}
                  </View>
                </TouchableOpacity>
              ))}
            </ScrollView>
          </View>
        )}


        {/* 처리 상태 표시 */}
        {isProcessing && (
          <View style={styles.processingContainer}>
            <ActivityIndicator size="large" color="#007AFF" />
            <Text style={styles.processingText}>{processingStatus}</Text>
            {processingProgress > 0 && (
              <View style={styles.progressBar}>
                <View 
                  style={[styles.progressFill, { width: `${processingProgress}%` }]} 
                />
              </View>
            )}
            {processingProgress > 0 && (
              <Text style={styles.progressText}>{Math.round(processingProgress)}%</Text>
            )}
          </View>
        )}

        {/* 버튼들 */}
        <View style={styles.buttonContainer}>
          <TouchableOpacity
            style={[styles.button, styles.cancelButton]}
            onPress={onCancel}
            disabled={isProcessing}
          >
            <Text style={styles.buttonText}>취소</Text>
          </TouchableOpacity>

          {detectedObjects.length === 0 && !isProcessing && (
            <TouchableOpacity
              style={[styles.button, styles.detectButton]}
              onPress={detectAllObjects}
            >
              <Text style={styles.buttonText}>전체 객체 감지</Text>
            </TouchableOpacity>
          )}

          {detectedObjects.length > 0 && selectedObjectIndex >= 0 && !isProcessing && (
            <TouchableOpacity
              style={[styles.button, styles.confirmButton]}
              onPress={() => startTracking([detectedObjects[selectedObjectIndex]])}
            >
              <Text style={styles.buttonText}>선택된 객체 추적</Text>
            </TouchableOpacity>
          )}

          {detectedObjects.length > 0 && !isProcessing && (
            <TouchableOpacity
              style={[styles.button, styles.clearButton]}
              onPress={clearSelection}
            >
              <Text style={styles.buttonText}>다시 감지</Text>
            </TouchableOpacity>
          )}
        </View>

        {detectedObjects.length === 0 && !isProcessing && (
          <Text style={styles.hintText}>
            전체 객체 감지 버튼을 눌러서 시작하세요
          </Text>
        )}

        {detectedObjects.length > 0 && selectedObjectIndex === -1 && !isProcessing && (
          <Text style={styles.hintText}>
            추적할 객체를 탭해서 선택하세요
          </Text>
        )}
      </View>
    </GestureHandlerRootView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 20,
    backgroundColor: "#f5f5f5",
  },
  instructionText: {
    fontSize: 16,
    color: "#333",
    textAlign: "center",
    marginBottom: 20,
    fontWeight: "500",
  },
  imageContainer: {
    position: "relative",
    marginBottom: 20,
  },
  selectedBox: {
    position: "absolute",
    borderWidth: 3,
    borderColor: "#4CAF50",
    backgroundColor: "rgba(76, 175, 80, 0.2)",
    borderStyle: "dashed",
  },
  selectionInfo: {
    backgroundColor: "white",
    padding: 15,
    borderRadius: 8,
    marginBottom: 20,
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
  },
  selectionText: {
    fontSize: 14,
    color: "#333",
    marginBottom: 5,
  },
  buttonContainer: {
    flexDirection: "row",
    justifyContent: "space-around",
    width: "100%",
    maxWidth: 300,
  },
  button: {
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
    minWidth: 80,
    alignItems: "center",
    margin: 5,
  },
  cancelButton: {
    backgroundColor: "#757575",
  },
  clearButton: {
    backgroundColor: "#FF9800",
  },
  confirmButton: {
    backgroundColor: "#4CAF50",
  },
  detectButton: {
    backgroundColor: "#007AFF",
  },
  buttonText: {
    color: "white",
    fontSize: 16,
    fontWeight: "600",
  },
  detectionResults: {
    marginTop: 10,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: "#E0E0E0",
  },
  detectionTitle: {
    fontSize: 14,
    fontWeight: "600",
    color: "#333",
    marginBottom: 5,
  },
  detectionItem: {
    fontSize: 12,
    color: "#007AFF",
    marginVertical: 2,
  },
  processingContainer: {
    backgroundColor: "white",
    padding: 20,
    borderRadius: 12,
    alignItems: "center",
    marginBottom: 20,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5,
  },
  processingText: {
    fontSize: 16,
    color: "#333",
    textAlign: "center",
    marginTop: 10,
    fontWeight: "500",
  },
  progressBar: {
    width: 200,
    height: 8,
    backgroundColor: "#E0E0E0",
    borderRadius: 4,
    marginTop: 10,
    overflow: "hidden",
  },
  progressFill: {
    height: "100%",
    backgroundColor: "#007AFF",
    borderRadius: 4,
  },
  progressText: {
    fontSize: 14,
    color: "#666",
    marginTop: 5,
    fontWeight: "600",
  },
  hintText: {
    fontSize: 14,
    color: "#666",
    textAlign: "center",
    marginTop: 10,
    fontStyle: "italic",
  },
  selectedDetectedObject: {
    position: "absolute",
    borderColor: "#4CAF50",
    backgroundColor: "rgba(76, 175, 80, 0.2)",
    borderWidth: 3,
    borderRadius: 4,
  },
  segmentationMask: {
    position: "absolute",
    opacity: 0.7,
    tintColor: "#4CAF50",
  },
  objectListContainer: {
    marginTop: 20,
    marginBottom: 20,
  },
  objectListTitle: {
    fontSize: 16,
    fontWeight: "600",
    color: "#333",
    marginBottom: 10,
    textAlign: "center",
  },
  objectScrollView: {
    flexGrow: 0,
  },
  objectScrollContent: {
    paddingHorizontal: 10,
  },
  objectCard: {
    backgroundColor: "white",
    borderRadius: 12,
    marginHorizontal: 6,
    padding: 12,
    minWidth: 100,
    alignItems: "center",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
    borderWidth: 2,
    borderColor: "transparent",
  },
  objectCardSelected: {
    borderColor: "#4CAF50",
    backgroundColor: "#F1F8E9",
  },
  objectCardContent: {
    alignItems: "center",
  },
  objectCardClassName: {
    fontSize: 14,
    fontWeight: "600",
    color: "#333",
    textAlign: "center",
    marginBottom: 4,
  },
  objectCardConfidence: {
    fontSize: 12,
    color: "#007AFF",
    fontWeight: "500",
    marginBottom: 2,
  },
  objectCardSize: {
    fontSize: 10,
    color: "#666",
    fontWeight: "400",
  },
  objectCardMask: {
    fontSize: 9,
    color: "#4CAF50",
    fontWeight: "600",
    marginTop: 2,
  },
});
