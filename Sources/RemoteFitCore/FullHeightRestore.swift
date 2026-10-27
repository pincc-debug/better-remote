import Foundation

public enum FullHeightRestore {
    /// Match a cropped 16:10 built-in mode to the panel's native full-height aspect.
    /// Width, backing scale and refresh rate stay unchanged; external panels are excluded.
    public static func mode(saved: DisplayMode, available: [DisplayMode], nativePixels: Dimensions?, builtin: Bool) -> DisplayMode {
        guard builtin, let nativePixels, nativePixels.width > 0, nativePixels.height > 0,
              saved.width > 0, saved.height > 0, saved.pixelWidth > 0,
              abs(Double(saved.height) - Double(saved.width) * 10 / 16) <= 1 else { return saved }
        let expectedHeight = Double(saved.width) * Double(nativePixels.height) / Double(nativePixels.width)
        guard expectedHeight > Double(saved.height) + 1,
              expectedHeight <= Double(saved.height) * 1.06 else { return saved }
        let scale = Double(saved.pixelWidth) / Double(saved.width)
        return available.first {
            $0.width == saved.width && $0.pixelWidth == saved.pixelWidth && $0.height > saved.height &&
            abs(Double($0.height) - expectedHeight) <= 1 &&
            abs(Double($0.pixelHeight) / Double($0.height) - scale) < 0.01 &&
            abs($0.refresh - saved.refresh) < 0.01
        } ?? saved
    }
}
