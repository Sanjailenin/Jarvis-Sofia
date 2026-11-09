# Security

## Model

The model decides what to do; the app decides what is allowed. Every Mac action goes through a fixed list (`MacAction`) and is validated on its parameters before it runs. There is no shell execution, no arbitrary AppleScript, and no file is ever opened by a path the model made up if it looks like a program or script. Tool results are treated as data, and the prompt says so.

Remote commands from the phone are parsed deterministically; only free-form messages reach a model. Only one paired Telegram chat is answered, paired with a one-time code shown in Settings. Remote access has an off switch ("stop remote") and a rate limit.

Files sent off the Mac pass `FilePolicy`: allowed roots only, symlinks resolved first, hidden paths and off-limits folders refused, secret-looking names and contents refused, size caps.

Keys and tokens are stored in the macOS Keychain under the app's own service name. Nothing is logged that contains them.

## Reporting

Open a private security advisory on the repository, or email the maintainers listed in the repository profile. Please do not file public issues for vulnerabilities. You will get an answer within a week.

## Out of scope

Behaviour of Ollama, Telegram, ElevenLabs, OpenAI or Anthropic themselves; a Mac that is already compromised; a user granting the paired chat to someone else.
