import AppKit
import RemoteFitCore

/// Shipped UU / RustDesk marks. 16pt badge on the preview’s bottom-left, 8pt from those edges.
/// Bitmaps are 32 (@2x), 64, and 128 so higher-density screens can pick a sharper rep.
@MainActor
enum RemoteSoftwareIcon {
    static let pointSize: CGFloat = 16
    static let cornerRadius: CGFloat = 4
    static let inset: CGFloat = 8
    static let borderWidth: CGFloat = 0.5
    static let borderOpacity: CGFloat = 0.2

    private static var cache: [RemoteSoftware: NSImage] = [:]

    static func image(for software: RemoteSoftware) -> NSImage? {
        if let cached = cache[software] { return cached }
        let name: String
        switch software {
        case .uu: name = "uu"
        case .rustDesk: name = "rustdesk"
        case .toDesk, .anyDesk: return nil
        }
        guard let image = image(named: name) else { return nil }
        image.accessibilityDescription = software.title
        cache[software] = image
        return image
    }

    static func image(named name: String, directory: URL? = nil) -> NSImage? {
        let urls = [32, 64, 128].compactMap { resourceURL(name: name, pixels: $0, directory: directory) }
        guard !urls.isEmpty else { return nil }
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        var added = false
        for url in urls {
            guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = NSSize(width: pointSize, height: pointSize)
            image.addRepresentation(rep)
            added = true
        }
        guard added else { return nil }
        image.isTemplate = false
        return image
    }

    private static func resourceURL(name: String, pixels: Int, directory: URL?) -> URL? {
        if let directory {
            let url = directory.appendingPathComponent("\(name)-\(pixels).png")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let url = Bundle.main.url(forResource: "\(name)-\(pixels)", withExtension: "png") {
            return url
        }
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("assets/software/\(name)-\(pixels).png")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}
