import AppKit
import ApplicationServices

enum PasteService {
    /// Marque nos propres ⌘V synthétiques pour que le tap les laisse passer.
    static let marker: Int64 = 0x434C_4950 // "CLIP"

    static func write(_ item: ClipItem, store: ClipboardStore, plainText: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            guard let data = try? Data(contentsOf: store.imageURL(for: item.id)) else { return }
            pb.setData(data, forType: .png)
            if let tiff = NSBitmapImageRep(data: data)?.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        case .files:
            let paths = item.filePaths ?? []
            if plainText {
                pb.setString(paths.joined(separator: "\n"), forType: .string)
            } else {
                pb.writeObjects(paths.map { URL(fileURLWithPath: $0) as NSURL })
            }
        }
    }

    static func postCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: down) else { continue }
            e.flags = .maskCommand
            e.setIntegerValueField(.eventSourceUserData, value: marker)
            e.post(tap: .cgSessionEventTap)
        }
    }
}

/// Trouve la position du curseur texte (caret) via l'API d'accessibilité, sinon la souris.
enum CaretLocator {
    /// Rect en coordonnées Cocoa (origine en bas à gauche).
    static func caretRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.08)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.origin != .zero, rect.height > 0, rect.height < 200 else { return nil }

        // AX : origine en haut à gauche de l'écran principal → Cocoa : bas à gauche
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: max(rect.width, 1), height: rect.height)
    }
}
