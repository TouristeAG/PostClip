import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ClipboardStore()
    private var monitor: ClipboardMonitor!
    private var panel: PanelController!
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = ClipboardMonitor(store: store)
        monitor.start()

        panel = PanelController(store: store)
        panel.onPaste = { [weak self] item, plain in self?.paste(item, plainText: plain) }

        hotKey.onTrigger = { [weak self] in self?.togglePanel() }
        hotKey.shouldIntercept = { [weak self] in
            guard let self else { return false }
            if self.panel.isVisible { return true }
            self.monitor.poll()
            // Mot de passe (contenu masqué) : on laisse le ⌘V natif coller normalement.
            return !self.monitor.currentIsUncaptured
        }

        setupStatusItem()
        startHotKey()
    }

    // MARK: Raccourci & autorisation

    private func startHotKey() {
        if hotKey.start() { return }
        showAccessibilityOnboarding()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            if self.hotKey.start() {
                t.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    private func showAccessibilityOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "PostClip a besoin de l'accès Accessibilité"
        alert.informativeText = """
        Pour ouvrir l'historique avec \(ShortcutMode.current.label) et coller l'élément choisi, \
        autorisez PostClip dans Réglages Système → Confidentialité et sécurité → Accessibilité.

        Le raccourci s'activera automatiquement dès que l'accès est accordé.
        """
        alert.addButton(withTitle: "Ouvrir les Réglages")
        alert.addButton(withTitle: "Plus tard")
        if alert.runModal() == .alertFirstButtonReturn {
            Accessibility.prompt()
            Accessibility.openSettings()
        }
    }

    // MARK: Panneau

    private func togglePanel() {
        if panel.isVisible { panel.cycle() } else { panel.show() }
    }

    private func paste(_ item: ClipItem, plainText: Bool) {
        panel.hide()
        let alreadyThere = !plainText && monitor.isUnchanged(signature: item.signature)
        if !alreadyThere {
            // On réécrit le presse-papiers (sinon on garde l'original, avec sa mise en forme riche).
            PasteService.write(item, store: store, plainText: plainText)
            monitor.adoptCurrentChange(signature: plainText ? nil : item.signature)
        }
        store.touch(item.id)
        guard Accessibility.isTrusted else { return } // au moins copié dans le presse-papiers
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { PasteService.postCommandV() }
    }

    // MARK: Barre des menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "PostClip")
                ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "PostClip")
            img?.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Afficher l'historique", #selector(showFromMenu)))
        menu.addItem(.separator())

        let shortcutHeader = NSMenuItem(title: "Raccourci", action: nil, keyEquivalent: "")
        shortcutHeader.isEnabled = false
        menu.addItem(shortcutHeader)
        let cmdV = item("⌘V  — remplace le collage classique", #selector(useCmdV))
        cmdV.state = ShortcutMode.current == .commandV ? .on : .off
        cmdV.indentationLevel = 1
        menu.addItem(cmdV)
        let shiftCmdV = item("⇧⌘V  — garde ⌘V normal", #selector(useShiftCmdV))
        shiftCmdV.state = ShortcutMode.current == .shiftCommandV ? .on : .off
        shiftCmdV.indentationLevel = 1
        menu.addItem(shiftCmdV)
        menu.addItem(.separator())

        let login = item("Ouvrir au démarrage", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !hotKey.isRunning {
            let perm = item("⚠︎ Autoriser l'accès Accessibilité…", #selector(openAccessibility))
            menu.addItem(perm)
        }

        menu.addItem(item("Effacer l'historique", #selector(clearHistory)))
        menu.addItem(.separator())
        menu.addItem(item("Quitter PostClip", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func showFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.panel.show() }
    }

    @objc private func useCmdV() { ShortcutMode.current = .commandV }
    @objc private func useShiftCmdV() { ShortcutMode.current = .shiftCommandV }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier l'ouverture au démarrage"
            alert.informativeText = "Placez PostClip dans le dossier Applications puis réessayez.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        Accessibility.prompt()
        Accessibility.openSettings()
    }

    @objc private func clearHistory() { store.clearUnpinned() }
    @objc private func quit() { NSApp.terminate(nil) }
}
