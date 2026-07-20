import AppKit

/// Builds and maintains the status item's Display submenu: one item per
/// attached display, a checkmark on whichever one is actually carrying the
/// Overlay right now, and a persisted choice that takes effect immediately.
///
/// Deliberately untested — thin AppKit wiring verified by hand; the fallback
/// decision it displays comes from tested core types.
@MainActor
final class DisplayMenuController: NSObject, NSMenuDelegate {
    let menuItem: NSMenuItem

    private let displayPreference: DisplayPreference
    private let onChange: () -> Void

    init(displayPreference: DisplayPreference, onChange: @escaping () -> Void) {
        self.displayPreference = displayPreference
        self.onChange = onChange
        self.menuItem = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")

        super.init()

        let submenu = NSMenu()
        submenu.delegate = self
        menuItem.submenu = submenu
    }

    /// Rebuilt every time the submenu is about to open, so a hot-plugged or
    /// unplugged display is never stale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let attached = AttachedDisplays.current()
        let chosenID = AttachedDisplays.chosen(for: displayPreference)?.id

        for display in attached {
            let item = NSMenuItem(
                title: display.name,
                action: #selector(selectDisplay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = display.id
            item.state = display.id == chosenID ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func selectDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UInt32 else { return }
        displayPreference.remembered = id
        onChange()
    }
}
