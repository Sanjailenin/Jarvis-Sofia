import AVFoundation
import SwiftUI
import SofiaCore

struct SetupView: View {
    @ObservedObject var settings: AppSettings
    let done: () -> Void
    @ObservedObject private var state = SetupState()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome").font(.largeTitle.bold())
            Text("Two choices before we start. You can change both later in Settings.").foregroundStyle(.secondary)

            GroupBox("Her name") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $settings.assistantName).textFieldStyle(.roundedBorder)
                    Text("You'll wake her with “Hey \(settings.assistantName.isEmpty ? WakeWord.defaultName : settings.assistantName)”. Short names with clear vowels are heard best.").font(.caption).foregroundStyle(.secondary)
                    TextField("Your first name (how she addresses you)", text: $settings.ownerName).textFieldStyle(.roundedBorder)
                }.padding(6)
            }

            GroupBox("Her voice") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Voice", selection: $settings.voiceName) {
                        Text("Best British voice available").tag("")
                        ForEach(SetupState.groups, id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.voices, id: \.identifier) { v in Text("\(v.name) · \(v.language)\(v.quality == .enhanced || v.quality == .premium ? " · enhanced" : "")").tag(v.identifier) }
                            }
                        }
                    }
                    HStack {
                        Button(state.previewing ? "Speaking…" : "Preview") { state.preview(name: settings.assistantName.isEmpty ? WakeWord.defaultName : settings.assistantName, voice: settings.voiceName) }.disabled(state.previewing)
                        Text("Enhanced voices such as Daniel, Serena or Kate download from System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(6)
            }

            GroupBox("The model") {
                HStack {
                    Text(state.ollama.isEmpty ? "She thinks with Ollama on this Mac (\(settings.ollamaModel))." : state.ollama).font(.caption)
                    Spacer()
                    Button("Check") { Task { let ok = await settings.localProvider.isReachable(); state.ollama = ok ? "Ollama is running and \(settings.ollamaModel) is ready." : "Ollama isn't reachable, or \(settings.ollamaModel) isn't pulled (ollama pull \(settings.ollamaModel))." } }
                }.padding(6)
            }

            Spacer()
            HStack {
                Text("Next, macOS will ask for the microphone and speech recognition. Allow both for voice to work.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Continue") { if settings.assistantName.trimmingCharacters(in: .whitespaces).isEmpty { settings.assistantName = WakeWord.defaultName }; done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 600)
        .onAppear { if settings.assistantName.isEmpty { settings.assistantName = WakeWord.defaultName } }
    }
}

@MainActor
final class SetupState: ObservableObject {
    @Published var previewing = false
    @Published var ollama = ""
    private let speech = Speech()

    struct Group { let title: String; let voices: [AVSpeechSynthesisVoice] }
    static var groups: [Group] {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { !$0.identifier.contains("eloquence") }
        let british = all.filter { $0.language.hasPrefix("en-GB") || $0.language.hasPrefix("en-IE") }
        let english = all.filter { $0.language.hasPrefix("en") && !british.contains($0) }
        let other = all.filter { !$0.language.hasPrefix("en") }
        return [Group(title: "British and Irish", voices: british.sorted { $0.name < $1.name }), Group(title: "Other English", voices: english.sorted { $0.name < $1.name }), Group(title: "Other languages", voices: other.sorted { $0.name < $1.name })].filter { !$0.voices.isEmpty }
    }

    func preview(name: String, voice: String) {
        previewing = true
        speech.speak("Hi, I'm \(name). Say Hey \(name) whenever you need me.", voice: voice, elevenLabsKey: nil, elevenLabsVoice: "", onLevel: { _ in }, onDone: { [weak self] in Task { @MainActor in self?.previewing = false } })
    }
}
