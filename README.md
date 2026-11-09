# Sophia

A voice assistant that lives in the notch of your Mac. Say "Hey Sophia", ask for something, and she does it on the Mac: opens apps and sites, moves windows, plays music, types for you, changes settings. Message her from your phone and she sends you a file from the laptop, a screenshot, or tells you whether it is still on.

Everything runs on your Mac. The model is a local open model through Ollama. Speech recognition is Apple's on-device engine. Her voice is a British system voice. Nothing leaves the machine except your own Telegram bot and, if you choose to add keys, ElevenLabs or a cloud model for messages from your phone.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Sanjailenin/sophia/main/install.sh | bash
```

The script installs Homebrew if needed, installs and starts Ollama, pulls a model that fits your Mac's memory, downloads the signed app, checks its checksum, and opens it. First run opens Settings and macOS asks for the microphone and speech recognition. For Mac control, allow Accessibility and Screen Recording for Sophia in System Settings → Privacy & Security.

Remove everything with `install.sh --uninstall`. macOS 13 or later.

## Use

- Say "Hey Sophia, …" or press ⌃⌥S. Esc cancels. She keeps listening for a follow-up after answering.
- ⌃⌥D dictates: speak, and she types it where your cursor is.
- "Sophia, go off" puts her to sleep. "Hey Sophia", a double clap, the hotkey or the menu wake her.
- The island follows your pointer across displays. On a screen without a notch it is a pill under the menu bar.
- Nudges: low battery, disk nearly full, network lost and back.
- Optional entrance: a Spotify track or your own file on a double clap or "wake up, daddy's home".

## From your phone

Create a bot with @BotFather in Telegram, paste its token in Settings, and send the six-digit pairing code shown there to the bot. Only that chat is ever answered.

These commands never touch a model:

| Say | She does |
|---|---|
| `status` | Whether the Mac is on, battery, what is in front |
| `screen` | A screenshot |
| `send me <name or words>` | The file, from your allowed folders |
| `find <words>` | Lists matching files |
| `download https://…` | Saves the link to Downloads |
| `lock`, `open Safari`, `quit Slack`, `volume 30`, `mute`, `play`, `next` | The obvious |
| `stop remote` / `start remote` | Switches remote access off and on |

Anything else goes to the model. By default that is the same local Ollama model; in Settings you can point free-form messages from the phone at OpenAI or Anthropic with your own key, while everything said at the Mac stays local.

Files leave the Mac only from the folders you allow (Desktop, Documents, Downloads, Movies, Pictures and Music by default). Hidden files, Library, SSH keys, keychains, env files and anything that looks like a key are refused, as is anything over 100 MB. A closed lid still sleeps the Mac unless a display is attached; "Keep this Mac awake while plugged in" holds it awake on mains power.

## What she can do on the Mac

A fixed list, checked before anything runs: open, quit and switch apps; open https links and files; volume, mute, dark mode, Wi-Fi, lock screen, screenshot; type text; search the web; find files; play music; open System Settings pages; copy to the clipboard; make a note; open app links such as `spotify:`; move windows left, right, full, centre or to another display; hide and show apps; Focus on and off through two Shortcuts you create; change her own settings. Programs and scripts are never opened, and nothing from a model is ever run as a shell command.

## Build from source

```bash
git clone https://github.com/Sanjailenin/sophia && cd sophia
scripts/test.sh
scripts/build-app.sh && open build/Sophia.app
```

Swift 5.9, macOS 13 SDK. Only the Command Line Tools are needed. The test suite covers the state machine, wake word and standby phrases, clap detection, window geometry, the file policy, the remote command parser, the chat wire formats and the Telegram parser.

## Privacy and safety

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md). In short: local model, on-device speech, no telemetry, no update server, keys in your Keychain, a double-checked action list, a strict file policy, and a trigger log that records what woke her without ever storing transcripts.

## License

MIT.
