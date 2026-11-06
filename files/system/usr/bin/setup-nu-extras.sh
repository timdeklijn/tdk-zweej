#!/usr/bin/bash
# Keeps Nushell's starship prompt wired up.
#
# Unlike zsh, starship's nu integration is not a config line but a generated
# file: `starship init nu` emits a script that hardcodes the starship path and
# probes nu features (job list, term size), so it must be regenerated whenever
# either binary changes version — which on this image means after any uupd
# pull that bumps starship or nu. The file has to live under $HOME, because
# nushell only autoloads from $nu.vendor-autoload-dirs, which includes
# ~/.local/share/nushell/vendor/autoload — hence a first-login user unit
# rather than something baked into the image.
#
# Runs on every login but exits immediately when the stamp still matches the
# installed versions, so the steady-state cost is one file read plus two
# --version calls.
set -euo pipefail

autoload="$HOME/.local/share/nushell/vendor/autoload/starship.nu"
stamp="$HOME/.cache/nu-extras-stamp"

# Nothing to do on an image without nu, or before nu has ever been started.
command -v nu >/dev/null || exit 0
command -v starship >/dev/null || exit 0

# Deliberately no `| head` here: `starship --version` prints several lines and
# head closing the pipe early would kill it with SIGPIPE, which `pipefail`
# turns into a failed command substitution and aborts this script.
starship_version="$(starship --version)"
starship_version="${starship_version%%$'\n'*}"
want="nu $(nu --version) / ${starship_version}"
have="$(cat "$stamp" 2>/dev/null || true)"

if [ -f "$autoload" ] && [ "$want" = "$have" ]; then
    exit 0
fi

mkdir -p "$(dirname "$autoload")" "$(dirname "$stamp")"

# Write to a temp file in the same directory and rename, so a failed run can
# never leave a truncated autoload file behind — nushell sources it at every
# startup, so half a file would break every new shell.
tmp="$(mktemp "$autoload.XXXXXX")"
starship init nu >"$tmp"
mv "$tmp" "$autoload"
# mktemp creates 0600; make it a normal config file (the temp is renamed, so
# the mode has to be fixed up here rather than at creation time).
chmod 0644 "$autoload"

printf '%s\n' "$want" >"$stamp"
echo "Regenerated $autoload ($want)"
