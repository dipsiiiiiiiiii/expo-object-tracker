import Foundation
import Vision
import AVFoundation
import UIKit
import CoreGraphics

class VideoProcessor {
    private var trackedObjects: [String: VNTrackingRequest] = [:]
    private var selectedObservations: [String: VNDetectedObjectObservation] = [:]
    
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
}