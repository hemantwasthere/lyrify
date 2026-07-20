import AppKit
import LyrifyCore

/// Owns every window the Overlay might need — the pill and the notch's two
/// wings — and shows exactly the set its resolved Placement calls for. The
/// chosen display comes from `DisplaySelection`, resolved fresh on every
/// call so a screen change or a menu selection takes effect on the very
/// next render with no separate invalidation step. See ADR-0004.
///
/// Deliberately untested — thin AppKit wiring verified by hand; every
/// decision it acts on comes from tested core types.
@MainActor
final class OverlayPresenter {
    private let displayPreference: DisplayPreference

    private let pillView = OverlayView()
    private let leftWingView = OverlayWingView(side: .left)
    private let rightWingView = OverlayWingView(side: .right)

    private let pillWindow: OverlayWindow
    private let leftWingWindow: OverlayWindow
    private let rightWingWindow: OverlayWindow

    /// "Near the top edge," not flush with it — clear of the system menu
    /// bar's own items.
    private static let pillTopInset: CGFloat = 8

    init(displayPreference: DisplayPreference) {
        self.displayPreference = displayPreference
        self.pillWindow = OverlayWindow(contentView: pillView)
        self.leftWingWindow = OverlayWindow(contentView: leftWingView)
        self.rightWingWindow = OverlayWindow(contentView: rightWingView)
    }

    /// Shows `content` in whichever form the chosen display's Placement
    /// calls for, hiding the other form's windows. `.hidden`, or no chosen
    /// display at all (every screen vanished), hides everything.
    func show(_ content: OverlayDisplay.Content) {
        guard content != .hidden, let screen = chosenScreen() else {
            hide()
            return
        }

        switch screen.lyrifyPlacement {
        case .pill:
            leftWingWindow.orderOut(nil)
            rightWingWindow.orderOut(nil)

            paintPill(content)
            pillWindow.setFrame(pillFrame(on: screen), display: true)
            pillWindow.orderFrontRegardless()

        case .notch(let leftMargin, let rightMargin):
            pillWindow.orderOut(nil)

            paintWings(content)
            leftWingWindow.setFrame(leftMargin, display: true)
            rightWingWindow.setFrame(rightMargin, display: true)
            leftWingWindow.orderFrontRegardless()
            rightWingWindow.orderFrontRegardless()
        }
    }

    func hide() {
        pillWindow.orderOut(nil)
        leftWingWindow.orderOut(nil)
        rightWingWindow.orderOut(nil)
    }

    /// `.hidden` never reaches here — `show(_:)` returns before either paint
    /// method is called.
    private func paintPill(_ content: OverlayDisplay.Content) {
        switch content {
        case .hidden: return
        case .idle(let trackName):
            pillView.updateIdle(trackName: trackName)
        case .lines(let lineContent):
            pillView.update(with: lineContent)
        }
    }

    private func paintWings(_ content: OverlayDisplay.Content) {
        switch content {
        case .hidden: return
        case .idle(let trackName):
            leftWingView.update(text: trackName, alpha: OverlayView.idleAlpha)
            rightWingView.update(text: "", alpha: 1.0) // empty text; alpha is moot
        case .lines(let lineContent):
            let text = OverlayText(lineContent)
            leftWingView.update(text: text.activeText, alpha: text.activeAlpha)
            rightWingView.update(text: text.nextText, alpha: text.nextAlpha)
        }
    }

    private func chosenScreen() -> NSScreen? {
        AttachedDisplays.chosen(for: displayPreference)?.screen
    }

    private func pillFrame(on screen: NSScreen) -> NSRect {
        let size = OverlayView.size
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - Self.pillTopInset
        )
        return NSRect(origin: origin, size: size)
    }
}
