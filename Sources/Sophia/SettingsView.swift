import SwiftUI
import SophiaCore

extension Notification.Name {
    static let sophiaEntrance = Notification.Name("sophiaEntrance")
    static let sophiaTelegramChanged = Notification.Name("sophiaTelegramChanged")
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let pairingCode: () -> String
    @ObservedObject private var fields = SecretFields()

    var body: some View {
        Form {
            Section("You") {
                TextField("Your first name (how Sophia addresses you)", text: $settings.ownerName).textFieldStyle(.roundedBorder)
                Toggle("Open at login", isOn: $settings.openAtLogin)
                if !settings.loginMessage.isEmpty { Text(settings.loginMessage).font(.caption).foregroundStyle(.red) }
            }
            Section("Model (runs on this Mac)") {
                TextField("Ollama address", text: $settings.ollamaURL).textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.ollamaModel).textFieldStyle(.roundedBorder)
                HStack {
                    Text(fields.ollamaState.isEmpty ? "Everything you say to the notch is answered here, on this Mac." : fields.ollamaState).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check") { Task { let ok = await settings.localProvider.isReachable(); fields.ollamaState = ok ? "Ollama is running and the model is ready." : "Ollama isn't reachable, or the model isn't pulled (ollama pull \(settings.ollamaModel))." } }
                }
            }
            Section("Voice") {
                Picker("Voice", selection: $settings.voiceName) {
                    Text("Best British voice available").tag("")
                    ForEach(Speech.britishVoices, id: \.identifier) { v in Text("\(v.name) (\(v.quality == .enhanced || v.quality == .premium ? "enhanced" : "standard"))").tag(v.identifier) }
                }
                Text("Enhanced voices such as Daniel, Serena or Kate download from System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.").font(.caption).foregroundStyle(.secondary)
                SecureField("ElevenLabs API key (optional, for a premium voice)", text: $fields.elevenLabsKey).onSubmit { save(settings.elevenLabsKey, fields.elevenLabsKey) }
                TextField("ElevenLabs voice id (optional)", text: $settings.elevenLabsVoice).textFieldStyle(.roundedBorder)
            }
            Section("Wake") {
                Toggle("Wake with “Hey Sophia” (on this Mac only)", isOn: $settings.wakeWord)
                if !settings.wakeMessage.isEmpty { Text(settings.wakeMessage).font(.caption).foregroundStyle(.red) }
                Toggle("Just “Sophia, …” for 10 minutes after a conversation", isOn: $settings.casualWake).disabled(!settings.wakeWord)
                Toggle("Keep listening after she answers", isOn: $settings.conversation)
                Toggle("Noise suppression and echo cancellation", isOn: $settings.cleanAudio)
                Text("⌃⌥Space or ⌃⌥S talks, ⌃⌥D dictates into the field in front, Esc cancels.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Display") {
                Picker("Island appears on", selection: $settings.islandScreen) { Text("The screen I'm using").tag("follow"); Text("The built-in screen").tag("builtin"); Text("The main display").tag("main") }.pickerStyle(.segmented)
            }
            Section("Entrance") {
                Toggle("Play a song on a double clap or “wake up, daddy's home”", isOn: $settings.entrance)
                Picker("Clap sensitivity", selection: $settings.clapSensitivity) { Text("Low").tag("low"); Text("Normal").tag("normal"); Text("High").tag("high") }.pickerStyle(.segmented).disabled(!settings.entrance)
                TextField("Spotify track link (optional)", text: $settings.entranceSpotify).textFieldStyle(.roundedBorder).disabled(!settings.entrance)
                HStack {
                    TextField("Or your own mp3/wav path", text: $settings.entranceFile).textFieldStyle(.roundedBorder).disabled(!settings.entrance)
                    Button("Play") { NotificationCenter.default.post(name: .sophiaEntrance, object: nil) }.disabled(!settings.entrance)
                }
            }
            Section("Nudges and standby") {
                Toggle("Nudges: low battery, disk nearly full, network lost and back", isOn: $settings.nudges)
                Toggle("Sophia is off (say “Sophia, go off”; “Hey Sophia”, a clap, the hotkey or this switch wakes her)", isOn: $settings.standby)
            }
            Section("From your phone (Telegram)") {
                Toggle("Let Sophia do things on this Mac when I message her", isOn: $settings.remoteAccess)
                SecureField("Telegram bot token (from @BotFather)", text: $fields.telegramToken).onSubmit { save(settings.telegramToken, fields.telegramToken); NotificationCenter.default.post(name: .sophiaTelegramChanged, object: nil) }
                if settings.telegramChatID == 0 {
                    Text(pairingCode().isEmpty ? "Save a token, then send the pairing code to your bot from your phone." : "Send this code to your bot from your phone: \(pairingCode())").font(.caption)
                } else {
                    HStack { Text("Paired with one chat.").font(.caption); Button("Unpair") { settings.telegramChatID = 0 } }
                }
                TextField("Folders files may be sent from (comma-separated; empty = Desktop, Documents, Downloads, Movies, Pictures, Music)", text: $settings.remoteRoots).textFieldStyle(.roundedBorder)
                Toggle("Keep this Mac awake while plugged in", isOn: $settings.keepAwake)
                Picker("Model for free-form requests from the phone", selection: $settings.phoneProvider) { Text("Ollama (local)").tag("ollama"); Text("OpenAI").tag("openai"); Text("Anthropic").tag("anthropic") }
                if settings.phoneProvider == "openai" { SecureField("OpenAI API key", text: $fields.openAIKey).onSubmit { save(settings.openAIKey, fields.openAIKey) } }
                if settings.phoneProvider == "anthropic" { SecureField("Anthropic API key", text: $fields.anthropicKey).onSubmit { save(settings.anthropicKey, fields.anthropicKey) } }
                if settings.phoneProvider != "ollama" { TextField("Model name (optional)", text: $settings.phoneModel).textFieldStyle(.roundedBorder) }
                Text("Commands like “send me the thesis pdf”, “screen”, “status”, “lock” never use a model. Only free-form messages do, and only from the phone. Press Return to save a key; keys live in your Keychain.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            fields.telegramToken = settings.telegramToken.read() ?? ""
            fields.elevenLabsKey = settings.elevenLabsKey.read() ?? ""
            fields.openAIKey = settings.openAIKey.read() ?? ""
            fields.anthropicKey = settings.anthropicKey.read() ?? ""
        }
    }

    private func save(_ store: SecretStore, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { store.delete() } else { try? store.write(v) }
    }
}

final class SecretFields: ObservableObject {
    @Published var telegramToken = ""
    @Published var elevenLabsKey = ""
    @Published var openAIKey = ""
    @Published var anthropicKey = ""
    @Published var ollamaState = ""
}
