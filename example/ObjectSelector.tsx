import React, { useState } from "react";
import { View, Image, StyleSheet, Text, TouchableOpacity } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  runOnJS,
} from "react-native-reanimated";
import { BoundingBox } from "expo-object-tracker";

interface ObjectSelectorProps {
  thumbnailUri: string;
  imageWidth: number;
  imageHeight: number;
  videoResolution: { width: number; height: number } | null;
  onBoundingBoxChange: (boundingBox: BoundingBox) => void;
  onCancel: () => void;
}

export default function ObjectSelector({
  thumbnailUri,
  imageWidth,
  imageHeight,
  videoResolution,
  onBoundingBoxChange,
  onCancel,
}: ObjectSelectorProps) {
  const [isSelecting, setIsSelecting] = useState(false);
  const [selectedBox, setSelectedBox] = useState<BoundingBox | null>(null);
  const [scaledBox, setScaledBox] = useState<BoundingBox | null>(null);

  // 바운딩 박스 좌표
  const startX = useSharedValue(0);
  const startY = useSharedValue(0);
  const currentX = useSharedValue(0);
  const currentY = useSharedValue(0);

  const panGesture = Gesture.Pan()
    .onStart((event) => {
      runOnJS(setIsSelecting)(true);
      startX.value = event.x;
      startY.value = event.y;
      currentX.value = event.x;
      currentY.value = event.y;
    })
    .onUpdate((event) => {
      currentX.value = event.x;
      currentY.value = event.y;
    })
    .onEnd(() => {
      runOnJS(setIsSelecting)(false);

      // 바운딩 박스 계산
      const left = Math.min(startX.value, currentX.value);
      const top = Math.min(startY.value, currentY.value);
      const width = Math.abs(currentX.value - startX.value);
      const height = Math.abs(currentY.value - startY.value);

      // 최소 크기 체크
      if (width > 20 && height > 20) {
        // 화면 좌표를 실제 비디오 좌표로 스케일링
        let scaledBoundingBox: BoundingBox;
        
        if (videoResolution) {
          // 실제 비디오 해상도 대비 화면 표시 크기의 비율 계산
          const scaleX = videoResolution.width / imageWidth;
          const scaleY = videoResolution.height / imageHeight;
          
          scaledBoundingBox = {
            x: left * scaleX,
            y: top * scaleY,
            width: width * scaleX,
            height: height * scaleY,
          };
        } else {
          // 비디오 해상도 정보가 없으면 화면 좌표 그대로 사용
          scaledBoundingBox = { x: left, y: top, width, height };
        }

        // 선택된 박스를 state에 저장 (화면 표시용은 원본 좌표)
        runOnJS(setSelectedBox)({ x: left, y: top, width, height });
        runOnJS(setScaledBox)(scaledBoundingBox);
        
        // 실제 처리는 스케일링된 좌표로
        console.log('Screen coordinates:', { x: left, y: top, width, height });
        console.log('Scaled coordinates:', scaledBoundingBox);
      }
    });

  const animatedBoxStyle = useAnimatedStyle(() => {
    if (!isSelecting) return { display: "none" };

    const left = Math.min(startX.value, currentX.value);
    const top = Math.min(startY.value, currentY.value);
    const width = Math.abs(currentX.value - startX.value);
    const height = Math.abs(currentY.value - startY.value);

    return {
      position: "absolute",
      left,
      top,
      width,
      height,
      borderWidth: 2,
      borderColor: "#007AFF",
      backgroundColor: "rgba(0, 122, 255, 0.2)",
    };
  });

  const confirmSelection = () => {
    if (scaledBox) {
      onBoundingBoxChange(scaledBox);
    }
  };

  const clearSelection = () => {
    setSelectedBox(null);
    setScaledBox(null);
  };

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <View style={styles.container}>
        <Text style={styles.instructionText}>
          드래그해서 추적할 영역을 선택하세요
        </Text>
        
        <GestureDetector gesture={panGesture}>
          <View style={styles.imageContainer}>
            <Image
              source={{ uri: thumbnailUri }}
              style={{
                width: imageWidth,
                height: imageHeight,
              }}
              resizeMode="contain"
            />
            {/* 드래그 중인 박스 */}
            <Animated.View style={animatedBoxStyle} />
            
            {/* 선택된 박스 (확인용) */}
            {selectedBox && !isSelecting && (
              <View
                style={[
                  styles.selectedBox,
                  {
                    left: selectedBox.x,
                    top: selectedBox.y,
                    width: selectedBox.width,
                    height: selectedBox.height,
                  },
                ]}
              />
            )}
          </View>
        </GestureDetector>

        {/* 선택 상태 표시 */}
        {selectedBox && (
          <View style={styles.selectionInfo}>
            <Text style={styles.selectionText}>
              선택된 영역: {Math.round(selectedBox.width)} × {Math.round(selectedBox.height)}
            </Text>
            <Text style={styles.selectionText}>
              위치: ({Math.round(selectedBox.x)}, {Math.round(selectedBox.y)})
            </Text>
          </View>
        )}

        {/* 버튼들 */}
        <View style={styles.buttonContainer}>
          <TouchableOpacity
            style={[styles.button, styles.cancelButton]}
            onPress={onCancel}
          >
            <Text style={styles.buttonText}>취소</Text>
          </TouchableOpacity>

          {selectedBox && (
            <>
              <TouchableOpacity
                style={[styles.button, styles.clearButton]}
                onPress={clearSelection}
              >
                <Text style={styles.buttonText}>다시 선택</Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.button, styles.confirmButton]}
                onPress={confirmSelection}
              >
                <Text style={styles.buttonText}>확인</Text>
              </TouchableOpacity>
            </>
          )}
        </View>

        {!selectedBox && (
          <Text style={styles.hintText}>
            영역을 드래그해서 선택한 후 확인 버튼을 눌러주세요
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
  buttonText: {
    color: "white",
    fontSize: 16,
    fontWeight: "600",
  },
  hintText: {
    fontSize: 14,
    color: "#666",
    textAlign: "center",
    marginTop: 10,
    fontStyle: "italic",
  },
});
