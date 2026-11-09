# Roadmap and known rough edges

An honest review of the first public build, with the changes that would make it faster, safer or simpler. Pull requests welcome on any of these.

## Efficiency

- **Thinking tokens.** Qwen 3 reasons before every answer. Through Ollama's OpenAI-compatible endpoint the reasoning arrives in a separate field and is not spoken, but it still costs seconds per turn. Calling Ollama's native `/api/chat` with `think: false` for Mac-side turns would roughly halve the latency; thinking can stay on for free-form phone requests where accuracy matters more than speed.
- **No streaming.** `OwnerTurn` waits for the whole reply before speaking. Streaming the reply and speaking sentence by sentence, as the original design did, cuts time-to-first-word to about a second. `Speech` already queues utterances; the provider needs a streaming variant.
- **Blocking process calls.** `MacRunner.tool` waits for Spotlight and the Shortcuts CLI on the main actor. Moving it to a detached task keeps the island responsive during a long search.
- **Keychain reads per request.** Settings reads the ElevenLabs key and Telegram token from the Keychain on every use. Caching them in memory after the first read avoids repeated Security framework calls.
- **Spotlight queries** are built from up to six words with a content-type filter and run across all allowed roots at once. Fine for home folders; a cap on result count at the `mdfind` level (`-count` first, then query) would help very large volumes.

## Robustness

- **Wake listener restarts.** Audio device changes stop the engine silently; the listener restarts after a second. Plugging in headphones mid-sentence still loses that sentence.
- **Telegram long-poll** backs off on failure but has no jitter; many Macs behind one NAT would retry in lockstep.
- **Pairing codes** are six digits with per-chat rate limiting. Adding a hard cap on wrong attempts per hour before pairing is complete would make guessing hopeless rather than merely slow.
- **Model errors** surface as one spoken sentence. A retry with a smaller context when Ollama reports an out-of-memory error would help 8 GB Macs.

## Design

- **Two targets, one direction.** `SophiaCore` is pure and tested; `Sophia` touches the system. Keep it that way: anything new that can be a pure function with a test belongs in core. The state machine, the clap detector, the file policy and the command parser are the model to copy.
- **The controller** is the one large file and the only place that knows about everything. Splitting the Telegram wiring and the standby logic into their own small objects would make it easier to read; nothing else about it is wrong.
- **One provider protocol** covers Ollama, OpenAI-compatible servers and Anthropic. A streaming method and a capability flag for vision are the two additions the roadmap needs; adding more providers should not need anything else.
- **Memory** is a JSON list of facts. It is deliberately simple and inspectable. If it grows, a small SQLite store with full-text search is the next step, not a vector database.

## Features not yet ported

- **Computer use.** Looking at the screen and clicking through a multi-step task needs a vision-capable model. The accessibility tree reader, screenshot capture and input driver are in place; the loop that drives them is not. With a local vision model (Qwen 2.5-VL, Gemma 3) this can stay fully local.
- **Screen reading** ("what does this say") for the same reason.
- **Calendar awareness** was removed with the server; a read of the local Calendar through EventKit would bring back "no entrance during a meeting" and the battery nudge before one.
- **Notarized builds.** The release is signed ad hoc. A Developer ID would remove the right-click-to-open step and the Keychain re-prompts after updates.

## Testing

73 tests cover the pure core. Missing: an end-to-end test of `OwnerTurn` against a fake provider, a test for `RemoteRunner.find` against a temporary folder, and a Telegram handler test with a fake transport. All three are a protocol injection away.
