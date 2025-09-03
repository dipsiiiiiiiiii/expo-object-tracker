import { Image as RNImage } from "react-native";
import ExpoObjectTrackerModule from "./ExpoObjectTrackerModule";
import {
  DetectedObject,
  TrackedObject,
  VideoProcessingOptions,
  EffectConfig,
  ModelConfig,
  SAMPoint,
  SAMSegmentationResult,
  SAMPrompt,
  BoundingBox,
} from "./ExpoObjectTracker.types";

export class VideoObjectTracker {
  private processingCallbacks: Map<
    string,
    (progress: number, status: string) => void
  > = new Map();

  /**
   * Load a custom model for object detection
   */
  async loadModel(modelConfig: ModelConfig): Promise<void> {
    try {
      await ExpoObjectTrackerModule.loadModel(
        modelConfig.modelPath,
        modelConfig.type,
        modelConfig.classNames
      );
      console.log("Model loaded successfully:", modelConfig);
    } catch (error) {
      console.error("Failed to load model:", error);
      throw error;
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
      const detections = await ExpoObjectTrackerModule.detectObjects(
        videoUri,
        frameIndex
      );
      return detections;
    } catch (error) {
      console.error("Failed to detect objects in frame:", error);
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
      const detections = await ExpoObjectTrackerModule.detectObjectsInVideo(
        videoUri,
        maxFrames
      );
      return detections;
    } catch (error) {
      console.error("Failed to detect objects in video:", error);
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
      console.error("Failed to create detection preview:", error);
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
      const {
        targetClassName,
        minConfidence = 0.5,
        detectionInterval = 1,
      } = options;

      if (onProgress) {
        onProgress(0, "Starting object detection and tracking...");
      }

      const trackingResults =
        await ExpoObjectTrackerModule.detectAndTrackObjects(
          videoUri,
          targetClassName,
          minConfidence,
          detectionInterval
        );

      if (onProgress) {
        onProgress(100, "Object detection and tracking completed");
      }

      return trackingResults;
    } catch (error) {
      console.error("Failed to detect and track objects:", error);
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
        onProgress(0, "Creating tracking visualization...");
      }

      const visualizationUri =
        await ExpoObjectTrackerModule.createTrackingVisualization(
          videoUri,
          trackingResults,
          outputPath
        );

      if (onProgress) {
        onProgress(100, "Tracking visualization completed");
      }

      return visualizationUri;
    } catch (error) {
      console.error("Failed to create tracking visualization:", error);
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
        onProgress(0, "Applying effects to tracked objects...");
      }

      // Convert TrackedObject[] to TrackingData[] format expected by the module
      const trackingData = trackingResults.map((result) => ({
        frameIndex: result.frameIndex,
        boundingBox: result.boundingBox,
        confidence: result.confidence,
      }));

      const processedVideoUri =
        await ExpoObjectTrackerModule.applyEffectToTrackedObject(
          videoUri,
          trackingData,
          effectConfig
        );

      if (onProgress) {
        onProgress(100, "Video processing with effects completed");
      }

      return processedVideoUri;
    } catch (error) {
      console.error("Failed to process video with effects:", error);
      throw error;
    }
  }

  /**
   * Get video resolution information
   */
  async getVideoResolution(
    videoUri: string
  ): Promise<{ width: number; height: number }> {
    try {
      const resolution =
        await ExpoObjectTrackerModule.getVideoResolution(videoUri);
      return resolution;
    } catch (error) {
      console.error("Failed to get video resolution:", error);
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
        outputPath,
      } = options;

      // Step 1: Detect and track objects
      if (onProgress) onProgress(0, "Detecting and tracking objects...");

      const trackingResults = await this.detectAndTrackObjects(
        videoUri,
        { targetClassName, minConfidence },
        (progress, status) => {
          if (onProgress) onProgress(progress * 0.6, status);
        }
      );

      if (trackingResults.length === 0) {
        throw new Error("No objects detected in video");
      }

      // Step 2: Apply effects if configured
      let processedVideoUri: string | undefined;
      if (effectConfig) {
        if (onProgress) onProgress(60, "Applying effects...");

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
        if (onProgress) onProgress(90, "Creating visualization...");

        visualizationUri = await this.createTrackingVisualization(
          processedVideoUri || videoUri,
          trackingResults,
          outputPath,
          (progress, status) => {
            if (onProgress) onProgress(90 + progress * 0.1, status);
          }
        );
      }

      if (onProgress) onProgress(100, "Video processing completed");

      return {
        trackingResults,
        processedVideoUri,
        visualizationUri,
      };
    } catch (error) {
      console.error("Failed to process video:", error);
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
      "person",
      "bicycle",
      "car",
      "motorcycle",
      "airplane",
      "bus",
      "train",
      "truck",
      "boat",
      "traffic light",
      "fire hydrant",
      "stop sign",
      "parking meter",
      "bench",
      "bird",
      "cat",
      "dog",
      "horse",
      "sheep",
      "cow",
      "elephant",
      "bear",
      "zebra",
      "giraffe",
      "backpack",
      "umbrella",
      "handbag",
      "tie",
      "suitcase",
      "frisbee",
      "skis",
      "snowboard",
      "sports ball",
      "kite",
      "baseball bat",
      "baseball glove",
      "skateboard",
      "surfboard",
      "tennis racket",
      "bottle",
      "wine glass",
      "cup",
      "fork",
      "knife",
      "spoon",
      "bowl",
      "banana",
      "apple",
      "sandwich",
      "orange",
      "broccoli",
      "carrot",
      "hot dog",
      "pizza",
      "donut",
      "cake",
      "chair",
      "couch",
      "potted plant",
      "bed",
      "dining table",
      "toilet",
      "tv",
      "laptop",
      "mouse",
      "remote",
      "keyboard",
      "cell phone",
      "microwave",
      "oven",
      "toaster",
      "sink",
      "refrigerator",
      "book",
      "clock",
      "vase",
      "scissors",
      "teddy bear",
      "hair drier",
      "toothbrush",
    ];
  }

  // MARK: - SAM2 Segmentation Methods

  /**
   * Segment an object in an image using a single point prompt
   */
  async segmentWithPoint(
    imageUri: string,
    point: { x: number; y: number },
    isBackground: boolean = false
  ): Promise<SAMSegmentationResult> {
    try {
      const result = await ExpoObjectTrackerModule.segmentWithPoint(
        imageUri,
        point.x,
        point.y,
        isBackground
      );
      return result as SAMSegmentationResult;
    } catch (error) {
      console.error("Failed to segment with point:", error);
      throw error;
    }
  }

  /**
   * Segment an object in an image using a bounding box prompt
   */
  async segmentWithBoundingBox(
    imageUri: string,
    boundingBox: BoundingBox
  ): Promise<SAMSegmentationResult> {
    try {
      const result = await ExpoObjectTrackerModule.segmentWithBoundingBox(
        imageUri,
        boundingBox
      );
      return result as SAMSegmentationResult;
    } catch (error) {
      console.error("Failed to segment with bounding box:", error);
      throw error;
    }
  }

  /**
   * Segment an object in an image using multiple point prompts
   */
  async segmentWithPoints(
    imageUri: string,
    points: SAMPoint[]
  ): Promise<SAMSegmentationResult> {
    try {
      const result = await ExpoObjectTrackerModule.segmentWithPoints(
        imageUri,
        points
      );
      return result as SAMSegmentationResult;
    } catch (error) {
      console.error("Failed to segment with points:", error);
      throw error;
    }
  }

  /**
   * Segment all objects in an image using SAM everything mode
   */
  async segmentEverything(imageUri: string): Promise<SAMSegmentationResult[]> {
    try {
      const results = await ExpoObjectTrackerModule.segmentEverything(imageUri);
      return results as SAMSegmentationResult[];
    } catch (error) {
      console.error("Failed to segment everything:", error);
      throw error;
    }
  }

  /**
   * Universal segment method that accepts different prompt types
   */
  async segment(
    imageUri: string,
    prompt: SAMPrompt
  ): Promise<SAMSegmentationResult> {
    switch (prompt.type) {
      case 'point':
        return this.segmentWithPoint(
          imageUri, 
          prompt.point, 
          prompt.isBackground || false
        );
      
      case 'points':
        return this.segmentWithPoints(imageUri, prompt.points);
      
      case 'boundingBox':
        return this.segmentWithBoundingBox(imageUri, prompt.boundingBox);
      
      default:
        throw new Error(`Unsupported prompt type: ${(prompt as any).type}`);
    }
  }

  /**
   * Create a visualization overlay showing the segmented mask on the original image
   */
  async createSegmentationOverlay(
    _originalImageUri: string,
    maskUri: string,
    _color: string = '#FF0000',
    _opacity: number = 0.5
  ): Promise<string> {
    // This could be implemented using native image processing
    // For now, return the mask URI as a placeholder
    console.warn("createSegmentationOverlay not yet implemented - returning mask URI");
    return maskUri;
  }
}

// Export singleton instance
export default new VideoObjectTracker();
