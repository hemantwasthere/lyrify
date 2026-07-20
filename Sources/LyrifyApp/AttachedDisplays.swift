import AppKit
import LyrifyCore

/// One display Lyrify can see right now: its stable id and a human-readable
/// name for the status item's Display submenu.
struct AttachedDisplay {
    let id: UInt32
    let name: String
    let screen: NSScreen
}

/// Deliberately untested — thin AppKit wiring verified by hand; the one real
/// decision it makes (`chosen(for:)`'s fallback) just forwards to
/// `DisplaySelection`, the tested core seam, after gathering live geometry
/// that only AppKit can supply.
enum AttachedDisplays {
    /// Every display currently attached, in the order AppKit reports them.
    /// A screen AppKit cannot give a stable id for (never observed in
    /// practice) is left out rather than guessed at.
    static func current() -> [AttachedDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.lyrifyDisplayID else { return nil }
            return AttachedDisplay(id: id, name: screen.localizedName, screen: screen)
        }
    }

    /// The display `DisplaySelection` resolves to right now, given
    /// `preference` — the single source both the Overlay and the status
    /// item's Display submenu read, so they can never disagree about which
    /// display is in use. Nil only when AppKit reports no main display at
    /// all (every screen vanished).
    static func chosen(for preference: DisplayPreference) -> AttachedDisplay? {
        let attached = current()
        guard let mainID = NSScreen.main?.lyrifyDisplayID,
              let mainDisplay = attached.first(where: { $0.id == mainID })
        else { return attached.first }

        let chosenID = DisplaySelection.resolve(
            remembered: preference.remembered,
            attached: attached.map(\.id),
            mainDisplay: mainID
        )
        return attached.first(where: { $0.id == chosenID }) ?? mainDisplay
    }
}

extension NSScreen {
    /// The stable identifier `DisplaySelection` and `DisplayPreference`
    /// persist and compare — the CGDirectDisplayID AppKit reports under this
    /// device-description key.
    var lyrifyDisplayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// This display's Placement, from the geometry AppKit already resolves
    /// for notch-safe UI: the auxiliary areas are nil on a display with no
    /// notch, and their presence together with a positive top safe-area
    /// inset is what `Placement.resolve` treats as "has a notch." See
    /// ADR-0004.
    var lyrifyPlacement: Placement {
        guard let leftMargin = auxiliaryTopLeftArea, let rightMargin = auxiliaryTopRightArea else {
            return .pill
        }
        return Placement.resolve(
            topSafeAreaInset: safeAreaInsets.top,
            leftMargin: leftMargin,
            rightMargin: rightMargin
        )
    }
}
