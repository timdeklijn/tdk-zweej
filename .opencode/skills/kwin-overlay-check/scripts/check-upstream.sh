#!/usr/bin/env bash
# Status check for the KWin output-layer workaround (KWIN_USE_OVERLAYS=0).
# APIs verified 2026-09-30. Needs curl + jq (jq is available via the Nix profile).
set -u

BUGS="509635,512511,523021,523022,517490"

echo "== Installed versions =="
rpm -q kwin plasma-workspace plasma-login-manager 2>/dev/null || true
echo

echo "== KDE Bugzilla =="
curl -sf --max-time 30 \
  "https://bugs.kde.org/rest/bug?id=${BUGS}&include_fields=id,summary,status,resolution,cf_versionfixedin,last_change_time" \
  | jq -r '.bugs[] | "\(.id)  \(.status)/\(.resolution)  fixed-in: \(.cf_versionfixedin // "-")  last-change: \(.last_change_time)"' \
  || echo "(query failed)"
echo

echo "== Latest KWin tags (KDE GitLab, newest first) =="
curl -sf --max-time 30 \
  "https://invent.kde.org/api/v4/projects/plasma%2Fkwin/repository/tags?per_page=15" \
  | jq -r '.[].name' || echo "(query failed)"
echo

echo "== Fedora 44 kwin updates (Bodhi, newest first) =="
curl -sf --max-time 30 -H 'Accept: application/json' \
  "https://bodhi.fedoraproject.org/updates/?packages=kwin&releases=F44&rows_per_page=10" \
  | jq -r '.updates[] | "\(.date_stable // .date_submitted)  \(.alias)  \(.title | [scan("kwin-[0-9][^ ]*")] | join(", "))"' \
  || echo "(query failed)"
echo

echo "== Local journal hits (30 days) =="
journalctl --no-pager --since "30 days ago" --output=short-iso 2>/dev/null \
  | grep -E "Failed to find a working output layer configuration|Applying output configuration failed" \
  | tail -20
echo "(end of matches)"
