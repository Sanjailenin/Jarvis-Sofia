# Sophia

A voice assistant that lives in the notch of your Mac. Say "Hey Sophia", ask for something, and she does it on the Mac: opens apps and sites, moves windows, plays music, types for you, changes settings. Message her from your phone and she sends you a file from the laptop, a screenshot, or tells you whether it is still on.

Everything runs on your Mac. The model is a local open model through Ollama. Speech recognition is Apple's on-device engine. Her voice is a British system voice. Nothing leaves the machine except your own Telegram bot and, only if you add keys, ElevenLabs or a cloud model for messages from your phone.

## Install

You need a Mac on macOS 13 or later. Apple silicon is recommended; 16 GB of memory runs the default model comfortably.

### Option 1: one line in Terminal

```bash
curl -fsSL https://raw.githubusercontent.com/Sanjailenin/sophia/main/install.sh | bash
```

The script does, in order: installs Homebrew if you do not have it, installs and starts Ollama, pulls a model sized to your Mac's memory (about 5 GB for 16 GB Macs, 9 GB for 32 GB), downloads the latest Sophia release, checks its SHA-256 against the published checksum, puts `Sophia.app` in `/Applications`, and opens it. Read the script first if you like: it is short and plain bash.

Pick a different model with `SOPHIA_MODEL=qwen3:14b` in front of the command. Remove everything later with:

```bash
curl -fsSL https://raw.githubusercontent.com/Sanjailenin/sophia/main/install.sh | bash -s -- --uninstall
```

### Option 2: download the app yourself

1. Install Ollama from [ollama.com](https://ollama.com) or `brew install ollama`, start it, and run `ollama pull qwen3:8b`.
2. Download `Sophia.zip` from the [latest release](https://github.com/Sanjailenin/sophia/releases/latest), unzip it, and move `Sophia.app` to Applications.
3. The app is not notarized yet, so the first time right-click it, choose Open, and confirm.

### Option 3: build from source

```bash
git clone https://github.com/Sanjailenin/sophia && cd sophia
scripts/test.sh
scripts/build-app.sh && open build/Sophia.app
```

Needs the Xcode Command Line Tools (`xcode-select --install`), nothing else.

### First run

Sophia opens her Settings window and macOS asks for permissions as they are needed:

| Permission | Why | Needed for |
|---|---|---|
| Microphone | hearing you | everything by voice |
| Speech Recognition | on-device transcription | the wake word, requests, dictation |
| Accessibility | moving windows, pressing controls, typing | Mac control, dictation |
| Screen Recording | screenshots | the `screen` command from your phone |
| Automation (Spotify, Music, System Events) | music control, dark mode, typing | asked the first time each is used |

Say "Hey Sophia" or press ⌃⌥S and ask for something. If she says the model is not reachable, run `ollama serve` in Terminal or check the model name in Settings.

## Use

- "Hey Sophia, …" or ⌃⌥S to talk. Esc cancels. She keeps listening for a follow-up after answering; "thanks" or "that's all" closes.
- ⌃⌥D dictates: speak, and she types it where your cursor is. Press again to stop early.
- "Sophia, go off" puts her to sleep. "Hey Sophia", a double clap, the hotkey or the menu bar item wake her.
- The island follows your pointer across displays; on a screen without a notch it is a pill under the menu bar.
- Nudges: low battery, disk nearly full, network lost and back.
- Optional entrance: a Spotify track or your own audio file on a double clap or "wake up, daddy's home". Off by default.

Things she can do on the Mac, from a fixed list that is checked before anything runs: open, quit and switch apps; open https links and files; volume, mute, dark mode, Wi-Fi, lock screen, screenshot; type text; search the web; find files; play music; open System Settings pages; copy to the clipboard; make a note; open app links such as `spotify:`; move windows left, right, full, centre or to another display; hide and show apps; Focus on and off through two Shortcuts you create ("Sophia Focus On" and "Sophia Focus Off", each with a Set Focus action); change her own settings. Programs and scripts are never opened, and nothing from a model is ever run as a shell command.

## From your phone

1. In Telegram, message @BotFather, send `/newbot`, and copy the token it gives you.
2. In Sophia's Settings, under "From your phone", paste the token and press Return.
3. Settings shows a six-digit code. Send it to your bot from your phone. Only that chat is ever answered.

These commands never touch a model:

| Message | What happens |
|---|---|
| `status` | whether the Mac is on, battery, what is in front, free disk |
| `screen` | a screenshot |
| `send me <name or words>` | the file, from your allowed folders |
| `find <words>` | a list of matching files |
| `download https://…` | saves the link to Downloads |
| `lock`, `open Safari`, `quit Slack`, `volume 30`, `mute`, `play`, `next` | the obvious |
| `stop remote` / `start remote` | remote access off and on |
| `help` | this list |

Anything else goes to the model. By default that is the same local Ollama model. In Settings you can point free-form messages from the phone at OpenAI or Anthropic with your own key, while everything said at the Mac stays local.

Files leave the Mac only from the folders you allow (Desktop, Documents, Downloads, Movies, Pictures and Music by default). Hidden files, Library, SSH keys, keychains, env files and anything that looks like a key are refused, as is anything over 100 MB. A closed lid still sleeps the Mac unless a display is attached; "Keep this Mac awake while plugged in" holds it awake on mains power.

## Troubleshooting

- **"Ollama isn't running"**: `brew services start ollama` or `ollama serve`, then `ollama pull <model>`. Check the model name in Settings matches `ollama list`.
- **She does not hear "Hey Sophia"**: Speech Recognition and Microphone must be allowed for Sophia; the wake word needs an on-device English model, which macOS downloads under System Settings → General → Language & Region. Check the menu bar icon is not the slashed one (standby).
- **Nothing happens on the Mac when she says she did it**: Accessibility is off for Sophia. System Settings → Privacy & Security → Accessibility.
- **Telegram does not answer**: the token was saved without pressing Return, or the chat is not paired. Unpair and send the new code.
- **What woke her?** `~/Library/Logs/Sophia/events.log` lists every trigger with the app that was in front. It never contains what you said.

## Privacy and safety

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md). In short: local model, on-device speech, no telemetry, no update server, keys in your Keychain, a double-checked action list, a strict file policy, and a trigger log that records what woke her without ever storing transcripts.

## License

MIT.
