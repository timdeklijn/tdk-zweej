#!/usr/bin/bash
# Per-user zsh environment setup: managed init block for PATH, direnv, zoxide,
# starship, and atuin. Marks itself done via ~/.cache/zsh-extras-done so
# it's a fast no-op after the first successful run; if it fails partway
# (e.g. no network yet), it just tries again next login since the marker
# is only written at the very end.
set -euo pipefail

marker="$HOME/.cache/zsh-extras-done"
zshrc="$HOME/.zshrc"
touch "$zshrc"

[ -f "$marker" ] && exit 0

# --- Project-managed zsh configuration ---
if ! grep -qF '# >>> tdk-zweej managed >>>' "$zshrc"; then
    cat >> "$zshrc" <<'EOF'

# >>> tdk-zweej managed >>>
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.atuin/bin:$PATH"
eval "$(direnv hook zsh)"
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
if [ -x "$HOME/.atuin/bin/atuin" ]; then
    eval "$( $HOME/.atuin/bin/atuin init zsh )"
fi
# <<< tdk-zweej managed <<<
EOF
fi

# --- Atuin (better shell history) ---
# Install it before future shells load the managed init block.
if [ ! -x "$HOME/.atuin/bin/atuin" ]; then
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --non-interactive >/dev/null
fi

mkdir -p "$HOME/.cache"
touch "$marker"
