#!/usr/bin/bash
# One-time per-user zsh environment setup: direnv hook, starship prompt
# init line, atuin. Marks itself done via ~/.cache/zsh-extras-done so
# it's a fast no-op after the first successful run; if it fails partway
# (e.g. no network yet), it just tries again next login since the marker
# is only written at the very end.
set -euo pipefail

marker="$HOME/.cache/zsh-extras-done"
[ -f "$marker" ] && exit 0

zshrc="$HOME/.zshrc"
touch "$zshrc"

# --- direnv hook ---
if ! grep -q 'direnv hook zsh' "$zshrc"; then
    echo 'eval "$(direnv hook zsh)"' >> "$zshrc"
fi

# --- Starship prompt (package is baked into the image; just needs the
# init line, since that has to go in ~/.zshrc regardless) ---
if ! grep -q 'starship init zsh' "$zshrc"; then
    echo 'eval "$(starship init zsh)"' >> "$zshrc"
fi

# --- Atuin (better shell history) ---
# Its own installer adds the `eval "$(atuin init zsh)"` line to ~/.zshrc
# itself, so there's nothing extra to append here.
if [ ! -x "$HOME/.atuin/bin/atuin" ]; then
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive
fi

mkdir -p "$HOME/.cache"
touch "$marker"
