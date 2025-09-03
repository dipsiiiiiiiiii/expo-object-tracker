import ExpoObjectTrackerModule from './ExpoObjectTrackerModule';
import { DetectedObject, TrackedObject, VideoProcessingOptions, EffectConfig, ModelConfig } from './ExpoObjectTracker.types';

export class VideoObjectTracker {
  private processingCallbacks: Map<string, (progress: number, status: string) => void> = new Map();

  /**
   * Load a custom model for object detection
   */
  async loadModel(modelConfig: ModelConfig): Promise<void> {
    try {
      await ExpoObjectTrackerModule.loadModel(modelConfig.modelPath, modelConfig.type, modelConfig.classNames);
      console.log('Model loaded successfully:', modelConfig);
    } catch (error) {
      console.error('Failed to load model:', error);
      throw error;
    }
  }

  /**
   * Load built-in YOLOv11n-seg model (automatically finds the best available format)
   */
  async loadBuiltinYolo11Model(): Promise<void> {
    try {
      // Try to load YOLOv11-seg first (segmentation model), fallback to regular YOLOv11n
      await ExpoObjectTrackerModule.loadModel('yolo11n-seg', 'yolo11', this.getAvailableClasses());
      console.log('Built-in YOLOv11n-seg model loaded successfully');
    } catch (error) {
      console.warn('Failed to load YOLOv11-seg, trying YOLOv11n:', error);
      try {
        await ExpoObjectTrackerModule.loadModel('yolo11n', 'yolo11', this.getAvailableClasses());
        console.log('Built-in YOLOv11n model loaded successfully');
      } catch (fallbackError) {
        console.error('Failed to load any built-in YOLO model:', fallbackError);
        throw fallbackError;
      }
    }
  }

  /**
   * Detect objects in a single video frame using YOLOv11
   */
  async detectObjectsInFrame(
    videoUri: string,
    frameIndex: number = 0
  ): Promise<DetectedObject[]> {
    try {
      const detections = await ExpoObjectTrackerModule.detectObjects(videoUri, frameIndex);
      return detections;
    } catch (error) {
      console.error('Failed to detect objects in frame:', error);
      throw error;
    }
  }

  /**
   * Detect objects across multiple frames in a video
   */
  async detectObjectsInVideo(
    videoUri: string,
    options: VideoProcessingOptions = {}
  ): Promise<DetectedObject[]> {
    try {
      const { maxFrames = 30 } = options;
      const detections = await ExpoObjectTrackerModule.detectObjectsInVideo(videoUri, maxFrames);
      return detections;
    } catch (error) {
      console.error('Failed to detect objects in video:', error);
      throw error;
    }
  }

  /**
   * Create a preview image showing detected objects with bounding boxes
   */
  async createDetectionPreview(
    videoUri: string,
    frameIndex: number,
    detections: DetectedObject[]
  ): Promise<string> {
    try {
      const previewUri = await ExpoObjectTrackerModule.createDetectionPreview(
        videoUri,
        frameIndex,
        detections
      );
      return previewUri;
    } catch (error) {
      console.error('Failed to create detection preview:', error);
      throw error;
    }
  }

  /**
   * Detect and track objects throughout a video using YOLOv11 + Vision tracking
   */
  async detectAndTrackObjects(
    videoUri: string,
    options: VideoProcessingOptions & { detectionInterval?: number } = {},
    onProgress?: (progress: number, status: string) => void
  ): Promise<TrackedObject[]> {
    try {
      const { targetClassName, minConfidence = 0.5, detectionInterval = 1 } = options;
      
      if (onProgress) {
        onProgress(0, 'Starting object detection and tracking...');
      }

      const trackingResults = await ExpoObjectTrackerModule.detectAndTrackObjects(
        videoUri,
        targetClassName,
        minConfidence,
        detectionInterval
      );

      if (onProgress) {
        onProgress(100, 'Object detection and tracking completed');
      }

      return trackingResults;
    } catch (error) {
      console.error('Failed to detect and track objects:', error);
      throw error;
    }
  }


  /**
   * Create a video with tracking visualization
   */
  async createTrackingVisualization(
    videoUri: string,
    trackingResults: TrackedObject[],
    outputPath?: string,
    onProgress?: (progress: number, status: string) => void
  ): Promise<string> {
    try {
      if (onProgress) {
        onProgress(0, 'Creating tracking visualization...');
      }

      const visualizationUri = await ExpoObjectTrackerModule.createTrackingVisualization(
        videoUri,
        trackingResults,
        outputPath
      );

      if (onProgress) {
        onProgress(100, 'Tracking visualization completed');
      }

      return visualizationUri;
    } catch (error) {
      console.error('Failed to create tracking visualization:', error);
      throw error;
    }
  }

  /**
   * Apply effects to tracked objects in a video
   */
  async processVideoWithEffects(
    videoUri: string,
    trackingResults: TrackedObject[],
    effectConfig: EffectConfig,
    onProgress?: (progress: number, status: string) => void
  ): Promise<string> {
    try {
      if (onProgress) {
        onProgress(0, 'Applying effects to tracked objects...');
      }

      // Convert TrackedObject[] to TrackingData[] format expected by the module
      const trackingData = trackingResults.map(result => ({
        frameIndex: result.frameIndex,
        boundingBox: result.boundingBox,
        confidence: result.confidence
      }));

      const processedVideoUri = await ExpoObjectTrackerModule.applyEffectToTrackedObject(
        videoUri,
        trackingData,
        effectConfig
      );

      if (onProgress) {
        onProgress(100, 'Video processing with effects completed');
      }

      return processedVideoUri;
    } catch (error) {
      console.error('Failed to process video with effects:', error);
      throw error;
    }
  }

  /**
   * Get video resolution information
   */
  async getVideoResolution(videoUri: string): Promise<{ width: number; height: number }> {
    try {
      const resolution = await ExpoObjectTrackerModule.getVideoResolution(videoUri);
      return resolution;
    } catch (error) {
      console.error('Failed to get video resolution:', error);
      throw error;
    }
  }

  /**
   * Complete workflow: detect, track, and process video
   */
  async processVideo(
    videoUri: string,
    options: VideoProcessingOptions & {
      effectConfig?: EffectConfig;
      createVisualization?: boolean;
      outputPath?: string;
    } = {},
    onProgress?: (progress: number, status: string) => void
  ): Promise<{
    trackingResults: TrackedObject[];
    processedVideoUri?: string;
    visualizationUri?: string;
  }> {
    try {
      const {
        targetClassName,
        minConfidence = 0.5,
        effectConfig,
        createVisualization = false,
        outputPath
      } = options;

      // Step 1: Detect and track objects
      if (onProgress) onProgress(0, 'Detecting and tracking objects...');
      
      const trackingResults = await this.detectAndTrackObjects(
        videoUri,
        { targetClassName, minConfidence },
        (progress, status) => {
          if (onProgress) onProgress(progress * 0.6, status);
        }
      );

      if (trackingResults.length === 0) {
        throw new Error('No objects detected in video');
      }

      // Step 2: Apply effects if configured
      let processedVideoUri: string | undefined;
      if (effectConfig) {
        if (onProgress) onProgress(60, 'Applying effects...');
        
        processedVideoUri = await this.processVideoWithEffects(
          videoUri,
          trackingResults,
          effectConfig,
          (progress, status) => {
            if (onProgress) onProgress(60 + progress * 0.3, status);
          }
        );
      }

      // Step 3: Create visualization if requested
      let visualizationUri: string | undefined;
      if (createVisualization) {
        if (onProgress) onProgress(90, 'Creating visualization...');
        
        visualizationUri = await this.createTrackingVisualization(
          processedVideoUri || videoUri,
          trackingResults,
          outputPath,
          (progress, status) => {
            if (onProgress) onProgress(90 + progress * 0.1, status);
          }
        );
      }

      if (onProgress) onProgress(100, 'Video processing completed');

      return {
        trackingResults,
        processedVideoUri,
        visualizationUri
      };
    } catch (error) {
      console.error('Failed to process video:', error);
      throw error;
    }
  }

  /**
   * Cancel ongoing processing operations
   */
  cancelProcessing(operationId: string): void {
    this.processingCallbacks.delete(operationId);
  }

  /**
   * Get available object classes that YOLOv11 can detect
   */
  getAvailableClasses(): string[] {
    return [
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
    ];
  }
}

// Export singleton instance
export default new VideoObjectTracker();