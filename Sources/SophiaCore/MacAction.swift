import Foundation

public struct MacAction: Equatable {
    public enum Kind: String, CaseIterable {
        case openApp = "open_app", quitApp = "quit_app", switchApp = "switch_app", openURL = "open_url", openPath = "open_path"
        case setVolume = "set_volume", mute, unmute, darkMode = "dark_mode", media, wifi, lockScreen = "lock_screen", screenshot
        case typeText = "type_text"
        case webSearch = "web_search", findFile = "find_file", playMusic = "play_music", openSettings = "open_settings"
        case clipboardCopy = "clipboard_copy", newNote = "new_note"
        case openDeeplink = "open_deeplink"      // an app link (spotify:, slack://…) from the fixed scheme list
        case moveWindow = "move_window"
        case setPreference = "set_preference"
        case focus, hideApp = "hide_app", unhideApp = "unhide_app"
    }

    public static let searchURLs: [String: String] = [
        "google": "https://www.google.com/search?q=", "youtube": "https://www.youtube.com/results?search_query=",
        "maps": "https://www.google.com/maps/search/", "wikipedia": "https://en.wikipedia.org/w/index.php?search=",
        "images": "https://www.google.com/search?tbm=isch&q=", "news": "https://news.google.com/search?q=",
        "scholar": "https://scholar.google.com/scholar?q=",
    ]
    public static let deeplinkSchemes: Set<String> = ["spotify", "slack", "notion", "obsidian", "things", "bear", "todoist", "zoommtg", "msteams", "mailto"]
    public static let settingsPages: [String: String] = [
        "wifi": "com.apple.wifi-settings-extension", "bluetooth": "com.apple.BluetoothSettings", "sound": "com.apple.Sound-Settings.extension",
        "display": "com.apple.Displays-Settings.extension", "battery": "com.apple.Battery-Settings.extension",
        "notifications": "com.apple.Notifications-Settings.extension", "focus": "com.apple.Focus-Settings.extension",
        "privacy": "com.apple.settings.PrivacySecurity.extension", "keyboard": "com.apple.Keyboard-Settings.extension",
        "network": "com.apple.Network-Settings.extension", "general": "com.apple.systempreferences.GeneralSettings",
        "appearance": "com.apple.Appearance-Settings.extension", "wallpaper": "com.apple.Wallpaper-Settings.extension",
    ]

    public static func searchURL(_ query: String, site: String) -> URL? {
        guard let base = searchURLs[site] else { return nil }
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "&+=?#/")
        guard let q = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: base + q)
    }
    public let kind: Kind
    public let target: String
    public let value: String

    public static let scriptyExtensions: Set<String> = ["app", "command", "sh", "bash", "zsh", "tool", "pkg", "mpkg", "dmg", "scpt", "applescript", "workflow", "terminal", "py", "rb", "pl", "jar", "exe"]

    public init?(_ raw: [String: Any]) {
        guard let k = Kind(rawValue: raw["action"] as? String ?? "") else { return nil }
        let target = (raw["target"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (raw["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch k {
        case .openApp, .quitApp, .switchApp:
            guard target.range(of: #"^[\p{L}\p{N} .&+'’()-]{1,60}$"#, options: .regularExpression) != nil else { return nil }
        case .openURL:
            guard let u = URL(string: target), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { return nil }
        case .openDeeplink:
            guard target.count <= 500, let u = URL(string: target), let scheme = u.scheme?.lowercased(), Self.deeplinkSchemes.contains(scheme) else { return nil }
        case .openPath:
            guard (target.hasPrefix("~") || target.hasPrefix("/")), target.count <= 400, !target.contains(".."),
                  !Self.scriptyExtensions.contains((target as NSString).pathExtension.lowercased()) else { return nil }
        case .setVolume:
            guard value == "up" || value == "down" || (Int(value).map { (0...100).contains($0) } ?? false) else { return nil }
        case .darkMode:
            guard ["on", "off", "toggle"].contains(value) else { return nil }
        case .media:
            guard ["play_pause", "next", "previous"].contains(value) else { return nil }
        case .wifi:
            guard ["on", "off"].contains(value) else { return nil }
        case .typeText:
            guard !target.isEmpty, target.count <= 500 else { return nil }
        case .webSearch:
            guard !target.isEmpty, target.count <= 200, Self.searchURLs[value.isEmpty ? "google" : value] != nil else { return nil }
            self.kind = k; self.target = target; self.value = value.isEmpty ? "google" : value; return
        case .findFile:
            guard !target.isEmpty, target.count <= 100, target.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\*?")) == nil else { return nil }
        case .playMusic:
            guard !target.isEmpty, target.count <= 120 else { return nil }
        case .openSettings:
            guard Self.settingsPages[target.lowercased()] != nil else { return nil }
            self.kind = k; self.target = target.lowercased(); self.value = value; return
        case .clipboardCopy, .newNote:
            guard !target.isEmpty, target.count <= 2000 else { return nil }
        case .mute, .unmute, .lockScreen, .screenshot:
            break
        case .moveWindow:
            guard target.lowercased() == "front" || target.range(of: #"^[\p{L}\p{N} .&+'’()-]{1,60}$"#, options: .regularExpression) != nil, WindowGeometry.placements.contains(value) else { return nil }
        case .setPreference:
            guard let p = Preference(rawValue: target.lowercased()), let v = p.normalize(raw["value"] as? String ?? "") else { return nil }
            self.kind = k; self.target = p.rawValue; self.value = v; return
        case .focus:
            guard ["on", "off"].contains(value) else { return nil }
        case .hideApp, .unhideApp:
            guard target.range(of: #"^[\p{L}\p{N} .&+'’()-]{1,60}$"#, options: .regularExpression) != nil else { return nil }
        }
        self.kind = k; self.target = target; self.value = value
    }

    public static func list(from raw: Any?) -> (actions: [MacAction], rejected: Int) {
        let items = raw as? [[String: Any]] ?? []
        let ok = items.compactMap(MacAction.init)
        return (Array(ok.prefix(8)), items.count - min(ok.count, 8))
    }

    public static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }

    public var summary: String {
        switch kind {
        case .openApp: return "open \(target)"
        case .quitApp: return "quit \(target)"
        case .switchApp: return "switch to \(target)"
        case .openURL: return "open \(URL(string: target)?.host ?? target)"
        case .openPath: return "open \((target as NSString).lastPathComponent)"
        case .setVolume: return value == "up" ? "volume up" : value == "down" ? "volume down" : "volume \(value)"
        case .mute: return "mute"
        case .unmute: return "unmute"
        case .darkMode: return "dark mode \(value)"
        case .media: return value.replacingOccurrences(of: "_", with: "/")
        case .wifi: return "Wi-Fi \(value)"
        case .lockScreen: return "lock the screen"
        case .screenshot: return "screenshot"
        case .typeText: return "type text"
        case .webSearch: return "search \(value) for \(target)"
        case .findFile: return "find \(target)"
        case .playMusic: return "play \(target)"
        case .openSettings: return "open \(target) settings"
        case .clipboardCopy: return "copy to clipboard"
        case .moveWindow: return "move \(target) \(value.replacingOccurrences(of: "_", with: " "))"
        case .setPreference: return "set \(Preference(rawValue: target)?.spokenName ?? target) to \(value)"
        case .focus: return "focus \(value)"
        case .hideApp: return "hide \(target)"
        case .unhideApp: return "show \(target)"
        case .newNote: return "make a note"
        case .openDeeplink: return "open \(URL(string: target)?.scheme ?? "app") link"
        }
    }
}
