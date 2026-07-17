import Foundation
import CoreGraphics

// Sticky editor settings — remembered across captures via UserDefaults.
enum Prefs {
    private static let d = UserDefaults.standard
    private static func read(_ key: String, _ fallback: CGFloat) -> CGFloat {
        d.object(forKey: key) == nil ? fallback : CGFloat(d.double(forKey: key))
    }

    static var padding: CGFloat {
        get { read("padding", 0.06) } set { d.set(Double(newValue), forKey: "padding") }
    }
    static var corner: CGFloat {
        get { read("corner", 0.03) } set { d.set(Double(newValue), forKey: "corner") }
    }
    static var shadow: CGFloat {
        get { read("shadow", 0.5) } set { d.set(Double(newValue), forKey: "shadow") }
    }
    static var blurIntensity: CGFloat {
        get { read("blurIntensity", 1) } set { d.set(Double(newValue), forKey: "blurIntensity") }
    }
    static var pixelateIntensity: CGFloat {
        get { read("pixelateIntensity", 1) } set { d.set(Double(newValue), forKey: "pixelateIntensity") }
    }
}
