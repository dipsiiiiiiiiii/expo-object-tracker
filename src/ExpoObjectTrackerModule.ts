import { NativeModule, requireNativeModule } from 'expo';

import { BoundingBox, TrackingData, EffectConfig, PreviewFrame } from './ExpoObjectTracker.types';

declare class ExpoObjectTrackerModule extends NativeModule {
  selectObject(videoUri: string, frameIndex: number, boundingBox: BoundingBox): Promise<string>;
  generateObjectPreview(videoUri: string, objectId: string): Promise<string>;
  trackObject(videoUri: string, objectId: string): Promise<TrackingData[]>;
  generatePreviewFrames(videoUri: string, trackingData: TrackingData[], frameCount: number): Promise<PreviewFrame[]>;
  applyEffectToFrame(frameUri: string, boundingBox: BoundingBox, effectConfig: EffectConfig): Promise<string>;
  applyEffectToTrackedObject(videoUri: string, trackingData: TrackingData[], effectConfig: EffectConfig): Promise<string>;
  getVideoResolution(videoUri: string): Promise<{ width: number; height: number }>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoObjectTrackerModule>('ExpoObjectTracker');
