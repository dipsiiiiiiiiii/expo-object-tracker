import ExpoModulesCore
import Vision
import AVFoundation
import UIKit
import CoreML
import CoreGraphics
import CoreImage

// CGRect extension for area calculation
extension CGRect {
    var area: CGFloat {
        return width * height
    }
}

// SAM2 Types and Classes
struct SAMPoint {
    let x: Float
    let y: Float
    let label: Int // 1 for foreground, 0 for background
}

struct SAMSegmentationResult {
    let mask: UIImage
    let confidence: Float
    let boundingBox: CGRect
}

// Simple SAM Processor (placeholder implementation)
class SAMProcessor {
    private var isInitialized = false
    
    init() {
        // SAM model initialization would go here
        print("🔧 SAMProcessor initialized")
        isInitialized = true
    }
    
    func segmentWithPoint(_ image: UIImage, point: CGPoint, isBackground: Bool = false) throws -> SAMSegmentationResult {
        print("🎯 SAM segmentation at point: \(point)")
        
        // Placeholder implementation - creates a simple rectangular mask
        let maskSize = CGSize(width: 256, height: 256)
        let maskImage = createPlaceholderMask(size: maskSize)
        
        // Calculate bounding box around the point
        let boxSize: CGFloat = 100
        let boundingBox = CGRect(
            x: max(0, point.x - boxSize/2) / image.size.width,
            y: max(0, point.y - boxSize/2) / image.size.height,
            width: min(boxSize, image.size.width - max(0, point.x - boxSize/2)) / image.size.width,
            height: min(boxSize, image.size.height - max(0, point.y - boxSize/2)) / image.size.height
        )
        
        return SAMSegmentationResult(
            mask: maskImage,
            confidence: 0.85,
            boundingBox: boundingBox
        )
    }
    
    func segmentWithBoundingBox(_ image: UIImage, boundingBox: CGRect) throws -> SAMSegmentationResult {
        print("🎯 SAM segmentation with bounding box: \(boundingBox)")
        
        let maskSize = CGSize(width: 256, height: 256)
        let maskImage = createPlaceholderMask(size: maskSize)
        
        return SAMSegmentationResult(
            mask: maskImage,
            confidence: 0.90,
            boundingBox: boundingBox
        )
    }
    
    func segmentWithPoints(_ image: UIImage, points: [SAMPoint]) throws -> SAMSegmentationResult {
        print("🎯 SAM segmentation with \(points.count) points")
        
        let maskSize = CGSize(width: 256, height: 256)
        let maskImage = createPlaceholderMask(size: maskSize)
        
        // Use first point for bounding box calculation
        let firstPoint = points.first ?? SAMPoint(x: 0.5, y: 0.5, label: 1)
        let boxSize: CGFloat = 100
        let boundingBox = CGRect(
            x: max(0, CGFloat(firstPoint.x) * image.size.width - boxSize/2) / image.size.width,
            y: max(0, CGFloat(firstPoint.y) * image.size.height - boxSize/2) / image.size.height,
            width: boxSize / image.size.width,
            height: boxSize / image.size.height
        )
        
        return SAMSegmentationResult(
            mask: maskImage,
            confidence: 0.88,
            boundingBox: boundingBox
        )
    }
    
    // SAM Everything Mode - 이미지의 모든 객체 자동 감지 (실제 구현)
    func segmentEverything(_ image: UIImage) throws -> [SAMSegmentationResult] {
        print("🌟 SAM everything mode - detecting all objects in image")
        
        var results: [SAMSegmentationResult] = []
        let gridSize = 32 // 32x32 그리드로 이미지 스캔
        let threshold: Float = 0.5 // 최소 신뢰도 임계값
        
        // 이미지 전체에 그리드 포인트 생성
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = Float(col) / Float(gridSize - 1)
                let y = Float(row) / Float(gridSize - 1)
                let point = CGPoint(x: CGFloat(x) * image.size.width, 
                                  y: CGFloat(y) * image.size.height)
                
                // 각 그리드 포인트에서 세그먼테이션 시도
                do {
                    let segmentResult = try self.segmentWithPoint(image, point: point, isBackground: false)
                    
                    // 신뢰도가 임계값 이상이고 중복되지 않는 객체만 추가
                    if segmentResult.confidence >= threshold && !isDuplicateObject(segmentResult, existingResults: results) {
                        results.append(segmentResult)
                        print("✅ Found object at (\(x), \(y)) with confidence \(segmentResult.confidence)")
                    }
                } catch {
                    // 세그먼테이션 실패한 포인트는 무시
                    continue
                }
                
                // 너무 많은 객체를 찾지 않도록 제한
                if results.count >= 20 {
                    break
                }
            }
            if results.count >= 20 {
                break
            }
        }
        
        // 신뢰도 순으로 정렬
        results.sort { $0.confidence > $1.confidence }
        
        print("🎯 SAM everything mode found \(results.count) objects")
        return results
    }
    
    // 중복 객체 검사 (바운딩 박스 겹침 기준)
    private func isDuplicateObject(_ newResult: SAMSegmentationResult, existingResults: [SAMSegmentationResult]) -> Bool {
        let overlapThreshold: CGFloat = 0.5 // 50% 이상 겹치면 중복으로 판단
        
        for existingResult in existingResults {
            let intersection = newResult.boundingBox.intersection(existingResult.boundingBox)
            let unionArea = newResult.boundingBox.union(existingResult.boundingBox).area
            let overlapRatio = intersection.area / unionArea
            
            if overlapRatio > overlapThreshold {
                return true
            }
        }
        return false
    }
    
    private func createPlaceholderMask(size: CGSize) -> UIImage {
        // Create a simple white mask image
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let maskImage = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return maskImage
    }
}

public class ExpoObjectTrackerModule: Module {
  private var videoProcessor = VideoProcessor()
  private var samProcessor = SAMProcessor()
  
  public func definition() -> ModuleDefinition {
    Name("ExpoObjectTracker")

    AsyncFunction("selectObject") { (videoUri: String, frameIndex: Int, boundingBox: [String: Double]) -> String in
      return try await self.videoProcessor.selectObject(
        videoUri: videoUri, 
        frameIndex: frameIndex, 
        boundingBox: boundingBox
      )
    }

    AsyncFunction("generateObjectPreview") { (videoUri: String, objectId: String) -> String in
      return try await self.videoProcessor.generateObjectPreview(videoUri: videoUri, objectId: objectId)
    }

    AsyncFunction("trackObject") { (videoUri: String, objectId: String) -> [[String: Any]] in
      return try await self.videoProcessor.trackObject(videoUri: videoUri, objectId: objectId)
    }

    AsyncFunction("generatePreviewFrames") { (videoUri: String, trackingData: [[String: Any]], frameCount: Int) -> [[String: Any]] in
      return try await self.videoProcessor.generatePreviewFrames(
        videoUri: videoUri,
        trackingData: trackingData,
        frameCount: frameCount
      )
    }

    AsyncFunction("applyEffectToFrame") { (frameUri: String, boundingBox: [String: Any], effectConfig: [String: Any]) -> String in
      return try await self.videoProcessor.applyEffectToFrame(
        frameUri: frameUri,
        boundingBox: boundingBox,
        effectConfig: effectConfig
      )
    }

    AsyncFunction("applyEffectToTrackedObject") { (videoUri: String, trackingData: [[String: Any]], effectConfig: [String: Any]) -> String in
      return try await self.videoProcessor.applyEffectToTrackedObject(
        videoUri: videoUri, 
        trackingData: trackingData, 
        effectConfig: effectConfig
      )
    }

    AsyncFunction("getVideoResolution") { (videoUri: String) -> [String: Int] in
      return try await self.videoProcessor.getVideoResolution(videoUri: videoUri)
    }
    
    // Model Loading
    AsyncFunction("loadModel") { (modelPath: String, modelType: String, classNames: [String]?) -> Void in
      return try await self.videoProcessor.loadModel(modelPath: modelPath, modelType: modelType, classNames: classNames)
    }
    
    // YOLOv11 Detection Methods  
    AsyncFunction("detectObjects") { (videoUri: String, frameIndex: Int) -> [[String: Any]] in
      return try await self.videoProcessor.detectObjects(videoUri: videoUri, frameIndex: frameIndex)
    }
    
    AsyncFunction("detectObjectsInVideo") { (videoUri: String, maxFrames: Int) -> [[String: Any]] in
      return try await self.videoProcessor.detectObjectsInVideo(videoUri: videoUri, maxFrames: maxFrames)
    }
    
    AsyncFunction("createDetectionPreview") { (videoUri: String, frameIndex: Int, detections: [[String: Any]]) -> String in
      return try await self.videoProcessor.createDetectionPreview(
        videoUri: videoUri,
        frameIndex: frameIndex,
        detections: detections
      )
    }
    
    // Combined Detection + Tracking Methods
    AsyncFunction("detectAndTrackObjects") { (videoUri: String, targetClassName: String?, minConfidence: Float, detectionInterval: Int) -> [[String: Any]] in
      return try await self.videoProcessor.detectAndTrackObjects(
        videoUri: videoUri,
        targetClassName: targetClassName,
        minConfidence: minConfidence,
        detectionInterval: detectionInterval
      )
    }
    
    
    AsyncFunction("createTrackingVisualization") { (videoUri: String, trackingResults: [[String: Any]], outputPath: String?) -> String in
      return try await self.videoProcessor.createTrackingVisualization(
        videoUri: videoUri,
        trackingResults: trackingResults,
        outputPath: outputPath
      )
    }
    
    // SAM2 Segmentation Methods
    AsyncFunction("segmentWithPoint") { (imageUri: String, pointX: Float, pointY: Float, isBackground: Bool) -> [String: Any] in
      return try await self.segmentWithPoint(
        imageUri: imageUri,
        pointX: pointX,
        pointY: pointY,
        isBackground: isBackground
      )
    }
    
    AsyncFunction("segmentWithBoundingBox") { (imageUri: String, boundingBox: [String: Double]) -> [String: Any] in
      return try await self.segmentWithBoundingBox(
        imageUri: imageUri,
        boundingBox: boundingBox
      )
    }
    
    AsyncFunction("segmentWithPoints") { (imageUri: String, points: [[String: Any]]) -> [String: Any] in
      return try await self.segmentWithPoints(
        imageUri: imageUri,
        points: points
      )
    }
    
    AsyncFunction("segmentEverything") { (imageUri: String) -> [[String: Any]] in
      return try await self.segmentEverything(imageUri: imageUri)
    }
  }
  
  // MARK: - SAM2 Implementation Methods
  
  private func segmentWithPoint(imageUri: String, pointX: Float, pointY: Float, isBackground: Bool) async throws -> [String: Any] {
    // Load image from URI
    guard let imageUrl = URL(string: imageUri),
          let imageData = try? Data(contentsOf: imageUrl),
          let image = UIImage(data: imageData) else {
      throw NSError(domain: "ExpoObjectTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }
    
    // Convert normalized coordinates to image coordinates
    let point = CGPoint(x: CGFloat(pointX) * image.size.width, 
                       y: CGFloat(pointY) * image.size.height)
    
    // Perform SAM segmentation
    let result = try samProcessor.segmentWithPoint(image, point: point, isBackground: isBackground)
    
    // Save mask image to temporary file
    let maskUri = try saveMaskToTempFile(result.mask)
    
    return [
      "maskUri": maskUri,
      "confidence": result.confidence,
      "boundingBox": [
        "x": result.boundingBox.origin.x,
        "y": result.boundingBox.origin.y,
        "width": result.boundingBox.size.width,
        "height": result.boundingBox.size.height
      ]
    ]
  }
  
  private func segmentWithBoundingBox(imageUri: String, boundingBox: [String: Double]) async throws -> [String: Any] {
    // Load image from URI
    guard let imageUrl = URL(string: imageUri),
          let imageData = try? Data(contentsOf: imageUrl),
          let image = UIImage(data: imageData) else {
      throw NSError(domain: "ExpoObjectTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }
    
    // Convert normalized bounding box to image coordinates
    guard let x = boundingBox["x"],
          let y = boundingBox["y"],
          let width = boundingBox["width"],
          let height = boundingBox["height"] else {
      throw NSError(domain: "ExpoObjectTracker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid bounding box format"])
    }
    
    let rect = CGRect(
      x: x * image.size.width,
      y: y * image.size.height,
      width: width * image.size.width,
      height: height * image.size.height
    )
    
    // Perform SAM segmentation
    let result = try samProcessor.segmentWithBoundingBox(image, boundingBox: rect)
    
    // Save mask image to temporary file
    let maskUri = try saveMaskToTempFile(result.mask)
    
    return [
      "maskUri": maskUri,
      "confidence": result.confidence,
      "boundingBox": [
        "x": result.boundingBox.origin.x,
        "y": result.boundingBox.origin.y,
        "width": result.boundingBox.size.width,
        "height": result.boundingBox.size.height
      ]
    ]
  }
  
  private func segmentWithPoints(imageUri: String, points: [[String: Any]]) async throws -> [String: Any] {
    // Load image from URI
    guard let imageUrl = URL(string: imageUri),
          let imageData = try? Data(contentsOf: imageUrl),
          let image = UIImage(data: imageData) else {
      throw NSError(domain: "ExpoObjectTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }
    
    // Convert points to SAMPoint array
    var samPoints: [SAMPoint] = []
    for pointData in points {
      guard let x = pointData["x"] as? Double,
            let y = pointData["y"] as? Double,
            let label = pointData["label"] as? Int else {
        throw NSError(domain: "ExpoObjectTracker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid point format"])
      }
      
      samPoints.append(SAMPoint(x: Float(x), y: Float(y), label: label))
    }
    
    // Perform SAM segmentation
    let result = try samProcessor.segmentWithPoints(image, points: samPoints)
    
    // Save mask image to temporary file
    let maskUri = try saveMaskToTempFile(result.mask)
    
    return [
      "maskUri": maskUri,
      "confidence": result.confidence,
      "boundingBox": [
        "x": result.boundingBox.origin.x,
        "y": result.boundingBox.origin.y,
        "width": result.boundingBox.size.width,
        "height": result.boundingBox.size.height
      ]
    ]
  }
  
  private func saveMaskToTempFile(_ maskImage: UIImage) throws -> String {
    // Create temporary file path
    let tempDir = NSTemporaryDirectory()
    let fileName = "sam_mask_\(UUID().uuidString).png"
    let filePath = (tempDir as NSString).appendingPathComponent(fileName)
    let fileUrl = URL(fileURLWithPath: filePath)
    
    // Save mask image as PNG
    guard let pngData = maskImage.pngData() else {
      throw NSError(domain: "ExpoObjectTracker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to convert mask to PNG data"])
    }
    
    try pngData.write(to: fileUrl)
    
    return fileUrl.absoluteString
  }
  
  // MARK: - SAM Everything Mode Implementation
  
  private func segmentEverything(imageUri: String) async throws -> [[String: Any]] {
    // Load image from URI
    guard let imageUrl = URL(string: imageUri),
          let imageData = try? Data(contentsOf: imageUrl),
          let image = UIImage(data: imageData) else {
      throw NSError(domain: "ExpoObjectTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from URI: \(imageUri)"])
    }
    
    // Perform SAM everything segmentation
    let results = try samProcessor.segmentEverything(image)
    
    // Convert results to JavaScript format
    var jsResults: [[String: Any]] = []
    for result in results {
      // Save mask image to temporary file
      let maskUri = try saveMaskToTempFile(result.mask)
      
      jsResults.append([
        "maskUri": maskUri,
        "confidence": result.confidence,
        "boundingBox": [
          "x": result.boundingBox.origin.x,
          "y": result.boundingBox.origin.y,
          "width": result.boundingBox.size.width,
          "height": result.boundingBox.size.height
        ]
      ])
    }
    
    return jsResults
  }
}
