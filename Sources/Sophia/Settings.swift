import Foundation
import ServiceManagement
import SophiaCore

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var ownerName: String { didSet { d.set(ownerName, forKey: "ownerName") } }
    @Published var ollamaURL: String { didSet { d.set(ollamaURL, forKey: "ollamaURL") } }
    @Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: "ollamaModel") } }
    @Published var phoneProvider: String { didSet { d.set(phoneProvider, forKey: "phoneProvider") } }
    @Published var phoneModel: String { didSet { d.set(phoneModel, forKey: "phoneModel") } }
    @Published var voiceName: String { didSet { d.set(voiceName, forKey: "voiceName") } }
    @Published var elevenLabsVoice: String { didSet { d.set(elevenLabsVoice, forKey: "elevenLabsVoice") } }
    @Published var wakeWord: Bool { didSet { d.set(wakeWord, forKey: "wakeWord") } }
    @Published var wakeMessage = ""
    @Published var casualWake: Bool { didSet { d.set(casualWake, forKey: "casualWake") } }
    static let casualWindow: TimeInterval = 10 * 60
    @Published var conversation: Bool { didSet { d.set(conversation, forKey: "conversation") } }
    @Published var cleanAudio: Bool { didSet { d.set(cleanAudio, forKey: "cleanAudio") } }
    @Published var entrance: Bool { didSet { d.set(entrance, forKey: "entrance") } }
    @Published var entranceFile: String { didSet { d.set(entranceFile, forKey: "entranceFile") } }
    @Published var entranceSpotify: String { didSet { d.set(entranceSpotify, forKey: "entranceSpotify") } }
    @Published var entranceSpotifyStart: Double { didSet { d.set(entranceSpotifyStart, forKey: "entranceSpotifyStart") } }
    @Published var entranceSpotifyStop: Double { didSet { d.set(entranceSpotifyStop, forKey: "entranceSpotifyStop") } }
    @Published var clapSensitivity: String { didSet { d.set(clapSensitivity, forKey: "clapSensitivity") } }
    @Published var islandScreen: String { didSet { d.set(islandScreen, forKey: "islandScreen") } }
    @Published var nudges: Bool { didSet { d.set(nudges, forKey: "nudges") } }
    @Published var standby: Bool { didSet { d.set(standby, forKey: "standby") } }
    @Published var remoteAccess: Bool { didSet { d.set(remoteAccess, forKey: "remoteAccess") } }
    @Published var remoteRoots: String { didSet { d.set(remoteRoots, forKey: "remoteRoots") } }
    @Published var keepAwake: Bool { didSet { d.set(keepAwake, forKey: "keepAwake") } }
    @Published var telegramChatID: Int { didSet { d.set(telegramChatID, forKey: "telegramChatID") } }
    @Published var loginMessage = ""
    @Published var openAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do { if openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginMessage = "" }
            catch { loginMessage = "Couldn't change the login item: \(error.localizedDescription)"; openAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }

    let telegramToken: SecretStore = KeychainSecretStore(service: "dev.sophia.app", account: "telegram-token")
    let elevenLabsKey: SecretStore = KeychainSecretStore(service: "dev.sophia.app", account: "elevenlabs-key")
    let openAIKey: SecretStore = KeychainSecretStore(service: "dev.sophia.app", account: "openai-key")
    let anthropicKey: SecretStore = KeychainSecretStore(service: "dev.sophia.app", account: "anthropic-key")

    init() {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
        ownerName = d.string(forKey: "ownerName") ?? ""
        ollamaURL = d.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        ollamaModel = d.string(forKey: "ollamaModel") ?? "qwen3:8b"
        phoneProvider = d.string(forKey: "phoneProvider") ?? "ollama"
        phoneModel = d.string(forKey: "phoneModel") ?? ""
        voiceName = d.string(forKey: "voiceName") ?? ""
        elevenLabsVoice = d.string(forKey: "elevenLabsVoice") ?? ""
        wakeWord = flag("wakeWord", true)
        casualWake = flag("casualWake", true)
        conversation = flag("conversation", true)
        cleanAudio = flag("cleanAudio", true)
        entrance = flag("entrance", false)
        entranceFile = d.string(forKey: "entranceFile") ?? ""
        entranceSpotify = d.string(forKey: "entranceSpotify") ?? ""
        entranceSpotifyStart = d.double(forKey: "entranceSpotifyStart")
        entranceSpotifyStop = d.double(forKey: "entranceSpotifyStop")
        clapSensitivity = d.string(forKey: "clapSensitivity") ?? "normal"
        islandScreen = d.string(forKey: "islandScreen") ?? "follow"
        nudges = flag("nudges", true)
        standby = d.bool(forKey: "standby")
        remoteAccess = flag("remoteAccess", true)
        remoteRoots = d.string(forKey: "remoteRoots") ?? ""
        keepAwake = d.bool(forKey: "keepAwake")
        telegramChatID = d.integer(forKey: "telegramChatID")
    }

    var localProvider: OpenAICompatibleProvider { .ollama(model: ollamaModel, url: ollamaURL) }

    var phoneProviderInstance: ModelProvider {
        switch phoneProvider {
        case "openai":
            if let key = openAIKey.read(), !key.isEmpty { return OpenAICompatibleProvider(baseURL: URL(string: "https://api.openai.com")!, apiKey: key, model: phoneModel.isEmpty ? "gpt-4o-mini" : phoneModel, label: "OpenAI") }
        case "anthropic":
            if let key = anthropicKey.read(), !key.isEmpty { return AnthropicProvider(apiKey: key, model: phoneModel.isEmpty ? "claude-haiku-5-5" : phoneModel) }
        default: break
        }
        return localProvider
    }
}
