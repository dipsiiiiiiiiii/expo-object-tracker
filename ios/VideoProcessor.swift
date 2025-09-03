import Foundation
import Vision
import AVFoundation
import UIKit
import CoreGraphics
import CoreML
import CoreImage
import TensorFlowLite

// DetectedObject struct definition
struct DetectedObject {
    let className: String
    let confidence: Float
    let boundingBox: CGRect // Normalized coordinates (0-1)
    let identifier: String
    let segmentationMask: UIImage? // Segmentation mask for YOLOv11-seg
    
    var description: String {
        let maskInfo = segmentationMask != nil ? " [mask]" : ""
        return "\(className) (\(String(format: "%.1f%%", confidence * 100)))\(maskInfo)"
    }
}

// YOLOv11Detector class with TensorFlow Lite
class YOLOv11Detector {
    private var interpreter: Interpreter?
    private var modelURL: URL?
    private var customClassNames: [String]?
    private var inputWidth: Int = 640
    private var inputHeight: Int = 640
    private var inputChannels: Int = 3
    
    // COCO dataset class names
    private let classNames = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack",
        "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket",
        "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple",
        "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair",
        "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"
    ]
    
    init() {
        // Don't auto-load model on init, wait for loadModel call
    }
    
    func loadModel(from path: String, type: String, classNames: [String]? = nil) throws {
        print("🔧 Loading TFLite model from path: \(path)")
        print("   Model type: \(type)")
        print("   Class names count: \(classNames?.count ?? 0)")
        
        let actualPath: String
        
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            // HTTP URL인 경우 파일을 다운로드해서 로컬 경로 얻기
            guard let url = URL(string: path) else {
                throw NSError(domain: "YOLOv11Detector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid model URL: \(path)"])
            }
            
            print("📥 Downloading model from HTTP URL...")
            let semaphore = DispatchSemaphore(value: 0)
            var downloadedPath: String?
            var downloadError: Error?
            
            let downloadTask = URLSession.shared.downloadTask(with: url) { (tempURL, response, error) in
                if let error = error {
                    downloadError = error
                    semaphore.signal()
                    return
                }
                
                guard let tempURL = tempURL else {
                    downloadError = NSError(domain: "YOLOv11Detector", code: 2, userInfo: [NSLocalizedDescriptionKey: "No temporary file URL"])
                    semaphore.signal()
                    return
                }
                
                // 임시 파일을 앱의 Documents 디렉토리로 이동
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsPath.appendingPathComponent("yolo_model.tflite")
                
                do {
                    // 기존 파일이 있으면 삭제
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    downloadedPath = destinationURL.path
                    print("✅ Model downloaded to: \(destinationURL.path)")
                } catch {
                    downloadError = error
                }
                
                semaphore.signal()
            }
            
            downloadTask.resume()
            semaphore.wait()
            
            if let error = downloadError {
                throw NSError(domain: "YOLOv11Detector", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to download model: \(error.localizedDescription)"])
            }
            
            guard let path = downloadedPath else {
                throw NSError(domain: "YOLOv11Detector", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get downloaded model path"])
            }
            
            actualPath = path
        } else {
            // 로컬 파일 경로인 경우
            if path.hasPrefix("file://") {
                actualPath = String(path.dropFirst(7)) // "file://" 제거
            } else {
                actualPath = path
            }
        }
        
        print("📁 Using model path: \(actualPath)")
        
        do {
            interpreter = try Interpreter(modelPath: actualPath)
            try interpreter?.allocateTensors()
            
            self.modelURL = URL(fileURLWithPath: actualPath)
            self.customClassNames = classNames
            
            // 입력 텐서 정보 확인
            if let inputTensor = try interpreter?.input(at: 0) {
                print("✅ Input tensor shape: \(inputTensor.shape)")
                if inputTensor.shape.dimensions.count >= 3 {
                    inputHeight = inputTensor.shape.dimensions[1]
                    inputWidth = inputTensor.shape.dimensions[2]
                    inputChannels = inputTensor.shape.dimensions[3]
                }
                print("   Input size: \(inputWidth)x\(inputHeight)x\(inputChannels)")
            }
            
            // 출력 텐서 정보 확인
            let outputCount = interpreter?.outputTensorCount ?? 0
            print("✅ Output tensors count: \(outputCount)")
            for i in 0..<outputCount {
                if let outputTensor = try interpreter?.output(at: i) {
                    print("   Output \(i) shape: \(outputTensor.shape)")
                }
            }
            
            print("✅ TFLite model loaded successfully from: \(actualPath)")
        } catch {
            print("❌ Failed to load TFLite model from \(actualPath): \(error)")
            throw error
        }
    }
    
    func detectObjects(in ciImage: CIImage, completion: @escaping ([DetectedObject]) -> Void) {
        guard let interpreter = interpreter else {
            print("❌ TFLite interpreter not available")
            completion([])
            return
        }
        
        print("🔍 Starting YOLOv11 TFLite detection...")
        print("   Original image size: \(ciImage.extent.width) x \(ciImage.extent.height)")
        
        do {
            // 이미지 전처리: YOLOv11 요구사항에 맞게 리사이즈 및 정규화
            let inputData = try preprocessImageForTFLite(ciImage)
            print("   ✅ Image preprocessed for TFLite")
            
            // 입력 텐서에 데이터 설정
            try interpreter.copy(inputData, toInputAt: 0)
            print("   ✅ Input data copied to tensor")
            
            // 추론 실행
            try interpreter.invoke()
            print("   ✅ TFLite inference completed")
            
            // 출력 텐서에서 결과 가져오기
            let outputTensor = try interpreter.output(at: 0)
            print("   📊 Output tensor shape: \(outputTensor.shape)")
            print("   📊 Output tensor data size: \(outputTensor.data.count) bytes")
            
            // 출력 데이터를 Float 배열로 변환
            let outputData = outputTensor.data.withUnsafeBytes { bytes in
                return Array(bytes.bindMemory(to: Float32.self))
            }
            
            print("   📊 Output data count: \(outputData.count)")
            
            // 출력 데이터 샘플링 확인
            let sampleSize = min(100, outputData.count)
            let nonZeroCount = outputData.prefix(sampleSize).filter { abs($0) > 0.001 }.count
            print("   📊 Non-zero values in first \(sampleSize): \(nonZeroCount)")
            
            if nonZeroCount > 0 {
                let nonZeroValues = outputData.prefix(sampleSize).filter { abs($0) > 0.001 }.prefix(10)
                print("   📊 Sample non-zero values: \(Array(nonZeroValues))")
            }
            
            // YOLO 결과 파싱
            let detections = parseTFLiteYOLOResults(outputData)
            print("   ✅ Final detections count: \(detections.count)")
            
            for (index, detection) in detections.enumerated() {
                print("   Detection \(index): \(detection.description)")
            }
            
            completion(detections)
        } catch {
            print("❌ TFLite inference failed: \(error)")
            completion([])
        }
    }
    
    func detectObjects(in cgImage: CGImage, completion: @escaping ([DetectedObject]) -> Void) {
        let ciImage = CIImage(cgImage: cgImage)
        detectObjects(in: ciImage, completion: completion)
    }
    
    func detectObjectsInVideo(videoUrl: URL, at time: CMTime, completion: @escaping ([DetectedObject]) -> Void) {
        let asset = AVAsset(url: videoUrl)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        
        Task {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                detectObjects(in: cgImage, completion: completion)
            } catch {
                print("❌ Failed to extract frame: \(error)")
                completion([])
            }
        }
    }
    
    private func parseResults(_ results: [VNObservation]?) -> [DetectedObject] {
        guard let results = results else { 
            print("   ⚠️ No results to parse")
            return [] 
        }
        
        print("   📊 Parsing \(results.count) observations:")
        
        var detectedObjects: [DetectedObject] = []
        
        for (index, observation) in results.enumerated() {
            print("   Observation \(index): \(type(of: observation))")
            
            if let recognitionResult = observation as? VNRecognizedObjectObservation {
                print("     ✅ VNRecognizedObjectObservation found")
                let topLabel = recognitionResult.labels.first
                let confidence = topLabel?.confidence ?? 0.0
                let identifier = topLabel?.identifier ?? "unknown"
                
                print("     Labels: \(recognitionResult.labels.map { "\($0.identifier)(\($0.confidence))" })")
                
                // Get class name from identifier or use identifier directly
                let className = getClassName(from: identifier)
                
                // Convert Vision coordinates to UIKit coordinates
                let boundingBox = recognitionResult.boundingBox
                
                let detectedObject = DetectedObject(
                    className: className,
                    confidence: confidence,
                    boundingBox: boundingBox,
                    identifier: identifier,
                    segmentationMask: nil // No segmentation mask from VNRecognizedObjectObservation
                )
                
                print("     Object: \(className), confidence: \(confidence), box: \(boundingBox)")
                
                // Lower threshold for debugging
                if confidence > 0.1 {
                    detectedObjects.append(detectedObject)
                    print("     ✅ Added to results")
                } else {
                    print("     ❌ Filtered out (low confidence)")
                }
            } else if let coreMLResult = observation as? VNCoreMLFeatureValueObservation {
                print("     ⚠️ VNCoreMLFeatureValueObservation found - parsing YOLO output")
                print("     Feature name: \(coreMLResult.featureName)")
                print("     Feature value type: \(type(of: coreMLResult.featureValue))")
                
                // YOLOv11 raw output 파싱 시도
                let detectedFromRaw = self.parseYOLOv11Output(coreMLResult)
                detectedObjects.append(contentsOf: detectedFromRaw)
                print("     📊 Parsed \(detectedFromRaw.count) objects from raw output")
            } else {
                print("     ⚠️ Unknown observation type: \(type(of: observation))")
            }
        }
        
        print("   📈 Raw detections before NMS: \(detectedObjects.count)")
        
        // Sort by confidence (highest first)
        detectedObjects.sort { $0.confidence > $1.confidence }
        
        // Apply Non-Maximum Suppression to remove overlapping detections
        let finalResults = applyNMS(to: detectedObjects, threshold: 0.5)
        print("   📉 Final detections after NMS: \(finalResults.count)")
        
        return finalResults
    }
    
    private func getClassName(from identifier: String) -> String {
        // Use custom class names if available
        if let customNames = customClassNames {
            if let index = Int(identifier), index < customNames.count {
                return customNames[index]
            }
            if customNames.contains(identifier.lowercased()) {
                return identifier.lowercased()
            }
        }
        
        // Fallback to COCO class names
        if let index = Int(identifier), index < classNames.count {
            return classNames[index]
        }
        
        // If identifier is already a string class name, return it
        if classNames.contains(identifier.lowercased()) {
            return identifier.lowercased()
        }
        
        return identifier
    }
    
    private func parseYOLOv11Output(_ observation: VNCoreMLFeatureValueObservation) -> [DetectedObject] {
        let featureValue = observation.featureValue
        
        guard featureValue.type == .multiArray,
              let multiArray = featureValue.multiArrayValue else {
            print("     ❌ Not a multi-array feature")
            return []
        }
        
        print("     🔍 YOLO Raw Output Analysis:")
        print("       Shape: \(multiArray.shape)")
        print("       Count: \(multiArray.count)")
        print("       Feature name: \(observation.featureName)")
        
        // YOLOv11-seg 모델은 여러 출력을 가질 수 있음:
        // 1. Detection output: [1, 116, 8400] (클래스 80개 + 4개 bbox coords + 32개 mask coefficients)
        // 2. Segmentation output: [1, 32, 160, 160] (prototype masks)
        
        // YOLOv11-seg 표준 출력 처리
        if observation.featureName == "var_1366" {
            // Detection output: [1, 116, 8400] - main detection results
            print("       Processing main detection output")
            return parseYOLOv11SegDetections(multiArray)
        } else if observation.featureName == "p" {
            // Prototype masks: [1, 32, 160, 160] - segmentation prototypes
            print("       Found prototype masks, storing for later use")
            // TODO: Store prototype masks for segmentation processing
            return []
        }
        
        // 다른 출력 이름의 경우 기본 처리
        return parseYOLOv11SegDetections(multiArray)
    }
    
    private func parseDetectionOutput(_ multiArray: MLMultiArray) -> [DetectedObject] {
        guard multiArray.shape.count >= 3 else {
            print("     ❌ Unexpected shape format: need 3 dimensions")
            return []
        }
        
        // YOLOv11-seg 출력: [1, 116, 8400] = [batch, features, detections]
        let batchSize = multiArray.shape[0].intValue
        let numFeatures = multiArray.shape[1].intValue  
        let numDetections = multiArray.shape[2].intValue
        
        print("       Batch size: \(batchSize)")
        print("       Features per detection: \(numFeatures)")  
        print("       Number of detections: \(numDetections)")
        
        var detections: [DetectedObject] = []
        let maxCheck = min(100, numDetections) // 처음 100개만 체크
        
        for i in 0..<maxCheck {
            // YOLOv11-seg 메모리 레이아웃: [1, 116, 8400]
            // 각 detection i에 대해: features는 [0...115] 범위, detection index는 i
            
            // 좌표 및 confidence 인덱스 계산
            let xIndex = 0 * numDetections + i      // x: feature 0
            let yIndex = 1 * numDetections + i      // y: feature 1  
            let wIndex = 2 * numDetections + i      // w: feature 2
            let hIndex = 3 * numDetections + i      // h: feature 3
            let confIndex = 4 * numDetections + i   // objectness: feature 4
            
            if confIndex < multiArray.count {
                let objectness = multiArray[[NSNumber(value: confIndex)]].floatValue
                
                if objectness > 0.25 { // lower threshold for debugging
                    print("         🎯 Detection \(i): objectness=\(objectness)")
                    
                    // 바운딩 박스 좌표 (x, y, w, h) 추출
                    let x = multiArray[[NSNumber(value: xIndex)]].floatValue
                    let y = multiArray[[NSNumber(value: yIndex)]].floatValue  
                    let w = multiArray[[NSNumber(value: wIndex)]].floatValue
                    let h = multiArray[[NSNumber(value: hIndex)]].floatValue
                    
                    print("         📦 Box: x=\(x), y=\(y), w=\(w), h=\(h)")
                    
                    // 클래스 찾기 (feature 5~84에서 최대값)
                    var maxClass = 0
                    var maxClassConfidence: Float = 0
                    
                    for classIdx in 0..<80 { // 80개 COCO 클래스
                        let classFeatureIdx = (5 + classIdx) * numDetections + i
                        if classFeatureIdx < multiArray.count {
                            let classConf = multiArray[[NSNumber(value: classFeatureIdx)]].floatValue
                            if classConf > maxClassConfidence {
                                maxClassConfidence = classConf
                                maxClass = classIdx
                            }
                        }
                    }
                    
                    let finalConfidence = objectness * maxClassConfidence
                    print("         🏷️ Class: \(maxClass) (\(classNames[maxClass])), conf=\(maxClassConfidence), final=\(finalConfidence)")
                    
                    if finalConfidence > 0.1 && maxClass < classNames.count {
                        // 정규화된 좌표로 변환 (center format → corner format) 
                        // YOLOv11 출력은 이미 정규화됨 (0-1 범위)
                        let boundingBox = CGRect(
                            x: CGFloat(x - w/2), 
                            y: CGFloat(y - h/2), 
                            width: CGFloat(w), 
                            height: CGFloat(h)
                        )
                        
                        // Mask coefficients 추출 (feature 85-116)
                        var maskCoefficients: [Float] = []
                        for maskIdx in 0..<32 { // 32개 mask coefficients
                            let maskFeatureIdx = (85 + maskIdx) * numDetections + i
                            if maskFeatureIdx < multiArray.count {
                                let coeff = multiArray[[NSNumber(value: maskFeatureIdx)]].floatValue
                                maskCoefficients.append(coeff)
                            }
                        }
                        
                        let detection = DetectedObject(
                            className: classNames[maxClass],
                            confidence: finalConfidence,
                            boundingBox: boundingBox,
                            identifier: String(maxClass),
                            segmentationMask: nil // Will be generated from mask coefficients if available
                        )
                        
                        detections.append(detection)
                        print("       ✅ Raw detection: \(detection.className) (\(finalConfidence)) maskCoeffs: \(maskCoefficients.count)")
                    }
                }
            }
        }
        
        print("       📊 Total detections found: \(detections.count)")
        return detections
    }
    
    // YOLOv11-seg 전용 파싱 함수 (문서 기반)
    private func parseYOLOv11SegDetections(_ multiArray: MLMultiArray) -> [DetectedObject] {
        guard multiArray.shape.count == 3,
              multiArray.shape[0].intValue == 1,
              multiArray.shape[1].intValue == 116,
              multiArray.shape[2].intValue == 8400 else {
            print("     ❌ Invalid YOLOv11-seg shape: expected [1,116,8400], got \(multiArray.shape)")
            return []
        }
        
        print("       🎯 YOLOv11-seg standard parsing")
        let numDetections = 8400
        var detections: [DetectedObject] = []
        
        // YOLOv11-seg 출력 구조: [batch=1, features=116, detections=8400]
        // features 0-3: x,y,w,h (center format, normalized 0-1)
        // feature 4: objectness confidence
        // features 5-84: class probabilities (80 COCO classes) 
        // features 85-116: mask coefficients (32 coefficients)
        
        for i in 0..<min(1000, numDetections) { // 첫 1000개만 체크
            // 메모리 레이아웃: feature * numDetections + detection_index
            let objIdx = 4 * numDetections + i // objectness at feature 4
            
            if objIdx < multiArray.count {
                let objectness = multiArray[[NSNumber(value: objIdx)]].floatValue
                
                if objectness > 0.1 { // 낮은 threshold로 테스트
                    print("         🎯 Detection \(i): objectness=\(objectness)")
                    
                    // 바운딩 박스 좌표 (normalized 0-1)
                    let xIdx = 0 * numDetections + i
                    let yIdx = 1 * numDetections + i
                    let wIdx = 2 * numDetections + i
                    let hIdx = 3 * numDetections + i
                    
                    let cx = multiArray[[NSNumber(value: xIdx)]].floatValue
                    let cy = multiArray[[NSNumber(value: yIdx)]].floatValue
                    let w = multiArray[[NSNumber(value: wIdx)]].floatValue
                    let h = multiArray[[NSNumber(value: hIdx)]].floatValue
                    
                    print("         📦 Box: cx=\(cx), cy=\(cy), w=\(w), h=\(h)")
                    
                    // 클래스 확률 찾기 (features 5-84)
                    var maxClass = 0
                    var maxClassProb: Float = 0
                    
                    for classIdx in 0..<80 {
                        let classFeatureIdx = (5 + classIdx) * numDetections + i
                        if classFeatureIdx < multiArray.count {
                            let classProb = multiArray[[NSNumber(value: classFeatureIdx)]].floatValue
                            if classProb > maxClassProb {
                                maxClassProb = classProb
                                maxClass = classIdx
                            }
                        }
                    }
                    
                    let finalConfidence = objectness * maxClassProb
                    print("         🏷️ Best class: \(maxClass) (\(classNames[maxClass])), prob=\(maxClassProb), final=\(finalConfidence)")
                    
                    if finalConfidence > 0.05 && maxClass < classNames.count {
                        // 중심점 → 코너 좌표 변환 (여전히 정규화됨 0-1)
                        let x1 = cx - w/2
                        let y1 = cy - h/2
                        
                        let boundingBox = CGRect(
                            x: CGFloat(x1),
                            y: CGFloat(y1), 
                            width: CGFloat(w),
                            height: CGFloat(h)
                        )
                        
                        let detection = DetectedObject(
                            className: classNames[maxClass],
                            confidence: finalConfidence,
                            boundingBox: boundingBox,
                            identifier: String(maxClass),
                            segmentationMask: nil
                        )
                        
                        detections.append(detection)
                        print("       ✅ Added detection: \(detection.className) (\(finalConfidence))")
                    }
                }
            }
        }
        
        print("       📊 YOLOv11-seg detections found: \(detections.count)")
        return detections
    }
    
    private func applyNMS(to detections: [DetectedObject], threshold: Float) -> [DetectedObject] {
        guard detections.count > 1 else { return detections }
        
        var result: [DetectedObject] = []
        var indices = Array(0..<detections.count)
        
        while !indices.isEmpty {
            let currentIndex = indices.removeFirst()
            let currentDetection = detections[currentIndex]
            result.append(currentDetection)
            
            indices = indices.filter { index in
                let otherDetection = detections[index]
                let iou = calculateIoU(box1: currentDetection.boundingBox, box2: otherDetection.boundingBox)
                return iou < threshold
            }
        }
        
        return result
    }
    
    private func calculateIoU(box1: CGRect, box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        
        if intersection.isNull {
            return 0.0
        }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = box1.width * box1.height + box2.width * box2.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
    
    // YOLOv11용 이미지 전처리 (640x640, letterboxing)
    private func preprocessImageForYOLO(_ inputImage: CIImage, targetSize: CGFloat) -> CIImage {
        let inputSize = inputImage.extent.size
        
        // Aspect ratio를 유지하며 640x640 안에 맞추기
        let scale = min(targetSize / inputSize.width, targetSize / inputSize.height)
        let scaledSize = CGSize(width: inputSize.width * scale, height: inputSize.height * scale)
        
        print("   Preprocessing: \(inputSize) -> \(scaledSize) (scale: \(scale))")
        
        // CIContext를 사용해서 실제 640x640 이미지 생성
        let context = CIContext()
        
        // 1. 이미지 스케일링
        let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
        scaleFilter.setValue(inputImage, forKey: kCIInputImageKey)
        scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
        scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        
        guard let scaledImage = scaleFilter.outputImage else {
            print("   ❌ Failed to scale image")
            return inputImage
        }
        
        // 2. 640x640 검은색 배경 생성
        let blackBackground = CIImage(color: CIColor.black).cropped(to: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        
        // 3. Letterboxing - 중앙에 배치
        let offsetX = (targetSize - scaledSize.width) / 2
        let offsetY = (targetSize - scaledSize.height) / 2
        
        let translationTransform = CGAffineTransform(translationX: offsetX, y: offsetY)
        let centeredImage = scaledImage.transformed(by: translationTransform)
        
        // 4. 배경과 합성
        let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
        compositeFilter.setValue(centeredImage, forKey: kCIInputImageKey)
        compositeFilter.setValue(blackBackground, forKey: kCIInputBackgroundImageKey)
        
        guard let finalImage = compositeFilter.outputImage else {
            print("   ❌ Failed to composite image")
            return inputImage
        }
        
        let result = finalImage.cropped(to: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        print("   Final preprocessed size: \(result.extent)")
        
        return result
    }
    
    // TensorFlow Lite용 이미지 전처리
    private func preprocessImageForTFLite(_ inputImage: CIImage) throws -> Data {
        let targetSize: CGFloat = CGFloat(max(inputWidth, inputHeight))
        
        // 기존 YOLO 전처리를 재사용하여 640x640 이미지 생성
        let preprocessedImage = preprocessImageForYOLO(inputImage, targetSize: targetSize)
        
        // CIImage를 CGImage로 변환
        let context = CIContext()
        guard let cgImage = context.createCGImage(preprocessedImage, from: preprocessedImage.extent) else {
            throw NSError(domain: "TFLitePreprocessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert CIImage to CGImage"])
        }
        
        // CGImage를 pixel buffer로 변환하고 정규화
        let width = cgImage.width
        let height = cgImage.height
        let channels = inputChannels
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw NSError(domain: "TFLitePreprocessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create color space"])
        }
        
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw NSError(domain: "TFLitePreprocessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext"])
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // RGB 데이터 추출 및 정규화 (0-1 범위)
        var floatArray = [Float32]()
        floatArray.reserveCapacity(width * height * channels)
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelOffset = (y * width + x) * bytesPerPixel
                let r = Float32(pixelData[pixelOffset]) / 255.0
                let g = Float32(pixelData[pixelOffset + 1]) / 255.0
                let b = Float32(pixelData[pixelOffset + 2]) / 255.0
                
                floatArray.append(r)
                floatArray.append(g)
                floatArray.append(b)
            }
        }
        
        print("   TFLite input shape: [\(1), \(height), \(width), \(channels)]")
        print("   TFLite input data size: \(floatArray.count) floats")
        
        // Float32 배열을 Data로 변환
        return Data(bytes: floatArray, count: floatArray.count * MemoryLayout<Float32>.size)
    }
    
    // TFLite YOLO 결과 파싱
    private func parseTFLiteYOLOResults(_ outputData: [Float32]) -> [DetectedObject] {
        print("   🔍 Parsing TFLite YOLO results...")
        
        // YOLOv11-seg 출력 형태 분석
        // 일반적으로 [1, 116, 8400] 형태로 출력됨
        // 116 = 4 (bbox) + 1 (objectness) + 80 (classes) + 31 (mask coefficients)
        // 8400 = 80*80 + 40*40 + 20*20 (다양한 스케일의 앵커 포인트)
        
        let numDetections = 8400
        let numFeatures = 116
        
        guard outputData.count >= numDetections * numFeatures else {
            print("   ❌ Insufficient output data: expected \(numDetections * numFeatures), got \(outputData.count)")
            return []
        }
        
        var detections: [DetectedObject] = []
        let confidenceThreshold: Float = 0.1 // Lower threshold for debugging
        
        for i in 0..<numDetections {
            // YOLOv11 출력 레이아웃: [batch_size, features, detections]
            // 메모리에서는 연속적으로: [all features for detection 0, all features for detection 1, ...]
            
            let baseIdx = i * numFeatures
            
            // 바운딩 박스 좌표 (cx, cy, w, h) - 정규화됨
            let cx = outputData[baseIdx + 0]
            let cy = outputData[baseIdx + 1]
            let w = outputData[baseIdx + 2]
            let h = outputData[baseIdx + 3]
            
            // Objectness confidence
            let objectness = outputData[baseIdx + 4]
            
            if objectness > confidenceThreshold {
                // 클래스별 confidence 확인 (indices 5-84)
                var maxClassConfidence: Float = 0
                var maxClassIndex = 0
                
                for classIdx in 0..<80 { // 80개 COCO 클래스
                    let classConf = outputData[baseIdx + 5 + classIdx]
                    if classConf > maxClassConfidence {
                        maxClassConfidence = classConf
                        maxClassIndex = classIdx
                    }
                }
                
                let finalConfidence = objectness * maxClassConfidence
                
                if finalConfidence > confidenceThreshold && maxClassIndex < classNames.count {
                    // Center format을 corner format으로 변환
                    let x = cx - w / 2
                    let y = cy - h / 2
                    
                    let boundingBox = CGRect(
                        x: CGFloat(x),
                        y: CGFloat(y),
                        width: CGFloat(w),
                        height: CGFloat(h)
                    )
                    
                    let className = customClassNames?[maxClassIndex] ?? classNames[maxClassIndex]
                    
                    let detection = DetectedObject(
                        className: className,
                        confidence: finalConfidence,
                        boundingBox: boundingBox,
                        identifier: String(maxClassIndex),
                        segmentationMask: nil // TODO: Implement segmentation mask extraction
                    )
                    
                    detections.append(detection)
                    
                    if detections.count <= 10 { // 처음 10개만 로그 출력
                        print("   🎯 Detection \(detections.count): \(className) (conf: \(finalConfidence), box: \(boundingBox))")
                    }
                }
            }
        }
        
        print("   📊 Raw detections found: \(detections.count)")
        
        // NMS 적용
        let finalResults = applyNMS(to: detections, threshold: 0.5)
        print("   📉 Final detections after NMS: \(finalResults.count)")
        
        return finalResults
    }
    
    // 직접 CoreML로 추론 수행
    private func testDirectCoreMLInference(ciImage: CIImage, modelURL: URL, completion: @escaping ([DetectedObject]) -> Void) {
        do {
            print("🧪 Direct CoreML inference...")
            let mlModel = try MLModel(contentsOf: modelURL)
            
            // CVPixelBuffer로 변환 (640x640)
            let context = CIContext()
            let pixelBuffer = try createPixelBuffer(from: ciImage, context: context)
            
            // 입력 데이터 검증
            validatePixelBuffer(pixelBuffer)
            
            // MLFeatureProvider 생성
            let inputFeature = try MLFeatureValue(pixelBuffer: pixelBuffer)
            let input = try MLDictionaryFeatureProvider(dictionary: ["image": inputFeature])
            
            print("   Performing direct CoreML prediction...")
            let prediction = try mlModel.prediction(from: input)
            
            print("   Direct CoreML prediction completed!")
            print("   Output feature names: \(prediction.featureNames)")
            
            // 먼저 raw 출력값들을 직접 확인
            var detections: [DetectedObject] = []
            
            if let detectionOutput = prediction.featureValue(for: "var_1366")?.multiArrayValue {
                print("   📊 Raw detection output validation:")
                print("     Shape: \(detectionOutput.shape)")
                print("     Count: \(detectionOutput.count)")
                
                // 실제 데이터 샘플링
                var nonZeroCount = 0
                var sampleValues: [Float] = []
                let sampleSize = min(1000, detectionOutput.count)
                
                for i in 0..<sampleSize {
                    let value = detectionOutput[[NSNumber(value: i)]].floatValue
                    sampleValues.append(value)
                    if abs(value) > 0.001 {
                        nonZeroCount += 1
                    }
                }
                
                print("     Non-zero values in first \(sampleSize): \(nonZeroCount)")
                print("     Sample values: \(sampleValues.prefix(20))")
                
                // 특정 위치들도 체크 (objectness positions)
                let numDetections = 8400
                print("     Checking objectness positions:")
                for det in [0, 1, 10, 100, 1000] {
                    let objIdx = 4 * numDetections + det
                    if objIdx < detectionOutput.count {
                        let objectness = detectionOutput[[NSNumber(value: objIdx)]].floatValue
                        print("       Detection \(det) objectness: \(objectness)")
                    }
                }
                
                // 파싱 실행
                detections = parseYOLOv11SegDetections(detectionOutput)
            }
            
            // 프로토타입 마스크도 확인
            if let protoOutput = prediction.featureValue(for: "p")?.multiArrayValue {
                print("   📊 Prototype masks validation:")
                print("     Shape: \(protoOutput.shape)")
                
                var protoNonZero = 0
                for i in 0..<min(1000, protoOutput.count) {
                    let value = protoOutput[[NSNumber(value: i)]].floatValue
                    if abs(value) > 0.001 { protoNonZero += 1 }
                }
                print("     Non-zero values in first 1000: \(protoNonZero)")
            }
            
            print("   Direct CoreML found \(detections.count) detections")
            completion(detections)
            
        } catch {
            print("❌ Direct CoreML inference failed: \(error)")
            completion([])
        }
    }
    
    // CVPixelBuffer 생성 - YOLOv11에 맞게 최적화
    private func createPixelBuffer(from ciImage: CIImage, context: CIContext) throws -> CVPixelBuffer {
        let width = 640
        let height = 640
        
        // YOLOv11은 RGB를 요구하므로 32ARGB 사용
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32ARGB, attributes as CFDictionary, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "PixelBuffer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }
        
        // RGB 색상 공간으로 변환
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let colorspaceCorrectedImage = ciImage.matchedToWorkingSpace(from: rgbColorSpace) ?? ciImage
        
        // CIImage를 CVPixelBuffer로 렌더링
        context.render(colorspaceCorrectedImage, to: buffer)
        
        return buffer
    }
    
    // 입력 데이터 검증
    private func validatePixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        print("   📊 Input validation:")
        print("     Size: \(width)x\(height)")
        print("     Format: \(pixelFormat) (expected: \(kCVPixelFormatType_32ARGB))")
        
        // 픽셀 데이터 샘플링
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let buffer = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
            
            // 첫 몇 픽셀 값 확인
            var samplePixels: [UInt8] = []
            var nonZeroCount = 0
            
            for i in 0..<min(100, bytesPerRow * height) {
                let value = buffer[i]
                samplePixels.append(value)
                if value > 0 { nonZeroCount += 1 }
            }
            
            print("     Non-zero bytes in first 100: \(nonZeroCount)")
            print("     Sample values: \(samplePixels.prefix(10))")
            
            // 중앙 부근 픽셀도 확인 (실제 이미지 데이터가 있어야 함)
            let centerY = height / 2
            let centerX = width / 2
            let centerOffset = centerY * bytesPerRow + centerX * 4 // 4 bytes per pixel (BGRA)
            
            if centerOffset + 3 < bytesPerRow * height {
                let a = buffer[centerOffset]
                let r = buffer[centerOffset + 1] 
                let g = buffer[centerOffset + 2]
                let b = buffer[centerOffset + 3]
                print("     Center pixel ARGB: (\(a), \(r), \(g), \(b))")
            }
        }
    }
}

class VideoProcessor {
    private var trackedObjects: [String: VNTrackingRequest] = [:]
    private var selectedObservations: [String: VNDetectedObjectObservation] = [:]
    private let yoloDetector = YOLOv11Detector()
    
    // MARK: - Model Loading
    
    func loadModel(modelPath: String, modelType: String, classNames: [String]?) async throws {
        try yoloDetector.loadModel(from: modelPath, type: modelType, classNames: classNames)
    }
    
    func selectObject(videoUri: String, frameIndex: Int, boundingBox: [String: Double]) async throws -> String {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let duration = try await asset.load(.duration)
        let frameTime = CMTime(seconds: Double(frameIndex) / 30.0, preferredTimescale: duration.timescale)
        
        let cgImage = try imageGenerator.copyCGImage(at: frameTime, actualTime: nil)
        
        guard let x = boundingBox["x"],
              let y = boundingBox["y"],
              let width = boundingBox["width"],
              let height = boundingBox["height"] else {
            throw NSError(domain: "VideoProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid bounding box"])
        }
        
        // 디버깅 로그 추가
        print("🔍 SelectObject Debug:")
        print("   Input coordinates: x=\(x), y=\(y), width=\(width), height=\(height)")
        print("   Image size: \(cgImage.width)x\(cgImage.height)")
        
        // UIKit 좌표계 (왼쪽 상단 0,0)를 Vision Framework 좌표계 (왼쪽 하단 0,0)로 변환
        // Vision Framework에서 실제로 기대하는 좌표계를 맞춰줘야 함
        let normalizedBoundingBox = CGRect(
            x: x / Double(cgImage.width),
            y: y / Double(cgImage.height),  // UIKit 좌표 그대로 사용해보기
            width: width / Double(cgImage.width),
            height: height / Double(cgImage.height)
        )
        
        print("   Normalized bounding box: \(normalizedBoundingBox)")
        
        let observation = VNDetectedObjectObservation(boundingBox: normalizedBoundingBox)
        let objectId = UUID().uuidString
        
        selectedObservations[objectId] = observation
        
        return objectId
    }
    
    func generateObjectPreview(videoUri: String, objectId: String) async throws -> String {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        guard let observation = selectedObservations[objectId] else {
            throw NSError(domain: "VideoProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Object not found"])
        }
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        
        // 비디오 트랙의 변환 정보 확인
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let transform = try await videoTrack.load(.preferredTransform)
        print("🎬 Video transform: \(transform)")
        print("🎬 Natural size: \(try await videoTrack.load(.naturalSize))")
        
        let frameTime = CMTime(seconds: 0, preferredTimescale: 600)
        let cgImage = try imageGenerator.copyCGImage(at: frameTime, actualTime: nil)
        
        print("🖼️ Generated CGImage size: \(cgImage.width)x\(cgImage.height)")
        
        let ciImage = CIImage(cgImage: cgImage)
        let boundingBox = observation.boundingBox
        
        // 디버깅 로그
        print("🎯 Debug Info:")
        print("   Original bounding box (normalized): \(boundingBox)")
        print("   Image size: \(ciImage.extent)")
        
        // 원본 이미지 크기로 바운딩 박스 변환
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        
        let context = CIContext()
        
        // CIImage를 CGImage로 변환
        guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw NSError(domain: "VideoProcessor", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }
        
        // Vision Framework 정규화 좌표를 UIKit 픽셀 좌표로 변환
        // 실제 테스트 결과 Vision Framework가 UIKit과 같은 좌표계를 사용하는 것으로 보임
        var uiKitBoundingBox = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: boundingBox.origin.y * imageHeight,  // 좌표 변환 없이 직접 사용
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )
        
        // 비디오 변환이 적용된 경우 바운딩 박스도 함께 변환
        if !transform.isIdentity {
            print("🔄 Applying transform to bounding box: \(transform)")
            // 변환 적용 - 주로 회전이나 뒤집기
            uiKitBoundingBox = uiKitBoundingBox.applying(transform)
            
            // 변환 후 음수 좌표를 보정
            if uiKitBoundingBox.origin.x < 0 || uiKitBoundingBox.origin.y < 0 {
                let offsetX = max(0, -uiKitBoundingBox.origin.x)
                let offsetY = max(0, -uiKitBoundingBox.origin.y)
                uiKitBoundingBox = uiKitBoundingBox.offsetBy(dx: offsetX, dy: offsetY)
            }
        }
        
        print("   Vision normalized box: \(boundingBox)")
        print("   UIKit pixel box (final): \(uiKitBoundingBox)")
        print("   Transform applied: \(!transform.isIdentity)")
        
        print("   UIKit bounding box: \(uiKitBoundingBox)")
        
        let renderer = UIGraphicsImageRenderer(size: ciImage.extent.size)
        let resultUIImage = renderer.image { context in
            // 원본 이미지를 UIKit 좌표계에 맞게 그리기
            let drawRect = CGRect(origin: .zero, size: ciImage.extent.size)
            
            // UIImage로 변환해서 그리면 좌표계가 자동으로 맞춰짐
            let uiImage = UIImage(cgImage: outputCGImage)
            uiImage.draw(in: drawRect)
            
            // 바운딩 박스 그리기 (UIKit 좌표계에서)
            context.cgContext.setStrokeColor(UIColor.systemGreen.cgColor)
            context.cgContext.setLineWidth(4.0)
            context.cgContext.setLineDash(phase: 0, lengths: [10, 6])
            context.cgContext.stroke(uiKitBoundingBox)
            
            // 반투명 채우기
            context.cgContext.setFillColor(UIColor.systemGreen.withAlphaComponent(0.2).cgColor)
            context.cgContext.fill(uiKitBoundingBox)
            
            // 라벨
            let labelText = "✓ Detected Object"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.white
            ]
            
            let labelSize = labelText.size(withAttributes: attributes)
            let labelY = max(uiKitBoundingBox.origin.y - labelSize.height - 8, 8)
            let labelRect = CGRect(
                x: uiKitBoundingBox.origin.x,
                y: labelY,
                width: labelSize.width + 12,
                height: labelSize.height + 6
            )
            
            context.cgContext.setFillColor(UIColor.systemGreen.cgColor)
            context.cgContext.fill(labelRect)
            
            labelText.draw(at: CGPoint(x: labelRect.origin.x + 6, y: labelRect.origin.y + 3), withAttributes: attributes)
        }
        
        let resultImage = CIImage(image: resultUIImage) ?? ciImage
        
        // 임시 파일로 저장
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("object_preview_\(UUID().uuidString).jpg")
        
        try context.writeJPEGRepresentation(of: resultImage, to: outputURL, colorSpace: resultImage.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        
        return outputURL.absoluteString
    }
    
    func getVideoResolution(videoUri: String) async throws -> [String: Int] {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        
        // 변환이 적용된 실제 표시 크기 계산
        let size = naturalSize.applying(transform)
        let width = abs(Int(size.width))
        let height = abs(Int(size.height))
        
        return ["width": width, "height": height]
    }
    
    func trackObject(videoUri: String, objectId: String) async throws -> [[String: Any]] {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        guard let initialObservation = selectedObservations[objectId] else {
            throw NSError(domain: "VideoProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Object not found"])
        }
        
        let asset = AVAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        
        reader.add(output)
        reader.startReading()
        
        var trackingResults: [[String: Any]] = []
        var frameIndex = 0
        
        var trackingRequest = VNTrackObjectRequest(detectedObjectObservation: initialObservation)
        trackingRequest.trackingLevel = .accurate
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            
            do {
                try requestHandler.perform([trackingRequest])
                
                if let observation = trackingRequest.results?.first as? VNDetectedObjectObservation {
                    let boundingBox = observation.boundingBox
                    
                    let trackingData: [String: Any] = [
                        "frameIndex": frameIndex,
                        "boundingBox": [
                            "x": boundingBox.origin.x,
                            "y": 1.0 - boundingBox.origin.y - boundingBox.height,
                            "width": boundingBox.width,
                            "height": boundingBox.height
                        ],
                        "confidence": observation.confidence
                    ]
                    
                    trackingResults.append(trackingData)
                    
                    let nextRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    nextRequest.trackingLevel = .accurate
                    trackingRequest = nextRequest
                }
            } catch {
                print("Tracking failed for frame \(frameIndex): \(error)")
                break
            }
            
            frameIndex += 1
        }
        
        reader.cancelReading()
        return trackingResults
    }
    
    func applyEffectToTrackedObject(videoUri: String, trackingData: [[String: Any]], effectConfig: [String: Any]) async throws -> String {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let composition = AVMutableComposition()
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "VideoProcessor", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition video track"])
        }
        
        let timeRange = try await videoTrack.load(.timeRange)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: CMTime.zero)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = try await videoTrack.load(.naturalSize)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]
        
        videoComposition.instructions = [instruction]
        
        // 효과 팩토리에서 효과 생성
        guard let effect = EffectFactory.createEffect(from: effectConfig) else {
            throw NSError(domain: "VideoProcessor", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid effect configuration"])
        }
        
        // TODO: Core Image를 사용한 실제 효과 적용 로직 구현
        // 현재는 기본 비디오만 출력
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("processed_video_\(UUID().uuidString).mp4")
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "VideoProcessor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw NSError(domain: "VideoProcessor", code: 6, userInfo: [NSLocalizedDescriptionKey: "Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")"])
        }
        
        return outputURL.absoluteString
    }
    
    func generatePreviewFrames(videoUri: String, trackingData: [[String: Any]], frameCount: Int) async throws -> [[String: Any]] {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let duration = try await asset.load(.duration)
        let totalFrames = trackingData.count
        let step = max(1, totalFrames / frameCount)
        
        var previewFrames: [[String: Any]] = []
        
        for i in stride(from: 0, to: totalFrames, by: step) {
            if previewFrames.count >= frameCount { break }
            
            guard let trackingInfo = trackingData.first(where: { data in
                if let frameIndex = data["frameIndex"] as? Int {
                    return frameIndex == i
                }
                return false
            }) else { continue }
            
            let time = CMTime(seconds: Double(i) / 30.0, preferredTimescale: duration.timescale)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                
                // 이미지를 임시 파일로 저장
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("preview_frame_\(i)_\(UUID().uuidString).jpg")
                
                let ciImage = CIImage(cgImage: cgImage)
                let context = CIContext()
                try context.writeJPEGRepresentation(of: ciImage, to: tempURL, colorSpace: ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB())
                
                let previewFrame: [String: Any] = [
                    "frameIndex": i,
                    "imageUri": tempURL.absoluteString,
                    "boundingBox": trackingInfo["boundingBox"] ?? [:]
                ]
                
                previewFrames.append(previewFrame)
            } catch {
                print("Failed to generate preview frame at index \(i): \(error)")
                continue
            }
        }
        
        return previewFrames
    }
    
    func applyEffectToFrame(frameUri: String, boundingBox: [String: Any], effectConfig: [String: Any]) async throws -> String {
        guard let url = URL(string: frameUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid frame URI"])
        }
        
        guard let effect = EffectFactory.createEffect(from: effectConfig) else {
            throw NSError(domain: "VideoProcessor", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid effect configuration"])
        }
        
        guard let x = boundingBox["x"] as? Double,
              let y = boundingBox["y"] as? Double,
              let width = boundingBox["width"] as? Double,
              let height = boundingBox["height"] as? Double else {
            throw NSError(domain: "VideoProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid bounding box"])
        }
        
        let ciImage = CIImage(contentsOf: url)!
        let boundingRect = CGRect(x: x * ciImage.extent.width, y: y * ciImage.extent.height, 
                                width: width * ciImage.extent.width, height: height * ciImage.extent.height)
        
        let processedImage = effect.apply(to: ciImage, boundingBox: boundingRect)
        
        // 처리된 이미지를 임시 파일로 저장
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("processed_frame_\(UUID().uuidString).jpg")
        
        let context = CIContext()
        try context.writeJPEGRepresentation(of: processedImage, to: outputURL, colorSpace: processedImage.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        
        return outputURL.absoluteString
    }
    
    // MARK: - YOLOv11 Detection Methods
    
    func detectObjects(videoUri: String, frameIndex: Int) async throws -> [[String: Any]] {
        print("🎬 Starting object detection for video:")
        print("   URI: \(videoUri)")
        print("   Frame index: \(frameIndex)")
        
        guard let url = URL(string: videoUri) else {
            print("❌ Invalid video URI: \(videoUri)")
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime.zero
        imageGenerator.requestedTimeToleranceAfter = CMTime.zero
        
        let duration = try await asset.load(.duration)
        let frameTime = CMTime(seconds: Double(frameIndex) / 30.0, preferredTimescale: duration.timescale)
        
        print("   Duration: \(duration.seconds) seconds")
        print("   Frame time: \(frameTime.seconds) seconds")
        
        let cgImage = try imageGenerator.copyCGImage(at: frameTime, actualTime: nil)
        let ciImage = CIImage(cgImage: cgImage)
        
        print("   Frame extracted: \(cgImage.width)x\(cgImage.height)")
        print("   Starting YOLOv11 detection...")
        
        return await withCheckedContinuation { continuation in
            yoloDetector.detectObjects(in: ciImage) { (detections: [DetectedObject]) in
                let results = detections.map { detection -> [String: Any] in
                    var result: [String: Any] = [
                        "className": detection.className,
                        "confidence": detection.confidence,
                        "boundingBox": [
                            "x": detection.boundingBox.origin.x,
                            "y": detection.boundingBox.origin.y,
                            "width": detection.boundingBox.width,
                            "height": detection.boundingBox.height
                        ],
                        "identifier": detection.identifier
                    ]
                    
                    // Add segmentation mask if available
                    if let segmentationMask = detection.segmentationMask {
                        if let maskData = segmentationMask.jpegData(compressionQuality: 0.8) {
                            let base64Mask = maskData.base64EncodedString()
                            result["segmentationMask"] = "data:image/jpeg;base64,\(base64Mask)"
                        }
                    }
                    
                    return result
                }
                continuation.resume(returning: results)
            }
        }
    }
    
    func detectObjectsInVideo(videoUri: String, maxFrames: Int = 30) async throws -> [[String: Any]] {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let totalSeconds = CMTimeGetSeconds(duration)
        let frameInterval = max(1.0, totalSeconds / Double(maxFrames))
        
        var allDetections: [[String: Any]] = []
        
        for i in 0..<maxFrames {
            let time = CMTime(seconds: Double(i) * frameInterval, preferredTimescale: duration.timescale)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let ciImage = CIImage(cgImage: cgImage)
                
                let detections = await withCheckedContinuation { continuation in
                    yoloDetector.detectObjects(in: ciImage) { (detections: [DetectedObject]) in
                        let results = detections.map { detection -> [String: Any] in
                            var result: [String: Any] = [
                                "frameIndex": i,
                                "time": CMTimeGetSeconds(time),
                                "className": detection.className,
                                "confidence": detection.confidence,
                                "boundingBox": [
                                    "x": detection.boundingBox.origin.x,
                                    "y": detection.boundingBox.origin.y,
                                    "width": detection.boundingBox.width,
                                    "height": detection.boundingBox.height
                                ],
                                "identifier": detection.identifier
                            ]
                            
                            // Add segmentation mask if available
                            if let segmentationMask = detection.segmentationMask {
                                if let maskData = segmentationMask.jpegData(compressionQuality: 0.8) {
                                    let base64Mask = maskData.base64EncodedString()
                                    result["segmentationMask"] = "data:image/jpeg;base64,\(base64Mask)"
                                }
                            }
                            
                            return result
                        }
                        continuation.resume(returning: results)
                    }
                }
                
                allDetections.append(contentsOf: detections)
            } catch {
                print("Failed to process frame \(i): \(error)")
                continue
            }
        }
        
        return allDetections
    }
    
    func createDetectionPreview(videoUri: String, frameIndex: Int, detections: [[String: Any]]) async throws -> String {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let duration = try await asset.load(.duration)
        let frameTime = CMTime(seconds: Double(frameIndex) / 30.0, preferredTimescale: duration.timescale)
        
        let cgImage = try imageGenerator.copyCGImage(at: frameTime, actualTime: nil)
        let ciImage = CIImage(cgImage: cgImage)
        
        // Create drawing context
        let renderer = UIGraphicsImageRenderer(size: ciImage.extent.size)
        let resultUIImage = renderer.image { context in
            // Draw original image
            let uiImage = UIImage(cgImage: cgImage)
            uiImage.draw(in: CGRect(origin: .zero, size: ciImage.extent.size))
            
            // Draw bounding boxes for detections
            for detection in detections {
                guard let boundingBox = detection["boundingBox"] as? [String: Double],
                      let className = detection["className"] as? String,
                      let confidence = detection["confidence"] as? Float else {
                    continue
                }
                
                let x = boundingBox["x"] ?? 0
                let y = boundingBox["y"] ?? 0
                let width = boundingBox["width"] ?? 0
                let height = boundingBox["height"] ?? 0
                
                // Convert normalized coordinates to pixel coordinates
                let pixelRect = CGRect(
                    x: x * ciImage.extent.width,
                    y: y * ciImage.extent.height,
                    width: width * ciImage.extent.width,
                    height: height * ciImage.extent.height
                )
                
                // Draw bounding box
                context.cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                context.cgContext.setLineWidth(3.0)
                context.cgContext.stroke(pixelRect)
                
                // Draw semi-transparent fill
                context.cgContext.setFillColor(UIColor.systemBlue.withAlphaComponent(0.2).cgColor)
                context.cgContext.fill(pixelRect)
                
                // Draw label
                let labelText = "\(className) (\(String(format: "%.1f%%", confidence * 100)))"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.white
                ]
                
                let labelSize = labelText.size(withAttributes: attributes)
                let labelY = max(pixelRect.origin.y - labelSize.height - 4, 4)
                let labelRect = CGRect(
                    x: pixelRect.origin.x,
                    y: labelY,
                    width: labelSize.width + 8,
                    height: labelSize.height + 4
                )
                
                context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
                context.cgContext.fill(labelRect)
                
                labelText.draw(at: CGPoint(x: labelRect.origin.x + 4, y: labelRect.origin.y + 2), withAttributes: attributes)
            }
        }
        
        let resultCIImage = CIImage(image: resultUIImage) ?? ciImage
        
        // Save to temporary file
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("detection_preview_\(UUID().uuidString).jpg")
        
        let context = CIContext()
        try context.writeJPEGRepresentation(of: resultCIImage, to: outputURL, colorSpace: resultCIImage.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        
        return outputURL.absoluteString
    }
    
    // MARK: - Combined Detection + Tracking Methods
    
    func detectAndTrackObjects(videoUri: String, targetClassName: String?, minConfidence: Float = 0.5, detectionInterval: Int = 1) async throws -> [[String: Any]] {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        
        reader.add(output)
        reader.startReading()
        
        var combinedResults: [[String: Any]] = []
        var frameIndex = 0
        var activeTrackers: [String: VNTrackingRequest] = [:]
        var trackerObjects: [String: DetectedObject] = [:]
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Run YOLOv11 detection based on detection interval (1 = every frame, 30 = every 30 frames)
            if frameIndex % detectionInterval == 0 {
                let detections: [DetectedObject] = await withCheckedContinuation { continuation in
                    yoloDetector.detectObjects(in: ciImage) { (detections: [DetectedObject]) in
                        continuation.resume(returning: detections)
                    }
                }
                
                // Filter detections by target class and confidence
                let filteredDetections = detections.filter { detection in
                    let classMatch = targetClassName == nil || detection.className == targetClassName
                    let confidenceMatch = detection.confidence >= minConfidence
                    return classMatch && confidenceMatch
                }
                
                // Create new trackers for high-confidence detections
                for detection in filteredDetections {
                    let objectId = UUID().uuidString
                    let observation = VNDetectedObjectObservation(boundingBox: detection.boundingBox)
                    let trackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    trackingRequest.trackingLevel = .accurate
                    
                    activeTrackers[objectId] = trackingRequest
                    trackerObjects[objectId] = detection
                    
                    // Add initial detection result
                    let result: [String: Any] = [
                        "objectId": objectId,
                        "frameIndex": frameIndex,
                        "className": detection.className,
                        "confidence": detection.confidence,
                        "source": "detection",
                        "boundingBox": [
                            "x": detection.boundingBox.origin.x,
                            "y": detection.boundingBox.origin.y,
                            "width": detection.boundingBox.width,
                            "height": detection.boundingBox.height
                        ]
                    ]
                    combinedResults.append(result)
                }
            }
            
            // Run tracking on all active trackers
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            var trackersToRemove: [String] = []
            
            for (objectId, trackingRequest) in activeTrackers {
                do {
                    try requestHandler.perform([trackingRequest])
                    
                    if let observation = trackingRequest.results?.first as? VNDetectedObjectObservation {
                        // If confidence is too low, remove tracker
                        if observation.confidence < 0.3 {
                            trackersToRemove.append(objectId)
                            continue
                        }
                        
                        let boundingBox = observation.boundingBox
                        let originalObject = trackerObjects[objectId]
                        
                        let result: [String: Any] = [
                            "objectId": objectId,
                            "frameIndex": frameIndex,
                            "className": originalObject?.className ?? "unknown",
                            "confidence": observation.confidence,
                            "source": "tracking",
                            "boundingBox": [
                                "x": boundingBox.origin.x,
                                "y": 1.0 - boundingBox.origin.y - boundingBox.height, // Convert coordinates
                                "width": boundingBox.width,
                                "height": boundingBox.height
                            ]
                        ]
                        combinedResults.append(result)
                        
                        // Update tracker with new observation
                        let nextRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                        nextRequest.trackingLevel = .accurate
                        activeTrackers[objectId] = nextRequest
                    } else {
                        trackersToRemove.append(objectId)
                    }
                } catch {
                    print("Tracking failed for object \(objectId) at frame \(frameIndex): \(error)")
                    trackersToRemove.append(objectId)
                }
            }
            
            // Remove failed trackers
            for objectId in trackersToRemove {
                activeTrackers.removeValue(forKey: objectId)
                trackerObjects.removeValue(forKey: objectId)
            }
            
            frameIndex += 1
        }
        
        reader.cancelReading()
        return combinedResults
    }
    
    func createTrackingVisualization(videoUri: String, trackingResults: [[String: Any]], outputPath: String?) async throws -> String {
        guard let url = URL(string: videoUri) else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid video URI"])
        }
        
        let asset = AVAsset(url: url)
        let composition = AVMutableComposition()
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "VideoProcessor", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition video track"])
        }
        
        let timeRange = try await videoTrack.load(.timeRange)
        try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: CMTime.zero)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let naturalSize = try await videoTrack.load(.naturalSize)
        videoComposition.renderSize = naturalSize
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]
        
        // Create overlay layer for bounding boxes
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: naturalSize)
        
        // Group tracking results by frame
        let resultsByFrame = Dictionary(grouping: trackingResults) { result in
            result["frameIndex"] as? Int ?? 0
        }
        
        // Create animation layers for each tracked object
        var objectColors: [String: CGColor] = [:]
        let availableColors: [CGColor] = [
            UIColor.systemBlue.cgColor,
            UIColor.systemRed.cgColor,
            UIColor.systemGreen.cgColor,
            UIColor.systemOrange.cgColor,
            UIColor.systemPurple.cgColor,
            UIColor.systemPink.cgColor
        ]
        
        for (frameIndex, results) in resultsByFrame {
            for result in results {
                guard let objectId = result["objectId"] as? String,
                      let boundingBox = result["boundingBox"] as? [String: Double],
                      let className = result["className"] as? String else {
                    continue
                }
                
                if objectColors[objectId] == nil {
                    objectColors[objectId] = availableColors[objectColors.count % availableColors.count]
                }
                
                // This is a simplified visualization - in a full implementation,
                // you'd create Core Animation layers that animate over time
            }
        }
        
        videoComposition.instructions = [instruction]
        
        // Export the video with visualization
        let outputURL: URL
        if let outputPath = outputPath {
            outputURL = URL(fileURLWithPath: outputPath)
        } else {
            outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("tracked_video_\(UUID().uuidString).mp4")
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "VideoProcessor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw NSError(domain: "VideoProcessor", code: 6, userInfo: [NSLocalizedDescriptionKey: "Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")"])
        }
        
        return outputURL.absoluteString
    }
}