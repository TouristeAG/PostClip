import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Historique persistant (~/Library/Application Support/PostClip).
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    var maxItems: Int {
        let v = UserDefaults.standard.integer(forKey: "maxItems")
        return v > 0 ? v : 100
    }

    let baseDir: URL
    let imagesDir: URL
    private let historyURL: URL
    let ioQueue = DispatchQueue(label: "postclip.io", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    init(baseDir custom: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDir = custom ?? support.appendingPathComponent("PostClip", isDirectory: true)
        // Reprise de l'historique de l'ancienne version (ClipPanel)
        let legacy = support.appendingPathComponent("ClipPanel", isDirectory: true)
        if custom == nil, !FileManager.default.fileExists(atPath: baseDir.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: baseDir)
        }
        imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        historyURL = baseDir.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Fichiers image

    func imageURL(for id: UUID) -> URL { imagesDir.appendingPathComponent("\(id.uuidString).png") }
    func thumbURL(for id: UUID) -> URL { imagesDir.appendingPathComponent("\(id.uuidString)_t.png") }

    private func deleteFiles(of item: ClipItem) {
        guard item.kind == .image else { return }
        IconCache.forget(item.id)
        let a = imageURL(for: item.id), b = thumbURL(for: item.id)
        ioQueue.async {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
    }

    // MARK: Mutations

    /// Si un élément identique existe déjà, il remonte en tête. Retourne true dans ce cas.
    @discardableResult
    func bump(signature: String, source: String?) -> Bool {
        guard let idx = items.firstIndex(where: { $0.signature == signature }) else { return false }
        var existing = items.remove(at: idx)
        existing.date = Date()
        if let source { existing.sourceBundleID = source }
        items.insert(existing, at: 0)
        scheduleSave()
        return true
    }

    func insert(_ item: ClipItem) {
        if bump(signature: item.signature, source: item.sourceBundleID) {
            deleteFiles(of: item)
            return
        }
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    func touch(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var it = items.remove(at: idx)
        it.date = Date()
        items.insert(it, at: 0)
        scheduleSave()
    }

    func remove(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let it = items.remove(at: idx)
        deleteFiles(of: it)
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinned.toggle()
        scheduleSave()
    }

    /// Efface tout sauf les éléments épinglés.
    func clearUnpinned() {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        removed.forEach(deleteFiles)
        scheduleSave()
    }

    private func trim() {
        var unpinned = items.filter { !$0.pinned }.count
        while unpinned > maxItems, let idx = items.lastIndex(where: { !$0.pinned }) {
            deleteFiles(of: items.remove(at: idx))
            unpinned -= 1
        }
    }

    // MARK: Persistance

    private func load() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        let fm = FileManager.default
        items = decoded.filter { $0.kind != .image || fm.fileExists(atPath: imageURL(for: $0.id).path) }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = items
        let url = historyURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        pendingSave = work
        ioQueue.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: Images

    /// Encode l'image en PNG + génère une miniature. Appelé sur ioQueue.
    func writeImage(data: Data, id: UUID) -> (width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }

        // Image complète
        let isPNG = (CGImageSourceGetType(src) as String?) == UTType.png.identifier
        if isPNG {
            try? data.write(to: imageURL(for: id))
        } else {
            guard writePNG(full, to: imageURL(for: id)) else { return nil }
        }

        // Miniature (360 px max → ~nets en Retina, très légers en mémoire)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
            _ = writePNG(thumb, to: thumbURL(for: id))
        }
        return (full.width, full.height)
    }

    private func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
