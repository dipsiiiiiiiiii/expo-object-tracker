import { NativeModule, requireNativeModule } from 'expo';

import { BoundingBox, TrackingData, EffectConfig, PreviewFrame, DetectedObject, TrackedObject } from './ExpoObjectTracker.types';

declare class ExpoObjectTrackerModule extends NativeModule {
  selectObject(videoUri: string, frameIndex: number, boundingBox: BoundingBox): Promise<string>;
  generateObjectPreview(videoUri: string, objectId: string): Promise<string>;
  trackObject(videoUri: string, objectId: string): Promise<TrackingData[]>;
  generatePreviewFrames(videoUri: string, trackingData: TrackingData[], frameCount: number): Promise<PreviewFrame[]>;
  applyEffectToFrame(frameUri: string, boundingBox: BoundingBox, effectConfig: EffectConfig): Promise<string>;
  applyEffectToTrackedObject(videoUri: string, trackingData: TrackingData[], effectConfig: EffectConfig): Promise<string>;
  getVideoResolution(videoUri: string): Promise<{ width: number; height: number }>;
  
  // YOLOv11 Detection Methods
  detectObjects(videoUri: string, frameIndex: number): Promise<DetectedObject[]>;
  detectObjectsInVideo(videoUri: string, maxFrames: number): Promise<DetectedObject[]>;
  createDetectionPreview(videoUri: string, frameIndex: number, detections: DetectedObject[]): Promise<string>;
  
  // Combined YOLOv11 Detection + Vision Tracking Methods
  detectAndTrackObjects(videoUri: string, targetClassName?: string, minConfidence?: number, detectionInterval?: number): Promise<TrackedObject[]>;
  createTrackingVisualization(videoUri: string, trackingResults: TrackedObject[], outputPath?: string): Promise<string>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoObjectTrackerModule>('ExpoObjectTracker');
