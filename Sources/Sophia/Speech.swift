import AVFoundation
import Foundation

@MainActor
final class Speech: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var onLevel: ((Float) -> Void)?
    private var onDone: (() -> Void)?
    private var queue: [String] = []
    private var finished = false
    private var speaking = false
    private var voice = ""
    private var elevenLabsKey: String?
    private var elevenLabsVoice = ""
    private var prefetch: [String: Data] = [:]

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

    func begin(voice: String, elevenLabsKey: String?, elevenLabsVoice: String, onLevel: @escaping (Float) -> Void, onDone: @escaping () -> Void) {
        stop()
        self.voice = voice; self.elevenLabsKey = elevenLabsKey; self.elevenLabsVoice = elevenLabsVoice
        self.onLevel = onLevel; self.onDone = onDone
        finished = false
    }

    func add(_ sentence: String) {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        queue.append(s)
        if let key = elevenLabsKey, !key.isEmpty, prefetch[s] == nil, queue.count <= 2 {
            Task { [weak self] in if let d = await Speech.elevenLabs(s, key: key, voice: self?.elevenLabsVoice ?? "") { self?.prefetch[s] = d } }
        }
        pump()
    }

    func finish() { finished = true; pump() }

    func speak(_ text: String, voice: String, elevenLabsKey: String?, elevenLabsVoice: String, onLevel: @escaping (Float) -> Void, onDone: @escaping () -> Void) {
        begin(voice: voice, elevenLabsKey: elevenLabsKey, elevenLabsVoice: elevenLabsVoice, onLevel: onLevel, onDone: onDone)
        add(text); finish()
    }

    private func pump() {
        guard !speaking else { return }
        guard let next = queue.first else {
            if finished { let cb = onDone; onDone = nil; finished = false; cb?() }
            return
        }
        queue.removeFirst()
        speaking = true
        if let key = elevenLabsKey, !key.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                var data = self.prefetch.removeValue(forKey: next)
                if data == nil { data = await Speech.elevenLabs(next, key: key, voice: self.elevenLabsVoice) }
                if let data, self.play(mp3: data) { return }
                self.speakLocally(next)
            }
        } else {
            speakLocally(next)
        }
    }

    private func speakLocally(_ text: String) {
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
        queue = []; prefetch = [:]; speaking = false; finished = false
        onLevel = nil; onDone = nil
    }

    private func sentenceEnded() {
        timer?.invalidate(); timer = nil
        player?.delegate = nil; player = nil
        speaking = false
        pump()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { Task { @MainActor in self.sentenceEnded() } }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { Task { @MainActor in if self.speaking { self.sentenceEnded() } } }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.sentenceEnded() } }
}
