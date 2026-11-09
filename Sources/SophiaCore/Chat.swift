import Foundation

public struct ToolCall: Equatable {
    public var id: String
    public var name: String
    public var arguments: String
    public init(id: String, name: String, arguments: String) { self.id = id; self.name = name; self.arguments = arguments }
    public var input: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:] }
}

public struct ToolSpec {
    public var name: String
    public var description: String
    public var parameters: [String: Any]
    public init(name: String, description: String, parameters: [String: Any]) { self.name = name; self.description = description; self.parameters = parameters }
}

public struct ChatMessage: Equatable {
    public enum Role: String { case system, user, assistant, tool }
    public var role: Role
    public var content: String
    public var toolCalls: [ToolCall]
    public var toolCallID: String?
    public init(role: Role, content: String, toolCalls: [ToolCall] = [], toolCallID: String? = nil) {
        self.role = role; self.content = content; self.toolCalls = toolCalls; self.toolCallID = toolCallID
    }
    public static func system(_ s: String) -> ChatMessage { .init(role: .system, content: s) }
    public static func user(_ s: String) -> ChatMessage { .init(role: .user, content: s) }
    public static func assistant(_ s: String, calls: [ToolCall] = []) -> ChatMessage { .init(role: .assistant, content: s, toolCalls: calls) }
    public static func tool(_ id: String, _ s: String) -> ChatMessage { .init(role: .tool, content: s, toolCallID: id) }
}

public struct ChatReply: Equatable {
    public var text: String
    public var calls: [ToolCall]
    public init(text: String, calls: [ToolCall] = []) { self.text = text; self.calls = calls }
}

public enum OpenAIWire {
    public static func body(model: String, messages: [ChatMessage], tools: [ToolSpec], temperature: Double = 0.4) -> [String: Any] {
        var out: [String: Any] = ["model": model, "temperature": temperature, "messages": messages.map(encode)]
        if !tools.isEmpty {
            out["tools"] = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
        }
        return out
    }
    static func encode(_ m: ChatMessage) -> [String: Any] {
        var o: [String: Any] = ["role": m.role.rawValue, "content": m.content]
        if !m.toolCalls.isEmpty { o["tool_calls"] = m.toolCalls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] } }
        if let id = m.toolCallID { o["tool_call_id"] = id }
        return o
    }
    public static func reply(from json: [String: Any]) -> ChatReply? {
        guard let choice = (json["choices"] as? [[String: Any]])?.first, let message = choice["message"] as? [String: Any] else { return nil }
        let text = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let calls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { c -> ToolCall? in
            guard let f = c["function"] as? [String: Any], let name = f["name"] as? String else { return nil }
            let args: String
            if let s = f["arguments"] as? String { args = s }
            else if let o = f["arguments"], let d = try? JSONSerialization.data(withJSONObject: o) { args = String(decoding: d, as: UTF8.self) }
            else { args = "{}" }
            return ToolCall(id: c["id"] as? String ?? UUID().uuidString, name: name, arguments: args)
        }
        return ChatReply(text: text, calls: calls)
    }
}

public enum AnthropicWire {
    public static func body(model: String, messages: [ChatMessage], tools: [ToolSpec], maxTokens: Int = 1200) -> [String: Any] {
        let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        var out: [String: Any] = ["model": model, "max_tokens": maxTokens, "messages": encode(messages.filter { $0.role != .system })]
        if !system.isEmpty { out["system"] = system }
        if !tools.isEmpty { out["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] } }
        return out
    }
    static func encode(_ messages: [ChatMessage]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var pendingResults: [[String: Any]] = []
        func flushResults() { if !pendingResults.isEmpty { out.append(["role": "user", "content": pendingResults]); pendingResults = [] } }
        for m in messages {
            switch m.role {
            case .tool:
                pendingResults.append(["type": "tool_result", "tool_use_id": m.toolCallID ?? "", "content": m.content])
            case .assistant:
                flushResults()
                var blocks: [[String: Any]] = []
                if !m.content.isEmpty { blocks.append(["type": "text", "text": m.content]) }
                for c in m.toolCalls { blocks.append(["type": "tool_use", "id": c.id, "name": c.name, "input": c.input]) }
                out.append(["role": "assistant", "content": blocks.isEmpty ? [["type": "text", "text": "…"]] : blocks])
            case .user:
                flushResults()
                out.append(["role": "user", "content": m.content])
            case .system: break
            }
        }
        flushResults()
        return out
    }
    public static func reply(from json: [String: Any]) -> ChatReply? {
        guard let blocks = json["content"] as? [[String: Any]] else { return nil }
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let calls = blocks.filter { $0["type"] as? String == "tool_use" }.compactMap { b -> ToolCall? in
            guard let name = b["name"] as? String else { return nil }
            let input = b["input"] ?? [:]
            let args = (try? JSONSerialization.data(withJSONObject: input)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            return ToolCall(id: b["id"] as? String ?? UUID().uuidString, name: name, arguments: args)
        }
        return ChatReply(text: text, calls: calls)
    }
}
