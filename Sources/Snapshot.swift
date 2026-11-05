import AppKit
import SwiftUI

/// Mode diagnostic : `PostClip --snapshot out.png [dark]` rend le panneau avec des données d'exemple.
@MainActor enum Snapshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dark = args.contains("dark")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("postclip-snap-\(UUID().uuidString)")
        let store = ClipboardStore(baseDir: dir)
        let samples: [(String, String)] = [
            ("https://developer.apple.com/documentation/appkit/nspasteboard", "com.apple.Safari"),
            ("func paste(_ item: ClipItem) {\n    PasteService.write(item)\n    PasteService.postCommandV()\n}", "com.apple.dt.Xcode"),
            ("Rendez-vous demain à 14h au studio pour la répétition générale du spectacle.", "com.apple.Notes"),
            ("Bonjour !", "com.apple.Terminal"),
        ]
        for (t, app) in samples.reversed() {
            store.insert(ClipItem(kind: .text, text: t, signature: "t:" + t, date: Date().addingTimeInterval(-Double.random(in: 30...4000)), sourceBundleID: app))
        }
        if args.count > i + 2, let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 2])) {
            let id = UUID()
            if let size = store.writeImage(data: data, id: id) {
                store.insert(ClipItem(id: id, kind: .image, imageWidth: size.width, imageHeight: size.height, signature: "i", date: Date(), sourceBundleID: "com.apple.Preview"))
            }
        }
        store.togglePin(store.items.last!.id)
        let model = PanelModel(store: store)
        model.selectFirst()
        let view = HistoryView(store: store, model: model, actions: PanelActions(paste: { _, _ in }, remove: { _ in }, togglePin: { _ in }, clearAll: {}))
            .background(dark ? Color(white: 0.17) : Color(white: 0.95))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: PanelController.size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        }
        exit(0)
    }
}
