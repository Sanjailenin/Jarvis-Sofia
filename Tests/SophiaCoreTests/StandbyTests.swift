import Testing
@testable import SophiaCore

struct StandbyTests {
    @Test func phrases() {
        for s in ["go off", "Sophia, go off", "okay sophia go to sleep", "stop listening", "power down please", "stand by", "standby", "switch yourself off", "go offline now", "off you go"] {
            #expect(IslandStateMachine.isStandbyPhrase(s), Comment(rawValue: s))
        }
        for s in ["go off the record", "turn off the lights", "stop", "sleep timer for 20 minutes", "power off the tv", "go to sleep mode on my mac", "how do I stand by a friend"] {
            #expect(!IslandStateMachine.isStandbyPhrase(s), Comment(rawValue: s))
        }
    }
    @Test func goingOffSpeaksOnceAndDoesNotListenAgain() {
        var m = IslandStateMachine(conversation: true)
        _ = m.handle(.hotkey); _ = m.handle(.recordingEnded)
        let effects = m.handle(.transcribed("Sophia, go off"))
        #expect(effects == [.standby, .speak(IslandStateMachine.standbyLine)] && m.phase == .speaking)
        _ = m.handle(.speechFinished)
        #expect(m.phase == .listening || m.phase == .idle)
    }
}
