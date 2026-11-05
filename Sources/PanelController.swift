import AppKit
import SwiftUI

/// Panneau flottant qui ne vole pas le focus à l'app active (comme Spotlight).
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PanelModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tout", text = "Texte", images = "Images", files = "Fichiers"
        var id: String { rawValue }
    }

    @Published var query = "" { didSet { selectFirst() } }
    @Published var filter: Filter = .all { didSet { selectFirst() } }
    @Published var selectedID: UUID?
    @Published var focusToken = 0

    let store: ClipboardStore
    init(store: ClipboardStore) { self.store = store }

    var visible: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = store.items.filter { item in
            switch filter {
            case .all: break
            case .text: if item.kind != .text { return false }
            case .images: if item.kind != .image { return false }
            case .files: if item.kind != .files { return false }
            }
            return item.matches(q)
        }
        return filtered.filter(\.pinned) + filtered.filter { !$0.pinned }
    }

    var selectedItem: ClipItem? {
        let list = visible
        return list.first { $0.id == selectedID } ?? list.first
    }

    func selectFirst() { selectedID = visible.first?.id }

    func move(_ delta: Int) {
        let list = visible
        guard !list.isEmpty else { return }
        let idx = list.firstIndex { $0.id == selectedID } ?? -1
        let next = (idx + delta + list.count) % list.count
        selectedID = list[next].id
    }

    func reset() {
        query = ""
        filter = .all
        selectFirst()
    }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 380, height: 470)

    let store: ClipboardStore
    let model: PanelModel
    private let panel: FloatingPanel
    private var keyMonitor: Any?

    var onPaste: ((ClipItem, Bool) -> Void)?

    init(store: ClipboardStore) {
        self.store = store
        model = PanelModel(store: store)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                          styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                          backing: .buffered, defer: true)
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovable = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]

        let actions = PanelActions(
            paste: { [weak self] item, plain in self?.onPaste?(item, plain) },
            remove: { [weak store] item in store?.remove(item.id) },
            togglePin: { [weak store] item in store?.togglePin(item.id) },
            clearAll: { [weak store] in store?.clearUnpinned() }
        )
        let host = NSHostingView(rootView: HistoryView(store: store, model: model, actions: actions))
        host.sizingOptions = [] // la taille du panneau reste fixe, quel que soit le nombre d'éléments
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        model.reset()
        panel.setFrameOrigin(origin())
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
        installKeyMonitor()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func cycle() { model.move(1) }

    func windowDidResignKey(_ notification: Notification) { hide() }

    // MARK: Position : sous le curseur texte, sinon près de la souris

    private func origin() -> NSPoint {
        let size = Self.size
        var point: NSPoint
        if let caret = CaretLocator.caretRect() {
            point = NSPoint(x: caret.minX - 16, y: caret.minY - size.height - 6)
            // Pas de place en dessous → au-dessus du caret
            if let screen = screen(containing: caret.origin), point.y < screen.visibleFrame.minY {
                point.y = caret.maxY + 6
            }
        } else {
            let mouse = NSEvent.mouseLocation
            point = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 12)
            if let screen = screen(containing: mouse), point.y < screen.visibleFrame.minY {
                point.y = mouse.y + 12
            }
        }
        let anchor = NSPoint(x: point.x + size.width / 2, y: point.y + size.height / 2)
        guard let vf = (screen(containing: anchor) ?? NSScreen.main)?.visibleFrame else { return point }
        point.x = min(max(point.x, vf.minX + 8), vf.maxX - size.width - 8)
        point.y = min(max(point.y, vf.minY + 8), vf.maxY - size.height - 8)
        return point
    }

    private func screen(containing p: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    // MARK: Clavier

    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1…9 (QWERTY & AZERTY)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        switch e.keyCode {
        case 125: model.move(1); return true                 // ↓
        case 126: model.move(-1); return true                // ↑
        case 36, 76:                                         // ↩
            if let item = model.selectedItem { onPaste?(item, flags.contains(.shift)) }
            return true
        case 53:                                             // esc
            if model.query.isEmpty { hide() } else { model.query = "" }
            return true
        case 51 where cmd:                                   // ⌘⌫
            if let item = model.selectedItem {
                model.move(1)
                store.remove(item.id)
                if model.selectedID == item.id { model.selectFirst() }
            }
            return true
        case 35 where cmd:                                   // ⌘P
            if let item = model.selectedItem { store.togglePin(item.id) }
            return true
        case 48:                                             // ⇥ : filtre suivant
            let all = PanelModel.Filter.allCases
            let i = all.firstIndex(of: model.filter) ?? 0
            model.filter = all[(i + (flags.contains(.shift) ? all.count - 1 : 1)) % all.count]
            return true
        default:
            if cmd, let n = Self.digitKeyCodes.firstIndex(of: e.keyCode) {
                let list = model.visible
                if n < list.count { onPaste?(list[n], flags.contains(.shift)) }
                return true
            }
            return false
        }
    }
}
