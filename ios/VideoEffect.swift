import Foundation
import CoreImage
import UIKit

protocol VideoEffect {
    func apply(to image: CIImage, boundingBox: CGRect) -> CIImage
}

class BlurEffect: VideoEffect {
    let intensity: Float
    
    init(intensity: Float) {
        self.intensity = max(0, min(20, intensity))
    }
    
    func apply(to image: CIImage, boundingBox: CGRect) -> CIImage {
        let context = CIContext()
        
        // 바운딩 박스 영역만 크롭
        let croppedImage = image.cropped(to: boundingBox)
        
        // 가우시안 블러 필터 적용
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return image
        }
        
        blurFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        blurFilter.setValue(intensity, forKey: kCIInputRadiusKey)
        
        guard let blurredImage = blurFilter.outputImage else {
            return image
        }
        
        // 블러된 이미지를 원본 위치에 합성
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }
        
        compositeFilter.setValue(blurredImage, forKey: kCIInputImageKey)
        compositeFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return compositeFilter.outputImage ?? image
    }
}

class MosaicEffect: VideoEffect {
    let blockSize: Float
    
    init(blockSize: Float) {
        self.blockSize = max(5, min(50, blockSize))
    }
    
    func apply(to image: CIImage, boundingBox: CGRect) -> CIImage {
        let croppedImage = image.cropped(to: boundingBox)
        
        // 픽셀레이트 필터로 모자이크 효과
        guard let pixelateFilter = CIFilter(name: "CIPixellate") else {
            return image
        }
        
        pixelateFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        pixelateFilter.setValue(blockSize, forKey: kCIInputScaleKey)
        
        guard let pixelatedImage = pixelateFilter.outputImage else {
            return image
        }
        
        // 원본에 합성
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }
        
        compositeFilter.setValue(pixelatedImage, forKey: kCIInputImageKey)
        compositeFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return compositeFilter.outputImage ?? image
    }
}

class EmojiEffect: VideoEffect {
    let emoji: String
    let scale: Float
    let rotation: Float
    
    init(emoji: String, scale: Float, rotation: Float = 0) {
        self.emoji = emoji
        self.scale = max(0.5, min(3.0, scale))
        self.rotation = rotation
    }
    
    func apply(to image: CIImage, boundingBox: CGRect) -> CIImage {
        // 이모지를 이미지로 렌더링
        guard let emojiImage = renderEmoji(emoji: emoji, size: boundingBox.size, scale: scale, rotation: rotation) else {
            return image
        }
        
        // 이모지를 바운딩 박스 위치에 합성
        let translatedEmoji = emojiImage.transformed(by: CGAffineTransform(translationX: boundingBox.origin.x, y: boundingBox.origin.y))
        
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }
        
        compositeFilter.setValue(translatedEmoji, forKey: kCIInputImageKey)
        compositeFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return compositeFilter.outputImage ?? image
    }
    
    private func renderEmoji(emoji: String, size: CGSize, scale: Float, rotation: Float) -> CIImage? {
        let fontSize = min(size.width, size.height) * CGFloat(scale)
        let font = UIFont.systemFont(ofSize: fontSize)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: emoji, attributes: attributes)
        let stringSize = attributedString.size()
        
        let renderer = UIGraphicsImageRenderer(size: stringSize)
        let uiImage = renderer.image { context in
            attributedString.draw(at: CGPoint.zero)
        }
        
        var ciImage = CIImage(image: uiImage)
        
        // 회전 적용
        if rotation != 0 {
            let radians = rotation * Float.pi / 180
            let transform = CGAffineTransform(rotationAngle: CGFloat(radians))
            ciImage = ciImage?.transformed(by: transform)
        }
        
        return ciImage
    }
}

class ColorEffect: VideoEffect {
    let color: CIColor
    let opacity: Float
    
    init(color: CIColor, opacity: Float) {
        self.color = color
        self.opacity = max(0, min(1, opacity))
    }
    
    func apply(to image: CIImage, boundingBox: CGRect) -> CIImage {
        // 단색 이미지 생성
        guard let colorFilter = CIFilter(name: "CIConstantColorGenerator") else {
            return image
        }
        
        colorFilter.setValue(color, forKey: kCIInputColorKey)
        
        guard let colorImage = colorFilter.outputImage?.cropped(to: boundingBox) else {
            return image
        }
        
        // 투명도 적용
        guard let opacityFilter = CIFilter(name: "CIColorMatrix") else {
            return image
        }
        
        opacityFilter.setValue(colorImage, forKey: kCIInputImageKey)
        opacityFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)), forKey: "inputAVector")
        
        guard let transparentColorImage = opacityFilter.outputImage else {
            return image
        }
        
        // 원본에 합성
        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            return image
        }
        
        compositeFilter.setValue(transparentColorImage, forKey: kCIInputImageKey)
        compositeFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return compositeFilter.outputImage ?? image
    }
}