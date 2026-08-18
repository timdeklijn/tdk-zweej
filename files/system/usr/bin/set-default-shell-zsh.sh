#!/usr/bin/bash
# Sets zsh as the login shell for real user accounts (UID 1000-59999).
# Run as root, non-interactively, via usermod — unlike chsh, this doesn't
# require the target user's password, so it works fine from a system
# service. Safe to run on every boot: it's a no-op once a user is already
# on zsh, and it also catches accounts created after the fact (e.g. by a
# fresh Anaconda install, or a new user added later).
set -euo pipefail

zsh_path="$(command -v zsh)"

getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1":"$7}' |
while IFS=: read -r user shell; do
    if [ "$shell" != "$zsh_path" ]; then
        echo "Setting shell for $user to $zsh_path"
        usermod -s "$zsh_path" "$user"
    fi
done
