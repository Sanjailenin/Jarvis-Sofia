#!/bin/bash
set -euo pipefail

REPO="${SOPHIA_REPO:-Sanjailenin/sophia}"
APP_DIR="${SOPHIA_APP_DIR:-/Applications}"
MODEL="${SOPHIA_MODEL:-}"
VERSION="${SOPHIA_VERSION:-}"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\n\033[31m%s\033[0m\n' "$1"; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  say "Removing Sophia"
  pkill -x Sophia 2>/dev/null || true
  rm -rf "$APP_DIR/Sophia.app"
  rm -rf "$HOME/Library/Application Support/Sophia" "$HOME/Library/Logs/Sophia"
  defaults delete dev.sophia.app 2>/dev/null || true
  echo "Done. Ollama and its models were left in place (brew uninstall ollama removes them)."
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || die "Sophia runs on macOS only."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 13 ] || die "Sophia needs macOS 13 or later."

if [ -z "${SOPHIA_SKIP_MODEL:-}" ]; then
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi

if ! command -v ollama >/dev/null 2>&1; then
  say "Installing Ollama"
  brew install ollama
fi
if ! curl -fs http://localhost:11434/api/tags >/dev/null 2>&1; then
  say "Starting Ollama"
  brew services start ollama >/dev/null 2>&1 || (nohup ollama serve >/dev/null 2>&1 &)
  for _ in $(seq 1 20); do curl -fs http://localhost:11434/api/tags >/dev/null 2>&1 && break; sleep 1; done
fi

if [ -z "$MODEL" ]; then
  MEM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  if [ "$MEM_GB" -ge 32 ]; then MODEL="qwen3:14b"; elif [ "$MEM_GB" -ge 16 ]; then MODEL="qwen3:8b"; else MODEL="qwen3:4b"; fi
fi
say "Pulling the model: $MODEL (this is the slow part)"
ollama pull "$MODEL"
fi

say "Downloading Sophia"
TMP=$(mktemp -d)
LATEST="$VERSION"
[ -n "$LATEST" ] || LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
[ -n "$LATEST" ] || die "Couldn't find a release of $REPO. Build from source instead: git clone https://github.com/$REPO && cd sophia && scripts/build-app.sh"
curl -fsSL -o "$TMP/Sophia.zip" "https://github.com/$REPO/releases/download/$LATEST/Sophia.zip"
curl -fsSL -o "$TMP/Sophia.zip.sha256" "https://github.com/$REPO/releases/download/$LATEST/Sophia.zip.sha256"
(cd "$TMP" && shasum -a 256 -c Sophia.zip.sha256 >/dev/null) || die "Checksum mismatch; not installing."
ditto -x -k "$TMP/Sophia.zip" "$TMP"
pkill -x Sophia 2>/dev/null || true
rm -rf "$APP_DIR/Sophia.app"
mv "$TMP/Sophia.app" "$APP_DIR/Sophia.app"
xattr -dr com.apple.quarantine "$APP_DIR/Sophia.app" 2>/dev/null || true
[ -n "$MODEL" ] && defaults write dev.sophia.app ollamaModel -string "$MODEL"

if [ -n "${SOPHIA_NO_OPEN:-}" ]; then echo "Installed to $APP_DIR/Sophia.app ($LATEST)."; exit 0; fi
say "Opening Sophia"
open "$APP_DIR/Sophia.app"
cat <<EOF

Sophia is installed. On first run she opens Settings:
  1. Allow the microphone and speech recognition when macOS asks.
  2. For Mac control, allow Accessibility and Screen Recording for Sophia in System Settings → Privacy & Security.
  3. Optional: paste a Telegram bot token (from @BotFather) to reach this Mac from your phone, then send the
     six-digit code shown in Settings to your bot.

Say "Hey Sophia" or press ⌃⌥S. Uninstall with: $0 --uninstall
EOF
