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
