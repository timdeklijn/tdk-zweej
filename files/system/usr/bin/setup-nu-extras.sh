#!/usr/bin/bash
# Sets up Nushell's extras, the nu-side counterpart to setup-zsh-extras.sh.
#
# Two different problems, one unit:
#
#  1. Generated init scripts. Nushell has no `eval`, so starship and zoxide
#     integrations have to exist as files. `starship init nu` emits a script
#     that hardcodes the starship path and probes nu features (job list, term
#     size); `zoxide init nushell` emits commands plus an env_change.PWD hook.
#     Both have to be regenerated whenever their binary changes version, which
#     on this image means after any uupd pull that bumps them. starship's file
#     must live under $nu.vendor-autoload-dirs (per-user), zoxide's is sourced
#     from config.nu — either way it is $HOME, never the image.
#
#  2. Managed config blocks. The directory entries for zoxide and the PATH
#     entries for per-user installs can only be written per-user, at login.
#     Same contract as the zsh block: append once, marked, never overwrite
#     anything else, no-op once present.
#
#  3. The prompt theme. A tracked file in the image (/usr/share/tdk-zweej),
#     copied to $HOME once and then yours to edit.
#
# Runs on every login; steady state is two greps plus three --version calls.
set -euo pipefail

cache="$HOME/.cache/tdk-zweej"
stamp="$HOME/.cache/nu-extras-stamp"
nu_config_dir="$HOME/.config/nushell"
nu_config="$nu_config_dir/config.nu"
nu_env="$nu_config_dir/env.nu"
starship_autoload="$HOME/.local/share/nushell/vendor/autoload/starship.nu"
zoxide_nu="$cache/zoxide.nu"
starship_nu_config="$HOME/.config/starship-nu.toml"
starship_nu_theme="/usr/share/tdk-zweej/starship-nu.toml"

# All three come from the image, so a missing one means this isn't the image
# this script was written for — do nothing rather than write half a config.
command -v nu >/dev/null || exit 0
command -v starship >/dev/null || exit 0
command -v zoxide >/dev/null || exit 0

mkdir -p "$cache" "$nu_config_dir" "$HOME/.cache" "$(dirname "$starship_autoload")"

# --- managed blocks (cheap, marker-checked, safe to re-run) -------------------

read -r -d '' config_block <<'EOF' || true

# >>> tdk-zweej managed >>>
# zoxide (`z`, `zi`) — a generated file, sourced here because nushell has no
# `eval`. Written by nu-extras.service; regenerate it with:
#   zoxide init nushell > ~/.cache/tdk-zweej/zoxide.nu
source ~/.cache/tdk-zweej/zoxide.nu
# vim starts nvim (nvim comes from the Nix profile, not the image; nu aliases
# only fail when used, so a missing nvim can't break shell startup)
alias vim = nvim
# direnv: load .envrc on enter, unload on leave. Uses the cookbook's
# pre_prompt variant, not env_change.PWD: that hook fires *before* $env.PWD
# updates, so direnv reads the old directory and only ever loads, leaving
# stale variables behind after you leave. Costs one `direnv export json` per
# prompt.
use std/config *
$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt? | default []) ++ [{||
  if (which direnv | is-empty) { return }
  direnv export json | from json | default {} | update cells --columns [ PATH ] {
    do (env-conversions).path.from_string $in
  } | load-env
}]
# <<< tdk-zweej managed <<<
EOF

read -r -d '' env_block <<'EOF' || true

# >>> tdk-zweej managed >>>
# Per-user installs live outside /usr, so they need to be on PATH: zed, goose,
# opencode and the goose CLI land in ~/.local/bin, atuin in ~/.atuin/bin.
# Guarded so repeated logins can't stack duplicate entries.
for __tdk_dir in [".local/bin" ".atuin/bin"] {
    let __tdk_path = ($env.HOME | path join $__tdk_dir)
    if not ($__tdk_path in $env.PATH) {
        $env.PATH = ($env.PATH | prepend $__tdk_path)
    }
}
# Nu-only prompt style: starship honours $STARSHIP_CONFIG, so zsh keeps the
# stock look while nu gets the tokyo-night preset
# (~/.config/starship-nu.toml, installed from the image and then yours to edit).
let __tdk_starship_nu = ($env.HOME | path join ".config" "starship-nu.toml")
if ($__tdk_starship_nu | path exists) {
    $env.STARSHIP_CONFIG = $__tdk_starship_nu
}
# <<< tdk-zweej managed <<<
EOF

grep -qF '# >>> tdk-zweej managed >>>' "$nu_config" 2>/dev/null ||
    printf '%s\n' "$config_block" >>"$nu_config"
grep -qF '# >>> tdk-zweej managed >>>' "$nu_env" 2>/dev/null ||
    printf '%s\n' "$env_block" >>"$nu_env"

# --- generated init scripts (only when a version moved) -----------------------

# No `| head` anywhere below: `starship --version` prints several lines, and
# head closing the pipe early would kill it with SIGPIPE, which `pipefail`
# turns into a failed command substitution that aborts this script.
starship_version="$(starship --version)"
starship_version="${starship_version%%$'\n'*}"
want="nu $(nu --version) / ${starship_version} / $(zoxide --version)"
have="$(cat "$stamp" 2>/dev/null || true)"

if [ -f "$starship_autoload" ] && [ -f "$zoxide_nu" ] && [ "$want" = "$have" ]; then
    exit 0
fi

# Write to a temp file in the target directory and rename, so an interrupted
# run can never leave a truncated file behind — nushell sources these at every
# startup, so half a file would break every new shell.
generate() {
    local target="$1"
    shift
    local tmp
    tmp="$(mktemp "$target.XXXXXX")"
    "$@" >"$tmp"
    # mktemp creates 0600 and the rename preserves it.
    chmod 0644 "$tmp"
    mv "$tmp" "$target"
    echo "Regenerated $target"
}

generate "$starship_autoload" starship init nu
generate "$zoxide_nu" zoxide init nushell

# The nu-only prompt style: tokyo-night's layout, recoloured green, with
# dev-linux instead of its dev-apple glyph. It ships in the image and is copied
# once, because ~/.config is $HOME and cannot be baked in. Deliberately never
# regenerated -- unlike the init files above, this is config you are meant to
# edit, so an image bump must not clobber your tweaks. Delete it to get it back
# (the next login recreates it) or to fall back to starship's default prompt.
if [ ! -f "$starship_nu_config" ]; then
    if [ -r "$starship_nu_theme" ]; then
        install -Dm0644 "$starship_nu_theme" "$starship_nu_config"
        echo "Installed $starship_nu_config from $starship_nu_theme"
    else
        echo "warning: $starship_nu_theme missing; left $starship_nu_config alone" >&2
    fi
fi

printf '%s\n' "$want" >"$stamp"
