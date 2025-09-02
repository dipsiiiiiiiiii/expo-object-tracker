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
  }
}
