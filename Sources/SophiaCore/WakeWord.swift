import Foundation

public enum WakeWord {
    static let name = #"(?:sophia|sophia|sofie|sofiya|sophie|safia|sofi|sophea|zofia|so\s?fear|so\s?fia)"#
    private static let full = try! NSRegularExpression(
        pattern: #"\b(?:hey|hay|hei|hai|hi|hello|okay|ok|yo)[\s,.!-]*"# + name + #"\b"#, options: .caseInsensitive)
    private static let casual = try! NSRegularExpression(pattern: #"\b"# + name + #"\b[\s,.!?;:-]+(?=\w)"#, options: .caseInsensitive)
    private static let leadingName = try! NSRegularExpression(pattern: #"^\W*"# + name + #"\b[\s,.!?;:-]*"#, options: .caseInsensitive)

    private static let entrance = try! NSRegularExpression(
        pattern: #"\b(?:wake\s*up[\s,.!]*(?:daddy|daddies|dad)(?:'?s|\s+is)?(?:\s+home)?|(?:daddy|daddies|dad)(?:'?s|\s+is)\s+home)\b"#, options: .caseInsensitive)
    public static func matchesEntrance(_ text: String) -> Bool {
        entrance.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    public static func matches(_ text: String, casual: Bool = false) -> Bool { match(text, casual: casual) != nil }

    private static func match(_ text: String, casual: Bool) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..., in: text)
        if let m = full.firstMatch(in: text, range: range) { return m }
        return casual ? self.casual.firstMatch(in: text, range: range) : nil
    }

    public static func remainder(_ text: String, casual: Bool = false) -> String {
        guard let m = match(text, casual: casual), let r = Range(m.range, in: text) else { return "" }
        return String(text[r.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    public static func stripLeading(_ text: String) -> String {
        let all = NSRange(text.startIndex..., in: text)
        let m = full.firstMatch(in: text, range: all) ?? leadingName.firstMatch(in: text, range: all)
        guard let m, let r = Range(m.range, in: text) else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rest = String(String(text[r.upperBound...]).drop(while: { $0.isWhitespace || ",.!?;:-".contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = rest.first else { return "" }
        return first.uppercased() + rest.dropFirst()
    }
}
