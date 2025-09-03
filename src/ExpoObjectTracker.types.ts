export type BoundingBox = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type TrackingData = {
  frameIndex: number;
  boundingBox: BoundingBox;
  confidence: number;
};

export type BlurEffect = {
  type: 'blur';
  intensity: number; // 0-20
};

export type MosaicEffect = {
  type: 'mosaic';  
  blockSize: number; // 5-50
};

export type EmojiEffect = {
  type: 'emoji';
  emoji: string;
  scale: number; // 0.5-3.0
  rotation?: number; // 0-360
};

export type ColorEffect = {
  type: 'color';
  color: string; // hex color like "#FF0000"
  opacity: number; // 0-1
};

export type EffectConfig = BlurEffect | MosaicEffect | EmojiEffect | ColorEffect;

export type PreviewFrame = {
  frameIndex: number;
  imageUri: string;
  boundingBox: BoundingBox;
};

export type DetectedObject = {
  className: string;
  confidence: number;
  boundingBox: BoundingBox;
  identifier: string;
  frameIndex?: number;
  time?: number;
  segmentationMask?: string; // Base64 encoded image or URI for segmentation mask
};

export type TrackedObject = {
  objectId: string;
  frameIndex: number;
  className: string;
  confidence: number;
  source: 'detection' | 'tracking';
  boundingBox: BoundingBox;
};

export type ModelConfig = {
  modelPath: string;
  type: 'yolo11' | 'custom';
  classNames?: string[];
};

export type VideoProcessingOptions = {
  targetClassName?: string;
  minConfidence?: number;
  maxFrames?: number;
  modelConfig?: ModelConfig;
};

export type ExpoObjectTrackerModuleEvents = {
  onChange: {
    value: string;
  };
};

export type ExpoObjectTrackerViewProps = {
  style?: any;
};
