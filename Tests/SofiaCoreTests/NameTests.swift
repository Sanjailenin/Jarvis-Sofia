import Testing
@testable import SofiaCore

struct NameTests {
    @Test func defaultNameHearsBothSpellings() {
        let w = WakeWord(name: "Sofia")
        for s in ["hey sofia open safari", "Hey Sophia", "okay so fear what's up", "hello sophie"] { #expect(w.matches(s), Comment(rawValue: s)) }
        #expect(w.remainder("hey sofia open safari") == "open safari")
        #expect(w.stripLeading("so earlier, hey Sophia, what time is it") == "What time is it")
        #expect(WakeWord(name: "").name == "Sofia" && WakeWord(name: "  ").namePattern == WakeWord(name: "Sofia").namePattern)
    }
    @Test func customNameWakesOnlyOnItself() {
        let nova = WakeWord(name: "Nova")
        #expect(nova.matches("hey nova") && nova.matches("Hey Novah, lights") && !nova.matches("hey sofia") && !nova.matches("hey sophia"))
        #expect(nova.matches("nova, open mail", casual: true) && !nova.matches("nova, open mail", casual: false))
        #expect(nova.remainder("hey nova, open mail") == "open mail")
        #expect(nova.stripLeading("Nova open mail") == "Open mail")
        #expect(nova.hints.first == "Hey Nova")
        let jarvis = WakeWord(name: "Jarvis")
        #expect(jarvis.matches("hey jarvis") && !jarvis.matches("hey nova"))
        let kathy = WakeWord(name: "Cathy")
        #expect(kathy.matches("hey kathy") && kathy.matches("hey cathy"))
    }
    @Test func variantsAreSensible() {
        #expect(WakeWord.variants(of: "Sophia").contains("so fear"))
        let v = WakeWord.variants(of: "Phoebe")
        #expect(v.contains("phoebe") && v.contains("foebe"))
        #expect(WakeWord.variants(of: "Anna").contains("ana") && WakeWord.variants(of: "Anna").contains("annah"))
        #expect(WakeWord.variants(of: "Max") == ["max"])
    }
    @Test func standbyClosingAndPromptFollowTheCurrentName() {
        let saved = WakeWord.current
        defer { WakeWord.current = saved }
        WakeWord.current = WakeWord(name: "Nova")
        #expect(IslandStateMachine.isStandbyPhrase("nova, go off") && !IslandStateMachine.isStandbyPhrase("sofia, go off"))
        #expect(IslandStateMachine.isStandbyPhrase("go to sleep"))
        #expect(IslandStateMachine.standbyLine == "Going off. Say Hey Nova or clap twice when you want me back.")
        #expect(IslandStateMachine.isClosing("thanks nova") && !IslandStateMachine.isClosing("thanks sofia"))
        #expect(Prompt.system(ownerName: "Alex", facts: [], channel: "mac", assistantName: "Nova").hasPrefix("You are Nova,"))
        WakeWord.current = WakeWord(name: "Sofia")
        #expect(IslandStateMachine.isStandbyPhrase("sophia, go off") && IslandStateMachine.isStandbyPhrase("sofia go off"))
    }
}
