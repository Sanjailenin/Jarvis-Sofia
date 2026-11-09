import Foundation

final class MemoryStore {
    static let shared = MemoryStore()
    private let url: URL
    private(set) var facts: [String]

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sophia")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("memory.json")
        facts = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? []
    }

    func remember(_ fact: String) {
        let f = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !facts.contains(where: { $0.lowercased() == f.lowercased() }) else { return }
        facts.append(String(f.prefix(300)))
        if facts.count > 200 { facts.removeFirst(facts.count - 200) }
        save()
    }

    func forget(matching words: String) -> Int {
        let needles = words.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !needles.isEmpty else { return 0 }
        let before = facts.count
        facts.removeAll { f in needles.allSatisfy { f.lowercased().contains($0) } }
        if facts.count != before { save() }
        return before - facts.count
    }

    private func save() { try? JSONEncoder().encode(facts).write(to: url, options: .atomic) }
}
