import Testing
import Foundation
@testable import SophiaCore

final class FakeMemory: MemoryStoring, @unchecked Sendable {
    var facts: [String] = []
    func remember(_ fact: String) { facts.append(fact) }
    func forget(matching words: String) -> Int { let n = facts.count; facts.removeAll { $0.lowercased().contains(words.lowercased()) }; return n - facts.count }
}

final class FakePerformer: ActionPerformer, @unchecked Sendable {
    var performed: [MacAction] = []
    var fail = false
    var tasks: [String] = []
    func perform(_ action: MacAction) async -> ActionOutcome { performed.append(action); return fail ? .failed("no app called \(action.target)") : .done("") }
    func computerTask(_ goal: String, progress: @escaping @Sendable (String) -> Void) async -> String { tasks.append(goal); progress("Step 1: click"); return "Filled in the form." }
}

final class ScriptedProvider: ModelProvider, @unchecked Sendable {
    var label = "scripted"
    var supportsVision = true
    var replies: [ChatReply]
    var seen: [[ChatMessage]] = []
    var streamPieces: [String]? = nil
    init(_ replies: [ChatReply]) { self.replies = replies }
    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        seen.append(messages)
        guard !replies.isEmpty else { throw ProviderError("out of script") }
        return replies.removeFirst()
    }
    func stream(_ messages: [ChatMessage], tools: [ToolSpec], onText: @escaping @Sendable (String) -> Void) async throws -> ChatReply {
        let r = try await chat(messages, tools: tools)
        if let pieces = streamPieces, !r.text.isEmpty { for p in pieces { onText(p) } } else if !r.text.isEmpty { onText(r.text) }
        return r
    }
}

struct AssistantTurnTests {
    @Test func toolCallThenAnswer() async throws {
        let memory = FakeMemory(), performer = FakePerformer()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "c1", name: "mac_control", arguments: #"{"action":"open_app","target":"Safari"}"#)]), ChatReply(text: "Safari is open.")])
        let turn = AssistantTurn(memory: memory, performer: performer)
        let r = try await turn.run("open safari", channel: "mac", provider: provider, ownerName: "Alex", allowComputer: false)
        #expect(r.reply == "Safari is open." && r.performed == ["open Safari"] && r.failed.isEmpty)
        #expect(performer.performed.first?.kind == .openApp)
        #expect(provider.seen.count == 2 && provider.seen[1].last?.role == .tool && provider.seen[1].last?.toolCallID == "c1")
        #expect(provider.seen[0].first?.content.contains("Alex") == true)
    }
    @Test func invalidActionIsRefusedAndFailureReported() async throws {
        let performer = FakePerformer(); performer.fail = true
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "a", name: "mac_control", arguments: #"{"action":"rm_rf"}"#), ToolCall(id: "b", name: "mac_control", arguments: #"{"action":"open_app","target":"Nope"}"#)]), ChatReply(text: "That didn't work.")])
        let turn = AssistantTurn(memory: FakeMemory(), performer: performer)
        let r = try await turn.run("x", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(performer.performed.count == 1 && r.failed == ["no app called Nope"])
        let results = provider.seen[1].suffix(2).map(\.content)
        #expect(results[0].hasPrefix("Refused") && results[1].hasPrefix("Failed"))
    }
    @Test func memoryToolsAndHistory() async throws {
        let memory = FakeMemory()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "m", name: "remember_fact", arguments: #"{"fact":"Likes tea"}"#)]), ChatReply(text: "Noted."), ChatReply(text: "You like tea.")])
        let turn = AssistantTurn(memory: memory, performer: FakePerformer())
        _ = try await turn.run("remember I like tea", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(memory.facts == ["Likes tea"])
        let r2 = try await turn.run("what do I like", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(r2.reply == "You like tea." && provider.seen[2].count == 6 && provider.seen[2].first?.content.contains("Likes tea") == true)
        await turn.clear("mac")
        _ = try? await turn.run("hi", channel: "mac", provider: ScriptedProvider([ChatReply(text: "Hi.")]), ownerName: "", allowComputer: false)
    }
    @Test func streamingSpeaksSentencesAndComputerTaskRuns() async throws {
        let performer = FakePerformer()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "t", name: "computer_task", arguments: #"{"goal":"fill in the form"}"#)]), ChatReply(text: "Done, the form is filled. Anything else?")])
        provider.streamPieces = ["Done, the form", " is filled. Anything", " else?"]
        var spoken: [String] = []
        let box = Box()
        let turn = AssistantTurn(memory: FakeMemory(), performer: performer)
        let r = try await turn.run("fill the form", channel: "mac", provider: provider, ownerName: "", allowComputer: true, onSentence: { box.add($0) })
        spoken = box.items
        #expect(performer.tasks == ["fill in the form"] && r.performed == ["a screen task"])
        #expect(spoken == ["Done, the form is filled.", "Anything else?"])
        #expect(provider.seen[1].last?.content == "Filled in the form.")
    }
    @Test func computerToolOnlyWhenAllowed() async throws {
        let provider = ScriptedProvider([ChatReply(text: "ok"), ChatReply(text: "ok")])
        let turn = AssistantTurn(memory: FakeMemory(), performer: FakePerformer())
        _ = try await turn.run("x", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        _ = try await turn.run("x", channel: "mac", provider: provider, ownerName: "", allowComputer: true)
        #expect(provider.seen[0].first?.content.contains("computer_task") == false && provider.seen[1].first?.content.contains("computer_task") == true)
    }
}

final class Box: @unchecked Sendable {
    private let lock = NSLock(); private var list: [String] = []
    func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
    var items: [String] { lock.lock(); defer { lock.unlock() }; return list }
}

struct TelegramRouterTests {
    let update = { (chat: Int, text: String) in TelegramUpdate(updateID: 1, chatID: chat, text: text) }

    @Test func pairingFlowAndLockout() {
        var s = TelegramState(pairedChat: 0, pairingCode: "123456")
        #expect(TelegramRouter.route(update(7, "hello"), state: &s) == .reply("Not paired. Open Sophia's Settings on the Mac and send me the six-digit code shown there."))
        for _ in 0..<3 { _ = TelegramRouter.route(update(7, "000000"), state: &s) }
        let last = TelegramRouter.route(update(7, "000000"), state: &s)
        #expect(last == .reply("Too many wrong codes. Pairing is paused for an hour.") && s.lockedUntil != nil)
        #expect(TelegramRouter.route(update(7, "123456"), state: &s) == .ignore)
        s.lockedUntil = Date(timeIntervalSinceNow: -1)
        #expect(TelegramRouter.route(update(7, "123 456"), state: &s) == .paired(7, "Paired. This chat can now reach the Mac. Send “help” to see what I can do."))
        #expect(s.pairedChat == 7 && s.pairingCode == "")
    }
    @Test func onlyThePairedChatIsAnswered() {
        var s = TelegramState(pairedChat: 7)
        #expect(TelegramRouter.route(update(8, "status"), state: &s) == .ignore)
        #expect(TelegramRouter.route(update(7, "status"), state: &s) == .command(.status))
        #expect(TelegramRouter.route(update(7, "what did I do yesterday"), state: &s) == .freeform("what did I do yesterday"))
        #expect(TelegramRouter.route(update(7, ""), state: &s) == .ignore)
    }
    @Test func remoteSwitch() {
        var s = TelegramState(pairedChat: 7)
        #expect(TelegramRouter.route(update(7, "stop remote"), state: &s) == .setRemote(false, "Remote access is off until you send “start remote”.") && !s.remoteEnabled)
        #expect(TelegramRouter.route(update(7, "send me the thesis"), state: &s) == .reply("Remote access is off. Send “start remote” to turn it on."))
        #expect(TelegramRouter.route(update(7, "start remote"), state: &s) == .setRemote(true, "Remote access is on."))
        #expect(TelegramRouter.route(update(7, "send me the thesis"), state: &s) == .command(.sendFile("thesis")))
    }
    @Test func backoffGrowsWithJitter() {
        #expect(TelegramRouter.backoff(failures: 1, jitter: 0) == 5 && TelegramRouter.backoff(failures: 3, jitter: 0) == 15)
        #expect(TelegramRouter.backoff(failures: 20, jitter: 0) == 60 && TelegramRouter.backoff(failures: 20, jitter: 1) == 78)
    }
}

struct SplitterAndOllamaTests {
    @Test func sentencesComeOutAsTheyComplete() {
        var s = SentenceSplitter()
        var out: [String] = []
        out += s.push("Opening Safari now. It will")
        out += s.push(" take a moment, e.g. a second or two. Done!")
        #expect(out == ["Opening Safari now.", "It will take a moment, e.g. a second or two."])
        #expect(s.flush() == "Done!")
        var short = SentenceSplitter()
        #expect(short.push("Hi. There you go. ") == ["Hi. There you go."])
    }
    @Test func ollamaWireAndStreaming() {
        let body = OllamaWire.body(model: "qwen3:8b", messages: [.system("s"), .user("hi"), .assistant("", calls: [ToolCall(id: "x", name: "mac_control", arguments: #"{"action":"mute"}"#)]), .tool("x", "Done.")], tools: Prompt.tools, stream: true, think: false)
        #expect(body["think"] as? Bool == false && body["stream"] as? Bool == true)
        let msgs = body["messages"] as! [[String: Any]]
        #expect(((msgs[2]["tool_calls"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["arguments"] as? [String: String] == ["action": "mute"])
        let r = OllamaWire.reply(from: ["message": ["role": "assistant", "content": " Muted. ", "tool_calls": [["function": ["name": "mac_control", "arguments": ["action": "mute"]]]]]])!
        #expect(r.text == "Muted." && r.calls[0].input["action"] as? String == "mute")
        var st = OllamaWire.StreamState()
        #expect(st.feed(line: #"{"message":{"role":"assistant","content":"Open"},"done":false}"#) == "Open")
        #expect(st.feed(line: #"{"message":{"role":"assistant","content":"ing."},"done":false}"#) == "ing.")
        #expect(st.feed(line: #"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"mac_control","arguments":{"action":"lock_screen"}}}]},"done":true}"#) == nil)
        #expect(st.done && st.reply.text == "Opening." && st.reply.calls.count == 1)
        #expect(st.feed(line: "not json") == nil)
    }
    @Test func imagesTravelInWireFormats() {
        let m = ChatMessage(role: .user, content: "look", images: ["AAAA"])
        let o = OpenAIWire.body(model: "m", messages: [m], tools: [])["messages"] as! [[String: Any]]
        #expect((o[0]["content"] as? [[String: Any]])?.count == 2)
        let a = AnthropicWire.body(model: "m", messages: [m, .assistant("", calls: [ToolCall(id: "t", name: "screenshot", arguments: "{}")]), .tool("t", "screen", images: ["BBBB"])], tools: [])["messages"] as! [[String: Any]]
        let result = ((a[2]["content"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(result?.count == 2 && result?[1]["type"] as? String == "image")
        let ol = OllamaWire.body(model: "m", messages: [m], tools: [], stream: false, think: false)["messages"] as! [[String: Any]]
        #expect(ol[0]["images"] as? [String] == ["AAAA"])
    }
}

struct ComputerLoopTests {
    final class FakeHost: ComputerHost, @unchecked Sendable {
        var log: [String] = []
        func screenshot() async throws -> Screenshot { log.append("shot"); return Screenshot(base64: "IMG", width: 1280, height: 800) }
        func click(x: Int, y: Int, double: Bool, right: Bool) async throws { log.append("click \(x),\(y)") }
        func type(_ text: String) async throws { log.append("type \(text)") }
        func key(_ combo: String) async throws { log.append("key \(combo)") }
        func scroll(x: Int, y: Int, direction: String, amount: Int) async throws { log.append("scroll") }
        func findElements(_ query: String) async throws -> String { log.append("find \(query)"); return "e1 button \"Compose\" (120,80)" }
        func pressElement(_ id: String, text: String?) async throws -> String { log.append("press \(id)"); return "Pressed button \"Compose\"." }
    }
    @Test func controlsFirstThenDone() async {
        let host = FakeHost()
        let provider = ScriptedProvider([
            ChatReply(text: "", calls: [ToolCall(id: "1", name: "find_elements", arguments: #"{"query":"compose"}"#)]),
            ChatReply(text: "", calls: [ToolCall(id: "2", name: "press_element", arguments: #"{"id":"e1"}"#)]),
            ChatReply(text: "", calls: [ToolCall(id: "3", name: "done", arguments: #"{"summary":"Compose is open.","success":true}"#)]),
        ])
        let out = await ComputerLoop.run(goal: "open compose", host: host, provider: provider) { _ in }
        #expect(out == "Compose is open." && host.log == ["shot", "find compose", "press e1"])
        #expect(provider.seen[0].first?.content.contains("open compose") == true && provider.seen[0][1].images == ["IMG"])
    }
    @Test func repeatedStepStopsAndNoVisionRefuses() async {
        let host = FakeHost()
        let same = ChatReply(text: "", calls: [ToolCall(id: "k", name: "click", arguments: #"{"x":10,"y":10}"#)])
        let provider = ScriptedProvider([same, same, same, same])
        let out = await ComputerLoop.run(goal: "x", host: host, provider: provider) { _ in }
        #expect(out.hasPrefix("I kept repeating"))
        let blind = ScriptedProvider([]); blind.supportsVision = false
        #expect((await ComputerLoop.run(goal: "x", host: host, provider: blind) { _ in }).contains("no vision"))
    }
}
