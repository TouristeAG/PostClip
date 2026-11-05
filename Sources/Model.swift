import AppKit
import CryptoKit

/// Un élément de l'historique du presse-papiers.
struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, image, files }

    var id = UUID()
    var kind: Kind
    var text: String?
    var filePaths: [String]?
    var imageWidth: Int?
    var imageHeight: Int?
    var signature: String
    var date: Date
    var sourceBundleID: String?
    var pinned: Bool = false

    /// Texte affiché dans la liste (tronqué pour rester léger).
    var preview: String {
        switch kind {
        case .text:
            let raw = String((text ?? "").prefix(600))
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            return "Image"
        case .files:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            return names.joined(separator: ", ")
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        switch kind {
        case .text: return (text ?? "").localizedCaseInsensitiveContains(query)
        case .files: return preview.localizedCaseInsensitiveContains(query)
        case .image: return "image".localizedCaseInsensitiveContains(query)
        }
    }

    static func signature(prefix: String, data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Petits caches pour les icônes d'apps et les miniatures (évite de recharger à chaque rendu).
enum IconCache {
    private static var apps: [String: (name: String, icon: NSImage)] = [:]
    private static let thumbs = NSCache<NSString, NSImage>()

    static func app(_ bundleID: String?) -> (name: String, icon: NSImage)? {
        guard let bundleID else { return nil }
        if let cached = apps[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        apps[bundleID] = (name, icon)
        return (name, icon)
    }

    static func thumbnail(for item: ClipItem, store: ClipboardStore) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let img = thumbs.object(forKey: key) { return img }
        guard let img = NSImage(contentsOf: store.thumbURL(for: item.id)) else { return nil }
        thumbs.setObject(img, forKey: key)
        return img
    }

    static func fileIcon(_ path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    static func forget(_ id: UUID) { thumbs.removeObject(forKey: id.uuidString as NSString) }
}
