#!/bin/bash
# Connects Claude Code to the notch pet by adding hooks to ~/.claude/settings.json.
#
# Safe to run more than once: it backs the file up first and replaces any pet hooks
# it added before, leaving your other hooks untouched.
#
#   ./Scripts/install-claude-pet-hooks.sh            install
#   ./Scripts/install-claude-pet-hooks.sh --uninstall remove the pet hooks again

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SOURCE="$SCRIPT_DIR/claude-pet-hook.sh"
HOOK_DIR="$HOME/.claude/boringnotch"
HOOK_PATH="$HOOK_DIR/claude-pet-hook.sh"
SETTINGS="$HOME/.claude/settings.json"
MODE="${1:-install}"

if [ "$MODE" != "--uninstall" ]; then
    mkdir -p "$HOOK_DIR"
    cp "$HOOK_SOURCE" "$HOOK_PATH"
    chmod +x "$HOOK_PATH"
    echo "Installed hook script at $HOOK_PATH"
fi

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.backup-$(date +%Y%m%d-%H%M%S)"

MODE="$MODE" HOOK_PATH="$HOOK_PATH" SETTINGS="$SETTINGS" python3 <<'PYTHON'
import json, os

settings_path = os.environ["SETTINGS"]
hook_path = os.environ["HOOK_PATH"]
uninstall = os.environ["MODE"] == "--uninstall"

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# Which Claude Code event maps to which pet state.
# Notification covers permission prompts and idle-waiting, both of which mean "Claude wants you".
events = {
    "UserPromptSubmit": ("working", False),
    "PreToolUse": ("working", True),
    "Notification": ("waiting", True),
    "Stop": ("done", False),
    "SessionEnd": ("idle", True),
}

def is_pet_hook(entry):
    return any("claude-pet-hook.sh" in h.get("command", "") for h in entry.get("hooks", []))

for event, (state, supports_matcher) in events.items():
    entries = [e for e in hooks.get(event, []) if not is_pet_hook(e)]

    if not uninstall:
        entry = {"hooks": [{"type": "command", "command": f'"{hook_path}" {state}', "timeout": 5}]}
        if supports_matcher:
            entry["matcher"] = ""
        entries.append(entry)

    if entries:
        hooks[event] = entries
    else:
        hooks.pop(event, None)

if not hooks:
    settings.pop("hooks", None)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(("Removed" if uninstall else "Added") + f" pet hooks in {settings_path}")
PYTHON

echo
echo "Restart any running Claude Code sessions to pick up the change."
echo "Then turn on 'Show Claude Code pet' in the notch settings, under Appearance."
