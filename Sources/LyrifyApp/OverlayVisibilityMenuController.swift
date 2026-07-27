import AppKit

/// The status item's "Show Overlay" toggle: a single checkable item that
/// flips `OverlayVisibilityPreference` and takes effect immediately, so the
/// listener can turn the Overlay off without quitting Lyrify.
///
/// Deliberately untested — thin AppKit wiring verified by hand; the
/// preference it flips has no decision of its own to get wrong.
@MainActor
final class OverlayVisibilityMenuController: NSObject {
    let menuItem: NSMenuItem

    private let preference: OverlayVisibilityPreference
    private let onChange: () -> Void

    init(preference: OverlayVisibilityPreference, onChange: @escaping () -> Void) {
        self.preference = preference
        self.onChange = onChange
        self.menuItem = NSMenuItem(title: "Show Overlay", action: nil, keyEquivalent: "")

        super.init()

        menuItem.target = self
        menuItem.action = #selector(toggle)
        menuItem.state = preference.isVisible ? .on : .off
    }

    @objc private func toggle() {
        let isVisible = !preference.isVisible
        preference.isVisible = isVisible
        menuItem.state = isVisible ? .on : .off
        onChange()
    }
}
