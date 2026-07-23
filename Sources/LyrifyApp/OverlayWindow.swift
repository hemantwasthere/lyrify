import AppKit

/// The Overlay's window: a titled, closable, resizable panel with no
/// visible native title-bar strip. See ADR-0012 — reopens ADR-0006's
/// "never takes keyboard focus" guarantee, since only a key-able window
/// gets native traffic-light rendering and native resize behavior for
/// free. `titlebarAppearsTransparent`/`titleVisibility`/
/// `.fullSizeContentView` keep it looking exactly as borderless as the
/// non-activating panel it replaces; only a close button is exposed —
/// both the miniaturize and zoom buttons are hidden explicitly in `init`,
/// not merely by omitting their style-mask flags (verified by hand:
/// omitting `.miniaturizable` alone still left a disabled placeholder
/// circle in its spot). Lyrify has neither a minimize nor a zoom concept.
/// `minSize`/`maxSize` are the caller's responsibility to set
/// (see `OverlayController`), the same way the retired resizable card
/// left them to its own controller rather than baking bounds in here.
///
/// Dragging is handled by the content view (`DraggableBackgroundView`), not
/// by `isMovableByWindowBackground` — that flag can't tell a click from the
/// start of a drag.
///
/// Deliberately untested — built and verified by hand.
final class OverlayWindow: NSPanel {
    /// Fired from `windowShouldClose(_:)` whenever the real close button
    /// (or any other path that ultimately calls `close()`/`performClose(_:)`,
    /// such as a future Cmd-W) tries to close the window — never itself
    /// closes anything; the caller decides what "close" actually means.
    var onCloseRequested: (() -> Void)?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentView.frame.size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Without this, the content view is asked to redraw at every
        // intermediate size of a live resize drag — visibly flickery/laggy
        // next to Spotify's own Mini Player (ADR-0009 names it as this
        // resizable card's own reference). This tells AppKit to scale the
        // existing backing store between frames instead, redrawing only
        // once the drag settles.
        preservesContentDuringLiveResize = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // Omitting `.miniaturizable` from the style mask turned out not to
        // be enough on its own — verified by hand, this macOS version
        // still renders a disabled placeholder circle in the miniaturize
        // button's spot regardless, for the traffic-light group's own
        // visual grouping. Hidden directly, the same way the zoom button
        // (genuinely tied to `.resizable`, which this window needs, so it
        // has no style-mask flag to omit either) already has to be.
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        // .floating, not .statusBar: the latter is the same level the real
        // system status-bar menus use, which makes macOS treat any window
        // there as "a menu is open" and dim every other status item for as
        // long as it's on screen. .floating still sits above regular
        // windows and, paired with .fullScreenAuxiliary below, still joins
        // a fullscreen app's Space — without that system-wide side effect.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = false

        self.contentView = contentView
        delegate = self
    }
}

extension OverlayWindow: NSWindowDelegate {
    /// The one choke point every close path funnels through — a direct
    /// override of the close button's own target/action would only catch
    /// clicks on that specific button, not any other route to `close()`.
    /// Always answers `false`: closing the Overlay's window would
    /// deallocate it, which nothing here wants; `onCloseRequested` is
    /// where the real "hide, don't quit" behavior lives instead.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCloseRequested?()
        return false
    }
}
