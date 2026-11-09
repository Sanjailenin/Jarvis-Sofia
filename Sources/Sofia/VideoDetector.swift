import AppKit
import ApplicationServices

@MainActor
enum VideoDetector {
    static let players: Set<String> = ["com.apple.TV", "com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.colliderli.iina", "io.mpv", "com.firecore.infuse",
                                       "com.eltima.elmedia6", "com.plexapp.plex", "com.netflix.Netflix", "tv.plex.player.desktop", "com.apple.Music"]
    static func isVideoInFront() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return false }
        if players.contains(id) { return true }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &w) == .success, let win = w else { return false }
        var full: CFTypeRef?
        if AXUIElementCopyAttributeValue(win as! AXUIElement, "AXFullScreen" as CFString, &full) == .success, let b = full as? Bool { return b }
        return false
    }
}
