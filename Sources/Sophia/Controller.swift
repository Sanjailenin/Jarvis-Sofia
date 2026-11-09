import AppKit
import Combine
import SophiaCore

@MainActor
final class Controller {
    let model = IslandModel()
    var panel: NotchPanel?
    private var machine = IslandStateMachine(conversation: AppSettings.shared.conversation)
    private let settings = AppSettings.shared
    private let recorder = Recorder()
    private let speech = Speech()
    private let wake = WakeListener()
    private let entrance = Entrance()
    private let nudges = NudgeMonitor()
    private let keepAwake = KeepAwake()
    let telegram = TelegramBot()
    private let turn = OwnerTurn()
    private var bag = Set<AnyCancellable>()
    private var generation = 0
    private var work: Task<Void, Never>?
    private var heldClip: Data?
    private var wakeAudio: (preRoll: [Int16], primed: Bool)?
    private var errorTimer: Timer?
    private var videoTimer: Timer?
    private var escKey: HotKey?
    private var pendingLines: [String] = []

    init() {
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        wake.onWake = { [weak self] preRoll, remainder in MainActor.assumeIsolated {
            self?.wakeFromStandby()
            self?.wakeAudio = (preRoll, !remainder.isEmpty)
            self?.hotkeyPressed()
        } }
        wake.onEntrance = { [weak self] how in MainActor.assumeIsolated { self?.entranceTriggered(how) } }
        nudges.onNudge = { [weak self] line in MainActor.assumeIsolated { self?.say(line) } }
        telegram.onPaired = { [weak self] chat in MainActor.assumeIsolated { self?.settings.telegramChatID = chat } }
        telegram.remoteEnabled = { [weak self] in MainActor.assumeIsolated { self?.settings.remoteAccess ?? false } }
        telegram.setRemoteEnabled = { [weak self] on in MainActor.assumeIsolated { self?.settings.remoteAccess = on } }
        telegram.freeform = { [weak self] text in
            guard let self else { return "" }
            do { return try await self.turn.run(text, channel: "phone", provider: self.settings.phoneProviderInstance, ownerName: self.settings.ownerName).reply }
            catch { return "I couldn't reach the model: \(error.localizedDescription)" }
        }
        settings.$conversation.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.machine.conversation = on } }.store(in: &bag)
        settings.$wakeWord.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.applyWake(on) } }.store(in: &bag)
        settings.$clapSensitivity.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] s in MainActor.assumeIsolated { self?.wake.clapSensitivity = ClapDetector.Sensitivity(rawValue: s) ?? .normal } }.store(in: &bag)
        settings.$entrance.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.wake.entranceOn = on } }.store(in: &bag)
        settings.$nudges.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { guard let self else { return }; on && !self.settings.standby ? self.nudges.start() : self.nudges.stop() } }.store(in: &bag)
        settings.$keepAwake.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.keepAwake.enabled = on } }.store(in: &bag)
        settings.$standby.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { guard let self else { return }; if on { if self.machine.phase != .speaking { self.enterStandby() } } else { self.resumeFromStandby() } } }.store(in: &bag)
        settings.$telegramChatID.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in MainActor.assumeIsolated { self?.startTelegram() } }.store(in: &bag)
        keepAwake.start()
        videoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in guard let self else { return }; self.wake.videoInFront = VideoDetector.isVideoInFront() } }
    }

    func startBackground() {
        startTelegram()
        if settings.nudges && !settings.standby { nudges.start() }
        if settings.entrance && !settings.standby { entrance.play(settings) }
    }

    func startTelegram() {
        telegram.start(token: settings.telegramToken.read() ?? "", chatID: settings.telegramChatID, settings: settings)
    }

    func hotkeyPressed() {
        if settings.standby { wakeFromStandby() }
        if !machine.phase.isActive { panel?.reposition(model: model) }
        dispatch(.hotkey)
    }

    func dictationPressed() {
        if machine.phase == .listening && machine.dictating { recorder.stopAndDeliver(); return }
        dispatch(.dictate)
    }

    func escapePressed() { dispatch(.escape) }

    func say(_ line: String) {
        if machine.phase.isActive { pendingLines.append(line); return }
        panel?.reposition(model: model)
        dispatch(.say(line))
    }

    func previewEntrance() { entrance.play(settings) }

    private func entranceTriggered(_ how: String) {
        guard settings.entrance, !entrance.inCooldown, !wake.videoInFront else { return }
        if settings.standby { wakeFromStandby() }
        WakeLog.event("entrance (\(how))")
        entrance.play(settings)
    }

    private func enterStandby() {
        settings.standby = true
        nudges.stop(); entrance.stop()
        syncWake()
        WakeLog.event("standby on")
    }
    func wakeFromStandby() {
        guard settings.standby else { return }
        settings.standby = false
    }
    private func resumeFromStandby() {
        WakeLog.event("standby off")
        applyWake(settings.wakeWord)
        if settings.nudges { nudges.start() }
    }

    private func applyWake(_ on: Bool) {
        settings.wakeMessage = ""
        guard on else { wake.stop(); model.wakeListening = false; return }
        WakeListener.prepare { [weak self] ok, why in
            guard let self else { return }
            if ok { self.syncWake() } else { self.settings.wakeMessage = why ?? ""; self.settings.wakeWord = false }
        }
    }
    private func syncWake() {
        let shouldRun = settings.wakeWord && machine.phase == .idle
        if shouldRun { wake.start() } else { wake.stop() }
        model.wakeListening = wake.running
    }

    func dispatch(_ event: Event) {
        let before = machine.phase
        let effects = machine.handle(event)
        model.phase = machine.phase
        model.transcript = machine.transcript
        panel?.ignoresMouseEvents = !machine.phase.isActive
        updateEscKey()
        if settings.wakeWord { syncWake() }
        if before != machine.phase {
            if !before.isActive && machine.phase.isActive { panel?.reposition(model: model) }
            if before.isActive && machine.phase == .idle {
                wake.casualUntil = settings.casualWake ? Date().addingTimeInterval(AppSettings.casualWindow) : .distantPast
                if let next = pendingLines.first { pendingLines.removeFirst(); Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in Task { @MainActor in self?.say(next) } } }
            }
            cue(before, machine.phase)
        }
        effects.forEach(perform)
    }

    private func perform(_ e: Effect) {
        switch e {
        case .startListening: startListening()
        case .startFollowUp: startListening(followUp: true)
        case .stopListening: recorder.stopAndDeliver()
        case .cancelListening: recorder.cancel(); model.level = 0
        case .transcribe: transcribe()
        case .transcribeDictation: transcribeDictation()
        case .ask(let t): ask(t)
        case .speak(let line): speak(line)
        case .stopSpeaking: speech.stop(); model.level = 0
        case .cancelRequests: generation += 1; work?.cancel(); work = nil; heldClip = nil; speech.stop(); model.level = 0
        case .scheduleErrorDismiss:
            errorTimer?.invalidate()
            errorTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in Task { @MainActor in self?.dispatch(.errorTimeout) } }
        case .chime: NSSound(named: "Glass")?.play()
        case .standby: enterStandby()
        }
    }

    private func startListening(followUp: Bool = false) {
        if followUp && settings.standby { dispatch(.escape); return }
        generation += 1
        Recorder.requestPermission { [weak self] ok in
            guard let self, self.machine.phase == .listening else { return }
            guard ok else { self.dispatch(.failed("Microphone access is off. Allow it in System Settings → Privacy → Microphone.")); return }
            let wake = self.wakeAudio; self.wakeAudio = nil
            self.recorder.start(preRoll: wake?.preRoll ?? [], primed: wake?.primed ?? false, noSpeechTimeout: followUp ? 8 : 9, onLevel: { [weak self] l in Task { @MainActor in self?.model.level = l } }) { [weak self] outcome in
                Task { @MainActor in
                    guard let self, self.machine.phase == .listening else { return }
                    switch outcome {
                    case .clip(let d): self.heldClip = d; self.dispatch(.recordingEnded)
                    case .noSpeech: self.dispatch(.noSpeech)
                    case .silentMic: self.dispatch(.failed("The microphone is silent. Check System Settings → Sound → Input."))
                    case .failed(let m): self.dispatch(.failed(m))
                    }
                }
            }
        }
    }

    private func transcribe() {
        model.level = 0
        let gen = generation
        guard let clip = heldClip else { dispatch(.failed("Nothing was recorded")); return }
        heldClip = nil
        work = Task { [weak self] in
            guard let self else { return }
            let text = WakeWord.stripLeading(await LocalEar.transcribe(wav: clip, hints: ["Hey Sophia", "Sophia"], timeout: 12) ?? "")
            guard gen == self.generation else { return }
            self.dispatch(.transcribed(text))
        }
    }

    private func transcribeDictation() {
        model.level = 0
        let gen = generation
        guard let clip = heldClip else { dispatch(.dictated); return }
        heldClip = nil
        work = Task { [weak self] in
            guard let self else { return }
            let text = Dictation.clean(await LocalEar.transcribe(wav: clip, hints: [], timeout: 20) ?? "")
            guard gen == self.generation else { return }
            if !text.isEmpty { _ = try? await InputDriver.perform("type", ["text": text], scale: ScreenScale(displayWidth: 1, displayHeight: 1)) }
            self.dispatch(.dictated)
        }
    }

    private func ask(_ text: String) {
        let gen = generation
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.turn.run(text, channel: "mac", provider: self.settings.localProvider, ownerName: self.settings.ownerName)
                guard gen == self.generation else { return }
                var line = result.reply
                if !result.failed.isEmpty { line += " I couldn't " + result.failed.joined(separator: "; ") + "." }
                self.dispatch(.replyReady(spokenForm(reply: line)))
            } catch is CancellationError {
            } catch {
                guard gen == self.generation else { return }
                let reachable = await self.settings.localProvider.isReachable()
                self.dispatch(.failed(reachable ? "The model didn't answer: \(error.localizedDescription)" : "Ollama isn't running, or the model isn't pulled. Start it with: ollama serve"))
            }
        }
    }

    private func speak(_ line: String) {
        speech.speak(line, voice: settings.voiceName, elevenLabsKey: settings.elevenLabsKey.read(), elevenLabsVoice: settings.elevenLabsVoice,
                     onLevel: { [weak self] l in Task { @MainActor in self?.model.level = l } },
                     onDone: { [weak self] in Task { @MainActor in self?.model.level = 0; self?.dispatch(.speechFinished) } })
    }

    private func updateEscKey() {
        if machine.phase.isActive {
            if escKey == nil { escKey = HotKey(keyCode: 53, modifiers: 0) { [weak self] in Task { @MainActor in self?.dispatch(.escape) } } }
        } else { escKey?.unregister(); escKey = nil }
    }

    private func cue(_ from: Phase, _ to: Phase) {
        if to == .listening { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now); NSSound(named: "Tink")?.play() }
        if from == .listening && to == .thinking { NSSound(named: "Pop")?.play() }
        if case .error = to { NSSound(named: "Basso")?.play() }
    }
}
