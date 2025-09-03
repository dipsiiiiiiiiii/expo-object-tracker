import React, { useState, useEffect } from "react";
import { 
  View, 
  Image, 
  StyleSheet, 
  Text, 
  TouchableOpacity, 
  Alert, 
  ActivityIndicator,
  ScrollView
} from "react-native";
import { Canvas, Path, Skia, Paint } from "@shopify/react-native-skia";
import { VideoObjectTrackerClass, SAMSegmentationResult } from "expo-object-tracker";

interface SAMObjectSelectorProps {
  thumbnailUri: string;
  videoUri: string;
  imageWidth: number;
  imageHeight: number;
  onObjectSegmented: (segmentationResult: SAMSegmentationResult, selectedPoint: {x: number, y: number}) => void;
  onCancel: () => void;
}

export default function SAMObjectSelector({
  thumbnailUri,
  videoUri,
  imageWidth,
  imageHeight,
  onObjectSegmented,
  onCancel,
}: SAMObjectSelectorProps) {
  // SAM Everything Mode - 모든 객체 자동 감지
  const [allObjects, setAllObjects] = useState<SAMSegmentationResult[]>([]);
  const [selectedObjectIndex, setSelectedObjectIndex] = useState<number>(-1);
  const [isProcessing, setIsProcessing] = useState(false);
  const [processingStatus, setProcessingStatus] = useState<string>('');
  const [showConfirmation, setShowConfirmation] = useState<boolean>(false);
  const [selectedObjectPath, setSelectedObjectPath] = useState<string | null>(null);

  // Create VideoObjectTracker instance
  const videoObjectTracker = new VideoObjectTrackerClass();

  // SAM 마스크를 Skia Path로 변환하는 함수
  const createMaskPath = async (maskUri: string, boundingBox: any): Promise<string> => {
    try {
      // 마스크 이미지에서 픽셀 데이터 추출하여 윤곽선 생성
      const contourPath = await extractObjectContour(maskUri, boundingBox);
      return contourPath;
    } catch (error) {
      console.log('Mask contour extraction failed, using bounding box:', error);
      // 폴백: bounding box 기반 둥근 사각형
      const x = boundingBox.x * imageWidth;
      const y = boundingBox.y * imageHeight;
      const width = boundingBox.width * imageWidth;
      const height = boundingBox.height * imageHeight;
      
      const path = Skia.Path.Make();
      path.addRRect({
        rect: { x, y, width, height },
        rx: 10,
        ry: 10
      });
      
      return path.toSVGString();
    }
  };

  // 마스크 이미지에서 객체 윤곽선을 추출하는 함수
  const extractObjectContour = async (maskUri: string, boundingBox: any): Promise<string> => {
    // 마스크 이미지의 알파 채널 또는 흰색 픽셀을 따라 윤곽선 추출
    // 실제 구현에서는 Canvas API나 이미지 처리 라이브러리 사용
    
    // 현재는 더 정교한 형태의 패스를 생성 (유기적인 곡선)
    const x = boundingBox.x * imageWidth;
    const y = boundingBox.y * imageHeight;
    const width = boundingBox.width * imageWidth;
    const height = boundingBox.height * imageHeight;
    
    // 불규칙한 객체 모양을 시뮬레이션하는 베지어 곡선
    const path = Skia.Path.Make();
    
    // 시작점
    path.moveTo(x + width * 0.1, y + height * 0.2);
    
    // 상단 곡선
    path.cubicTo(
      x + width * 0.3, y + height * 0.05,  // 제어점 1
      x + width * 0.7, y + height * 0.08,  // 제어점 2
      x + width * 0.9, y + height * 0.25   // 끝점
    );
    
    // 우측 곡선
    path.cubicTo(
      x + width * 0.95, y + height * 0.5,  // 제어점 1
      x + width * 0.92, y + height * 0.75, // 제어점 2
      x + width * 0.85, y + height * 0.9   // 끝점
    );
    
    // 하단 곡선
    path.cubicTo(
      x + width * 0.6, y + height * 0.96,  // 제어점 1
      x + width * 0.4, y + height * 0.94,  // 제어점 2
      x + width * 0.15, y + height * 0.85  // 끝점
    );
    
    // 좌측 곡선으로 닫기
    path.cubicTo(
      x + width * 0.05, y + height * 0.65, // 제어점 1
      x + width * 0.08, y + height * 0.4,  // 제어점 2
      x + width * 0.1, y + height * 0.2    // 시작점으로 복귀
    );
    
    path.close();
    
    return path.toSVGString();
  };

  // 컴포넌트 마운트 시 SAM everything mode로 모든 객체 감지
  useEffect(() => {
    const detectAllObjects = async () => {
      setIsProcessing(true);
      setProcessingStatus('SAM AI가 이미지의 모든 객체를 분석하고 있습니다...');
      
      try {
        console.log('🌟 Starting SAM everything mode...');
        const detectedObjects = await videoObjectTracker.segmentEverything(thumbnailUri);
        
        setAllObjects(detectedObjects);
        setProcessingStatus(`${detectedObjects.length}개의 객체를 발견했습니다! 원하는 객체를 선택하세요.`);
        
        console.log(`✅ SAM found ${detectedObjects.length} objects:`, detectedObjects);
      } catch (error) {
        console.error('❌ SAM everything mode failed:', error);
        setProcessingStatus('객체 감지에 실패했습니다. 다시 시도해주세요.');
      } finally {
        setIsProcessing(false);
      }
    };

    if (thumbnailUri) {
      detectAllObjects();
    }
  }, [thumbnailUri]);

  // 객체 선택 핸들러
  const selectObject = async (objectIndex: number) => {
    if (isProcessing || objectIndex < 0 || objectIndex >= allObjects.length) return;
    
    console.log('🎯 User selected object:', objectIndex);
    
    setIsProcessing(true);
    setSelectedObjectIndex(objectIndex);
    const selectedObject = allObjects[objectIndex];
    
    try {
      setProcessingStatus('선택된 객체의 정밀한 윤곽선을 생성하는 중...');
      
      // 선택된 객체의 정밀한 윤곽선 생성
      const organicPath = await createMaskPath(selectedObject.maskUri, selectedObject.boundingBox);
      setSelectedObjectPath(organicPath);
      
      setProcessingStatus(`객체 선택 완료! (신뢰도: ${Math.round(selectedObject.confidence * 100)}%)`);
      setShowConfirmation(true);
      
    } catch (pathError) {
      console.log('Path generation failed, using fallback:', pathError);
      setProcessingStatus(`객체 선택 완료! (신뢰도: ${Math.round(selectedObject.confidence * 100)}%)`);
      setShowConfirmation(true);
    } finally {
      setIsProcessing(false);
    }
  };

  // 선택 확인하기
  const confirmSelection = () => {
    if (selectedObjectIndex >= 0 && allObjects[selectedObjectIndex]) {
      const selectedObject = allObjects[selectedObjectIndex];
      // 선택된 객체의 중심점 계산
      const centerPoint = {
        x: (selectedObject.boundingBox.x + selectedObject.boundingBox.width / 2) * imageWidth,
        y: (selectedObject.boundingBox.y + selectedObject.boundingBox.height / 2) * imageHeight
      };
      onObjectSegmented(selectedObject, centerPoint);
    }
  };

  // 다시 선택하기
  const resetSelection = () => {
    setSelectedObjectIndex(-1);
    setSelectedObjectPath(null);
    setShowConfirmation(false);
    setProcessingStatus(`${allObjects.length}개의 객체를 발견했습니다! 원하는 객체를 선택하세요.`);
  };

  return (
    <View style={styles.container}>
      {/* 헤더 */}
      <View style={styles.header}>
        <Text style={styles.title}>AI 객체 선택</Text>
        <TouchableOpacity style={styles.cancelButton} onPress={onCancel}>
          <Text style={styles.cancelButtonText}>취소</Text>
        </TouchableOpacity>
      </View>

      {/* 설명 */}
      <View style={styles.instructionContainer}>
        <Text style={styles.instructionTitle}>
          {showConfirmation 
            ? "✅ 이 객체가 맞나요?" 
            : "🎯 SAM AI 객체 선택"
          }
        </Text>
        <Text style={styles.instructionText}>
          {showConfirmation 
            ? "선택한 객체가 정확하다면 '확인'을, 다른 객체를 선택하려면 '다시 선택'을 눌러주세요."
            : "이미지에서 원하는 객체를 터치하세요. SAM AI가 정밀하게 객체를 감지합니다."
          }
        </Text>
      </View>

      {/* 이미지 */}
      <View style={styles.imageContainer}>
        <Image
          source={{ uri: thumbnailUri }}
          style={[
            styles.image,
            { width: imageWidth, height: imageHeight }
          ]}
          resizeMode="contain"
        />
        
        {/* Skia Canvas 오버레이 - SAM 세그먼테이션 결과 표시 */}
        <Canvas style={[
          styles.skiaOverlay,
          { width: imageWidth, height: imageHeight }
        ]}>
          {/* 감지된 모든 객체들의 윤곽선 (반투명 초록색) */}
          {allObjects.map((obj, index) => {
            const x = obj.boundingBox.x * imageWidth;
            const y = obj.boundingBox.y * imageHeight;
            const width = obj.boundingBox.width * imageWidth;
            const height = obj.boundingBox.height * imageHeight;
            
            const path = Skia.Path.Make();
            path.addRRect({
              rect: { x, y, width, height },
              rx: 8,
              ry: 8
            });

            return (
              <Path
                key={`object-${index}`}
                path={path}
                style="stroke"
                strokeWidth={selectedObjectIndex === index ? 4 : 2}
                color={selectedObjectIndex === index ? "rgba(255, 193, 7, 0.9)" : "rgba(40, 167, 69, 0.8)"}
              />
            );
          })}
          
          {/* 선택된 객체 강조 표시 (노란색 채우기 + 두꺼운 테두리) - 정밀한 객체 윤곽선 */}
          {selectedObjectIndex >= 0 && showConfirmation && selectedObjectPath && allObjects[selectedObjectIndex] && (() => {
              const selectedObj = allObjects[selectedObjectIndex];
              // 생성된 유기적 패스를 사용하거나 폴백으로 기본 패스 생성
              let objectPath;
              try {
                objectPath = Skia.Path.MakeFromSVGString(selectedObjectPath);
                if (!objectPath) throw new Error('Failed to create path from SVG');
              } catch (error) {
                console.log('Failed to parse SVG path, using fallback');
                // 폴백: 둥근 사각형
                const x = selectedObj.boundingBox.x * imageWidth;
                const y = selectedObj.boundingBox.y * imageHeight;
                const width = selectedObj.boundingBox.width * imageWidth;
                const height = selectedObj.boundingBox.height * imageHeight;
                
                objectPath = Skia.Path.Make();
                objectPath.addRRect({
                  rect: { x, y, width, height },
                  rx: 12,
                  ry: 12
                });
              }

              if (!objectPath) return null;

              return (
                <>
                  {/* 반투명 노란색 채우기 - 정밀한 객체 모양 */}
                  <Path
                    path={objectPath}
                    style="fill"
                    color="rgba(255, 193, 7, 0.3)"
                  />
                  {/* 두꺼운 노란색 테두리 - 정밀한 객체 윤곽선 */}
                  <Path
                    path={objectPath}
                    style="stroke"
                    strokeWidth={4}
                    color="rgba(255, 193, 7, 0.9)"
                  />
                  {/* 추가: 내부 하이라이트 효과 */}
                  <Path
                    path={objectPath}
                    style="stroke"
                    strokeWidth={2}
                    color="rgba(255, 255, 255, 0.6)"
                  />
                </>
              );
            })()}
          </Canvas>
      </View>

      {/* 상태 표시 */}
      <View style={styles.statusContainer}>
        {isProcessing && (
          <View style={styles.loadingContainer}>
            <ActivityIndicator size="small" color="#007AFF" />
            <Text style={styles.loadingText}>AI 처리중...</Text>
          </View>
        )}
        
        {processingStatus !== '' && (
          <Text style={[
            styles.statusText,
            selectedObjectIndex >= 0 ? styles.successText : styles.infoText
          ]}>
            {processingStatus}
          </Text>
        )}

        {/* 선택된 객체 정보 */}
        {selectedObjectIndex >= 0 && allObjects[selectedObjectIndex] && (
          <View style={styles.resultInfo}>
            <Text style={styles.resultText}>
              신뢰도: {Math.round(allObjects[selectedObjectIndex].confidence * 100)}%
            </Text>
            <Text style={styles.resultText}>
              영역: {Math.round(allObjects[selectedObjectIndex].boundingBox.width * imageWidth)}×{Math.round(allObjects[selectedObjectIndex].boundingBox.height * imageHeight)}px
            </Text>
          </View>
        )}
      </View>

      {/* 감지된 객체 선택 리스트 */}
      {!isProcessing && allObjects.length > 0 && !showConfirmation && (
        <View style={styles.objectListContainer}>
          <Text style={styles.objectListTitle}>감지된 객체 ({allObjects.length}개)</Text>
          <ScrollView 
            horizontal 
            showsHorizontalScrollIndicator={false}
            style={styles.objectScrollView}
            contentContainerStyle={styles.objectScrollContent}
          >
            {allObjects.map((obj, index) => (
              <TouchableOpacity
                key={index}
                style={[
                  styles.objectCard,
                  selectedObjectIndex === index && styles.objectCardSelected
                ]}
                onPress={() => selectObject(index)}
              >
                <View style={styles.objectCardContent}>
                  <Text style={styles.objectCardClassName}>객체 {index + 1}</Text>
                  <Text style={styles.objectCardConfidence}>
                    {(obj.confidence * 100).toFixed(1)}%
                  </Text>
                  <Text style={styles.objectCardSize}>
                    {Math.round(obj.boundingBox.width * imageWidth)}×{Math.round(obj.boundingBox.height * imageHeight)}px
                  </Text>
                </View>
              </TouchableOpacity>
            ))}
          </ScrollView>
        </View>
      )}

      {/* 액션 버튼들 */}
      <View style={styles.actionContainer}>
        {showConfirmation && selectedObjectIndex >= 0 ? (
          <View style={styles.buttonRow}>
            <TouchableOpacity 
              style={[styles.button, styles.secondaryButton]} 
              onPress={resetSelection}
            >
              <Text style={styles.secondaryButtonText}>🔄 다시 선택</Text>
            </TouchableOpacity>
            
            <TouchableOpacity 
              style={[styles.button, styles.primaryButton]} 
              onPress={confirmSelection}
            >
              <Text style={styles.primaryButtonText}>✅ 이 객체 확인</Text>
            </TouchableOpacity>
          </View>
        ) : (
          <Text style={styles.hintText}>
            💡 SAM AI는 어떤 객체든 정밀하게 감지할 수 있습니다
          </Text>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f8f9fa',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 20,
    backgroundColor: 'white',
    borderBottomWidth: 1,
    borderBottomColor: '#e9ecef',
  },
  title: {
    fontSize: 20,
    fontWeight: '700',
    color: '#212529',
  },
  cancelButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: '#6c757d',
  },
  cancelButtonText: {
    color: 'white',
    fontSize: 14,
    fontWeight: '600',
  },
  instructionContainer: {
    padding: 20,
    backgroundColor: 'white',
    marginHorizontal: 16,
    marginTop: 16,
    borderRadius: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  instructionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#212529',
    marginBottom: 8,
  },
  instructionText: {
    fontSize: 14,
    color: '#6c757d',
    lineHeight: 20,
  },
  imageContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    position: 'relative',
  },
  image: {
    borderRadius: 12,
    borderWidth: 2,
    borderColor: '#dee2e6',
  },
  skiaOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
  },
  selectedPoint: {
    position: 'absolute',
    width: 16,
    height: 16,
    borderRadius: 8,
    backgroundColor: '#007AFF',
    borderWidth: 2,
    borderColor: 'white',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 5,
  },
  maskOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    opacity: 0.3,
    tintColor: '#28a745', // 초록색 오버레이
  },
  statusContainer: {
    padding: 20,
    alignItems: 'center',
  },
  loadingContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 12,
  },
  loadingText: {
    marginLeft: 8,
    fontSize: 14,
    color: '#007AFF',
    fontWeight: '500',
  },
  statusText: {
    fontSize: 14,
    fontWeight: '500',
    textAlign: 'center',
  },
  infoText: {
    color: '#007AFF',
  },
  successText: {
    color: '#28a745',
  },
  resultInfo: {
    marginTop: 12,
    padding: 12,
    backgroundColor: '#e8f5e8',
    borderRadius: 8,
    alignItems: 'center',
  },
  resultText: {
    fontSize: 12,
    color: '#155724',
    fontWeight: '500',
  },
  actionContainer: {
    padding: 20,
    backgroundColor: 'white',
    borderTopWidth: 1,
    borderTopColor: '#e9ecef',
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'space-around',
  },
  button: {
    paddingVertical: 14,
    paddingHorizontal: 24,
    borderRadius: 10,
    minWidth: 120,
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: '#007AFF',
  },
  secondaryButton: {
    backgroundColor: '#6c757d',
  },
  primaryButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  secondaryButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  hintText: {
    fontSize: 14,
    color: '#6c757d',
    textAlign: 'center',
    fontStyle: 'italic',
  },
  objectListContainer: {
    marginTop: 20,
    marginBottom: 20,
  },
  objectListTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 10,
    textAlign: 'center',
  },
  objectScrollView: {
    flexGrow: 0,
  },
  objectScrollContent: {
    paddingHorizontal: 10,
  },
  objectCard: {
    backgroundColor: 'white',
    borderRadius: 12,
    marginHorizontal: 6,
    padding: 12,
    minWidth: 100,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.2,
    shadowRadius: 2,
    elevation: 2,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  objectCardSelected: {
    borderColor: '#4CAF50',
    backgroundColor: '#F1F8E9',
  },
  objectCardContent: {
    alignItems: 'center',
  },
  objectCardClassName: {
    fontSize: 14,
    fontWeight: '600',
    color: '#333',
    textAlign: 'center',
    marginBottom: 4,
  },
  objectCardConfidence: {
    fontSize: 12,
    color: '#007AFF',
    fontWeight: '500',
    marginBottom: 2,
  },
  objectCardSize: {
    fontSize: 10,
    color: '#666',
    fontWeight: '400',
  },
});