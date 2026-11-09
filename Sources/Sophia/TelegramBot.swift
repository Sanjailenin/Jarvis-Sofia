import Foundation
import SophiaCore

@MainActor
final class TelegramBot {
    var onPaired: ((Int) -> Void)?
    var freeform: ((String) async -> String)?
    var remoteEnabled: () -> Bool = { true }
    var setRemoteEnabled: (Bool) -> Void = { _ in }
    private var token = ""
    private var allowedChat: Int = 0
    private(set) var pairingCode = ""
    private var loop: Task<Void, Never>?
    private var offset = 0
    private var settings: AppSettings?
    private var recent: [Date] = []

    func start(token: String, chatID: Int, settings: AppSettings) {
        stop()
        self.token = token; self.allowedChat = chatID; self.settings = settings
        guard !token.isEmpty else { return }
        if chatID == 0 { pairingCode = Pairing.code() }
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() { loop?.cancel(); loop = nil }

    private func api(_ method: String) -> URL { URL(string: "https://api.telegram.org/bot\(token)/\(method)")! }

    private func run() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                var r = URLRequest(url: api("getUpdates"), timeoutInterval: 40)
                r.httpMethod = "POST"
                r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                r.httpBody = try JSONSerialization.data(withJSONObject: ["timeout": 25, "offset": offset, "allowed_updates": ["message"]])
                let (data, resp) = try await URLSession.shared.data(for: r)
                guard (resp as? HTTPURLResponse)?.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError(message: "telegram") }
                failures = 0
                for u in TelegramUpdate.list(from: json) {
                    offset = max(offset, u.updateID + 1)
                    await handle(u)
                }
            } catch is CancellationError { return }
            catch {
                failures += 1
                WakeLog.event("telegram poll failed")
                try? await Task.sleep(for: .seconds(min(60, 5 * failures)))
            }
        }
    }

    private func handle(_ u: TelegramUpdate) async {
        guard !u.text.isEmpty else { return }
        if allowedChat == 0 {
            if Pairing.isCode(u.text, pairingCode) {
                allowedChat = u.chatID; pairingCode = ""
                onPaired?(u.chatID)
                await send(u.chatID, "Paired. This chat can now reach the Mac. Send “help” to see what I can do.")
            } else {
                await send(u.chatID, "Not paired. Open Sophia's Settings on the Mac and send me the six-digit code shown there.")
            }
            return
        }
        guard u.chatID == allowedChat else { return }
        guard rateOK() else { await send(u.chatID, "Too many requests; give me a minute."); return }
        WakeLog.event("telegram message")
        if let command = RemoteCommand.parse(u.text) {
            switch command {
            case .stopRemote: setRemoteEnabled(false); await send(u.chatID, "Remote access is off until you send “start remote”."); return
            case .startRemote: setRemoteEnabled(true); await send(u.chatID, "Remote access is on."); return
            default: break
            }
            guard remoteEnabled() else { await send(u.chatID, "Remote access is off. Send “start remote” to turn it on."); return }
            guard let settings else { return }
            let out = await RemoteRunner.run(command, settings: settings)
            if !out.text.isEmpty { await send(u.chatID, out.text) }
            if let file = out.file { await sendFile(u.chatID, file, asPhoto: out.isImage); if out.isImage { try? FileManager.default.removeItem(at: file) } }
            return
        }
        guard remoteEnabled() else { await send(u.chatID, "Remote access is off. Send “start remote” to turn it on."); return }
        guard let freeform else { await send(u.chatID, RemoteCommand.helpText); return }
        let reply = await freeform(u.text)
        await send(u.chatID, reply.isEmpty ? "Done." : reply)
    }

    private func rateOK() -> Bool {
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0) < 3600 }
        guard recent.count < 60 else { return false }
        recent.append(now)
        return true
    }

    func send(_ chat: Int, _ text: String) async {
        var r = URLRequest(url: api("sendMessage"), timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["chat_id": chat, "text": String(text.prefix(4000))])
        _ = try? await URLSession.shared.data(for: r)
    }

    func sendFile(_ chat: Int, _ file: URL, asPhoto: Bool) async {
        guard let data = try? Data(contentsOf: file), data.count <= 2_000_000_000 else { await send(chat, "That file is too large to send."); return }
        let boundary = "sophia-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) { body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!) }
        field("chat_id", String(chat))
        let part = asPhoto && data.count <= 10_000_000 ? "photo" : "document"
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(part)\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var r = URLRequest(url: api(part == "photo" ? "sendPhoto" : "sendDocument"), timeoutInterval: 300)
        r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        _ = try? await URLSession.shared.data(for: r)
    }
}
