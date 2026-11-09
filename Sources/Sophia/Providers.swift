import Foundation
import SophiaCore

protocol ModelProvider: Sendable {
    var label: String { get }
    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply
}

struct ProviderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct OpenAICompatibleProvider: ModelProvider {
    let baseURL: URL
    let apiKey: String?
    let model: String
    let label: String

    init(baseURL: URL, apiKey: String? = nil, model: String, label: String = "local model") {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.label = label
    }

    static func ollama(model: String, url: String = "http://localhost:11434") -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(baseURL: URL(string: url) ?? URL(string: "http://localhost:11434")!, model: model, label: "Ollama \(model)")
    }

    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        var r = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"), timeoutInterval: 120)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try JSONSerialization.data(withJSONObject: OpenAIWire.body(model: model, messages: messages, tools: tools))
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError(message: "no response from \(label)") }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError(message: "\(label) answered \(http.statusCode)") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reply = OpenAIWire.reply(from: json) else { throw ProviderError(message: "\(label) sent something unexpected") }
        return reply
    }

    func isReachable() async -> Bool {
        var r = URLRequest(url: baseURL.appendingPathComponent("api/tags"), timeoutInterval: 3)
        r.httpMethod = "GET"
        guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let models = json["models"] as? [[String: Any]] else { return true }
        let names = models.compactMap { $0["name"] as? String }
        return names.isEmpty || names.contains { $0 == model || $0.hasPrefix(model + ":") || model.hasPrefix($0) }
    }
}

struct AnthropicProvider: ModelProvider {
    let apiKey: String
    let model: String
    var label: String { "Anthropic \(model)" }

    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        var r = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 120)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        r.httpBody = try JSONSerialization.data(withJSONObject: AnthropicWire.body(model: model, messages: messages, tools: tools))
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError(message: "no response from Anthropic") }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError(message: "Anthropic answered \(http.statusCode)") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reply = AnthropicWire.reply(from: json) else { throw ProviderError(message: "Anthropic sent something unexpected") }
        return reply
    }
}
