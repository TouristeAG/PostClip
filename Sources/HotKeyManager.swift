import AppKit
import ApplicationServices

enum ShortcutMode: String {
    case commandV        // ⌘V ouvre le panneau (comme demandé)
    case shiftCommandV   // ⇧⌘V ouvre le panneau, ⌘V reste normal

    static var current: ShortcutMode {
        get { ShortcutMode(rawValue: UserDefaults.standard.string(forKey: "shortcut") ?? "") ?? .commandV }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "shortcut") }
    }

    var label: String { self == .commandV ? "⌘V" : "⇧⌘V" }
}

/// Intercepte ⌘V au niveau système grâce à un CGEventTap (nécessite l'autorisation Accessibilité).
final class HotKeyManager {
    var onTrigger: (() -> Void)?
    /// Retourne false pour laisser passer le ⌘V natif (ex. mot de passe non capturé).
    var shouldIntercept: (() -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventKeycode) == 9, // touche V (même position en AZERTY)
              event.getIntegerValueField(.eventSourceUserData) != PasteService.marker
        else { return Unmanaged.passUnretained(event) }

        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let wanted: CGEventFlags = ShortcutMode.current == .commandV ? [.maskCommand] : [.maskCommand, .maskShift]
        guard event.flags.intersection(relevant) == wanted else { return Unmanaged.passUnretained(event) }
        guard shouldIntercept?() ?? true else { return Unmanaged.passUnretained(event) }

        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
        }
        return nil // on avale l'événement
    }
}

private func hotKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                               refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
