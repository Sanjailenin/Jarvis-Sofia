import Foundation
import SophiaCore

@MainActor
final class OwnerTurn {
    struct Result { var reply: String; var performed: [String]; var failed: [String] }
    private var history: [String: [ChatMessage]] = [:]
    private let memory: MemoryStore

    init(memory: MemoryStore = .shared) { self.memory = memory }

    func clear(_ channel: String) { history[channel] = nil }

    func run(_ text: String, channel: String, provider: ModelProvider, ownerName: String) async throws -> Result {
        var messages = history[channel] ?? []
        messages.append(.user(text))
        var performed: [String] = [], failed: [String] = []
        var reply = ""
        for _ in 0..<6 {
            let all = [ChatMessage.system(Prompt.system(ownerName: ownerName, facts: memory.facts, channel: channel))] + messages.suffix(24)
            let out = try await provider.chat(all, tools: Prompt.tools)
            messages.append(.assistant(out.text, calls: out.calls))
            if out.calls.isEmpty { reply = out.text; break }
            for call in out.calls {
                let result = await handle(call, performed: &performed, failed: &failed)
                messages.append(.tool(call.id, result))
            }
            reply = out.text
        }
        history[channel] = Array(messages.suffix(30))
        if reply.isEmpty { reply = performed.isEmpty ? "Done." : "Done: \(performed.joined(separator: ", "))." }
        return Result(reply: reply, performed: performed, failed: failed)
    }

    private func handle(_ call: ToolCall, performed: inout [String], failed: inout [String]) async -> String {
        switch call.name {
        case "mac_control":
            guard let action = MacAction(call.input) else { return "Refused: not a valid Mac action." }
            let (f, notes) = await MacRunner.perform([action])
            if let e = f.first { failed.append(e); return "Failed: \(e)" }
            performed.append(action.summary)
            return notes.first ?? "Done: \(action.summary)."
        case "remember_fact":
            let fact = call.input["fact"] as? String ?? ""
            memory.remember(fact)
            return fact.isEmpty ? "Nothing to remember." : "Remembered."
        case "forget_fact":
            let n = memory.forget(matching: call.input["words"] as? String ?? "")
            return n == 0 ? "Nothing matched." : "Forgot \(n)."
        default:
            return "Unknown tool."
        }
    }
}
