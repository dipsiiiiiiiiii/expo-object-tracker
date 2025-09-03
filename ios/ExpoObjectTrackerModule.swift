import ExpoModulesCore
import Vision
import AVFoundation
import UIKit

public class ExpoObjectTrackerModule: Module {
  private var videoProcessor = VideoProcessor()
  
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
  }
}
