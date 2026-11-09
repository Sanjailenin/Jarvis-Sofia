#!/bin/bash
set -euo pipefail

REPO="${SOFIA_REPO:-Sanjailenin/sofia}"
APP_DIR="${SOFIA_APP_DIR:-/Applications}"
MODEL="${SOFIA_MODEL:-}"
VERSION="${SOFIA_VERSION:-}"

say() { printf '\n\033[1m%s\033[0m\n' "$1"; }
die() { printf '\n\033[31m%s\033[0m\n' "$1"; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  say "Removing Sofia"
  pkill -x Sofia 2>/dev/null || true
  rm -rf "$APP_DIR/Sofia.app" "$APP_DIR/Sophia.app"
  rm -rf "$HOME/Library/Application Support/Sofia" "$HOME/Library/Logs/Sofia" "$HOME/Library/Application Support/Sophia" "$HOME/Library/Logs/Sophia"
  defaults delete dev.sofia.app 2>/dev/null || true; defaults delete dev.sophia.app 2>/dev/null || true
  echo "Done. Ollama and its models were left in place (brew uninstall ollama removes them)."
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] || die "Sofia runs on macOS only."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 13 ] || die "Sofia needs macOS 13 or later."

if [ -z "${SOFIA_SKIP_MODEL:-}" ]; then
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

say "Downloading Sofia"
TMP=$(mktemp -d)
LATEST="$VERSION"
[ -n "$LATEST" ] || LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
[ -n "$LATEST" ] || die "Couldn't find a release of $REPO. Build from source instead: git clone https://github.com/$REPO && cd sofia && scripts/build-app.sh"
ASSET="Sofia"
curl -fsSL -o "$TMP/$ASSET.zip" "https://github.com/$REPO/releases/download/$LATEST/$ASSET.zip" 2>/dev/null || { ASSET="Sophia"; curl -fsSL -o "$TMP/$ASSET.zip" "https://github.com/$REPO/releases/download/$LATEST/$ASSET.zip" || die "Couldn't download the app from release $LATEST."; }
curl -fsSL -o "$TMP/$ASSET.zip.sha256" "https://github.com/$REPO/releases/download/$LATEST/$ASSET.zip.sha256" || die "Couldn't download the checksum."
(cd "$TMP" && shasum -a 256 -c "$ASSET.zip.sha256" >/dev/null) || die "Checksum mismatch; not installing."
ditto -x -k "$TMP/$ASSET.zip" "$TMP"
pkill -x Sofia 2>/dev/null || true; pkill -x Sophia 2>/dev/null || true
rm -rf "$APP_DIR/Sofia.app" "$APP_DIR/Sophia.app"
mv "$TMP/$ASSET.app" "$APP_DIR/Sofia.app"
xattr -dr com.apple.quarantine "$APP_DIR/Sofia.app" 2>/dev/null || true
[ -n "$MODEL" ] && defaults write dev.sofia.app ollamaModel -string "$MODEL"

if [ -n "${SOFIA_NO_OPEN:-}" ]; then echo "Installed to $APP_DIR/Sofia.app ($LATEST)."; exit 0; fi
say "Opening Sofia"
open "$APP_DIR/Sofia.app"
cat <<EOF

SOFIA is installed. On first run a welcome window asks for her name and voice, then:
  1. Allow the microphone and speech recognition when macOS asks.
  2. For Mac control, allow Accessibility and Screen Recording for Sofia in System Settings → Privacy & Security.
  3. Optional: paste a Telegram bot token (from @BotFather) to reach this Mac from your phone, then send the
     six-digit code shown in Settings to your bot.

Say "Hey <her name>" or press ⌃⌥S. Uninstall with: $0 --uninstall
EOF
