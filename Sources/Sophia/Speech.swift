import AVFoundation
import Foundation

@MainActor
final class Speech: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var onLevel: ((Float) -> Void)?
    private var onDone: (() -> Void)?

    override init() { super.init(); synth.delegate = self }

    static var britishVoices: [AVSpeechSynthesisVoice] {
        let preferred = ["Daniel", "Serena", "Kate", "Oliver", "Stephanie"]
        let gb = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en-GB") }
        return gb.sorted { a, b in
            let ia = preferred.firstIndex(where: { a.name.hasPrefix($0) }) ?? 99, ib = preferred.firstIndex(where: { b.name.hasPrefix($0) }) ?? 99
            if ia != ib { return ia < ib }
            return a.quality.rawValue > b.quality.rawValue
        }
    }

    static func voice(named name: String) -> AVSpeechSynthesisVoice? {
        if !name.isEmpty, let v = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == name || $0.identifier == name }) { return v }
        return britishVoices.first ?? AVSpeechSynthesisVoice(language: "en-GB")
    }

    func speak(_ text: String, voice: String, elevenLabsKey: String?, elevenLabsVoice: String, onLevel: @escaping (Float) -> Void, onDone: @escaping () -> Void) {
        stop()
        self.onLevel = onLevel; self.onDone = onDone
        if let key = elevenLabsKey, !key.isEmpty {
            Task { [weak self] in
                if let data = await Speech.elevenLabs(text, key: key, voice: elevenLabsVoice), let self, self.play(mp3: data) { return }
                self?.speakLocally(text, voice: voice)
            }
        } else {
            speakLocally(text, voice: voice)
        }
    }

    private func speakLocally(_ text: String, voice: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = Speech.voice(named: voice)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in Task { @MainActor in self?.onLevel?(Float.random(in: 0.25...0.8)) } }
    }

    private func play(mp3 data: Data) -> Bool {
        guard let p = try? AVAudioPlayer(data: data) else { return false }
        player = p; p.delegate = self; p.isMeteringEnabled = true
        guard p.play() else { return false }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let p = self?.player else { return }
            p.updateMeters()
            self?.onLevel?(Float(max(0, min(1, (p.averagePower(forChannel: 0) + 50) / 40))))
        } }
        return true
    }

    static func elevenLabs(_ text: String, key: String, voice: String) async -> Data? {
        let id = voice.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : voice
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(id)?output_format=mp3_44100_64") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "xi-api-key")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["text": String(text.prefix(1200)), "model_id": "eleven_turbo_v2_5"])
        guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200, data.count > 100 else { return nil }
        return data
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.delegate = nil; player?.stop(); player = nil
        synth.stopSpeaking(at: .immediate)
        onLevel = nil; onDone = nil
    }

    private func finished() { let cb = onDone; stop(); cb?() }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { Task { @MainActor in self.finished() } }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.finished() } }
}
