import Foundation
import CoreImage
import UIKit

class EffectFactory {
    static func createEffect(from config: [String: Any]) -> VideoEffect? {
        guard let type = config["type"] as? String else {
            return nil
        }
        
        switch type {
        case "blur":
            guard let intensity = config["intensity"] as? NSNumber else { return nil }
            return BlurEffect(intensity: intensity.floatValue)
            
        case "mosaic":
            guard let blockSize = config["blockSize"] as? NSNumber else { return nil }
            return MosaicEffect(blockSize: blockSize.floatValue)
            
        case "emoji":
            guard let emoji = config["emoji"] as? String,
                  let scale = config["scale"] as? NSNumber else { return nil }
            
            let rotation = (config["rotation"] as? NSNumber)?.floatValue ?? 0
            return EmojiEffect(emoji: emoji, scale: scale.floatValue, rotation: rotation)
            
        case "color":
            guard let colorString = config["color"] as? String,
                  let opacity = config["opacity"] as? NSNumber else { return nil }
            
            let color = parseHexColor(colorString)
            return ColorEffect(color: color, opacity: opacity.floatValue)
            
        default:
            return nil
        }
    }
    
    static func parseHexColor(_ hex: String) -> CIColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0
        
        return CIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// Helper function to parse hex colors
private func parseHexColor(_ hex: String) -> CIColor {
    return EffectFactory.parseHexColor(hex)
}