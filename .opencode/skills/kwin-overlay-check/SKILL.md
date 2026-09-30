---
name: KWin Overlay Workaround Check
description: Check whether the KWin output-layer bug that froze the screen at the plasmalogin handover is fixed upstream, and whether the KWIN_USE_OVERLAYS=0 workaround in tdk-zweej and /etc/environment can be removed. Use when asked to check the KWin workaround, re-check the kwin bug, or decide whether to remove KWIN_USE_OVERLAYS.
---

# KWin Overlay Workaround Check

## Context

On this machine (Fedora Kinoite `tdk-zweej`, AMD Phoenix iGPU, 2880x1920@120Hz internal
panel), KWin 6.7.5 intermittently failed at the plasmalogin -> Plasma session handover:
after login the screen kept showing the wallpaper and the desktop never appeared.
Journal signatures:

- `kwin_wayland: Failed to find a working output layer configuration!`
- `kwin_wayland: Applying output configuration failed!`
- often preceded by `kwin_wayland: Failed to create framebuffer: Invalid argument`

Since 2026-09-30 the workaround `KWIN_USE_OVERLAYS=0` is in place:

- image: `~/git/tdk-zweej/files/system/etc/environment` (copied to `/etc/` by the BlueBuild
  `files` module);
- live machine: `/etc/environment`.

Upstream references: KDE bugs 509635, 512511, 523021, 523022, 517490.
Baseline: last known bad = kwin 6.7.5. Next expected Plasma point release: 6.7.6
(scheduled 2026-10-27 per plasma-devel; verify). Plasma 6.8 was in pre-release (v6.7.9x
tags) as of late September 2026.

## Workflow

### 1. Collect local state

```sh
rpm -q kwin plasma-workspace plasma-login-manager
bootc status 2>/dev/null || rpm-ostree status
cat /etc/environment
cat ~/git/tdk-zweej/files/system/etc/environment
journalctl --no-pager --since "30 days ago" --output=short-iso \
  | grep -E "Failed to find a working output layer configuration|Applying output configuration failed"
```

Rules:

- No journal hits only means the workaround is doing its job; it does **not** prove the
  upstream bug is fixed.
- Record the installed KWin version; it is the baseline for the decision.

### 2. Check upstream status

Run the helper script (paths are relative to the directory containing this SKILL.md):

```sh
bash ~/git/tdk-zweej/.opencode/skills/kwin-overlay-check/scripts/check-upstream.sh
```

Verified REST APIs: KDE Bugzilla, KDE GitLab tags, Fedora Bodhi for F44. It reports:

- bug status / resolution / "Version Fixed/Implemented In" (`cf_versionfixedin`) for the
  tracked bugs;
- newest KWin release tags;
- newest `kwin` build for Fedora 44 (what the next tdk-zweej image will contain).

If curl is unavailable, use web search for the same information:

- KWin 6.7.x / 6.8 changelogs mentioning output layers, overlay planes, or session handover;
- "This Week in Plasma" posts mentioning the bug numbers;
- newer reports with the same journal signature.

### 3. Decide

| Finding | Recommendation |
| --- | --- |
| A newer KWin release available in Fedora stable (or a newer image) contains a fix for this failure class | Update first, then run the removal procedure and monitor |
| New report/commit describing the plasmalogin handover failure with fix version > installed | Preferred removal candidate |
| Only old bugs, `cf_versionfixedin` <= installed (e.g. 509635 -> 6.5.1), nothing new | Keep; re-check after the next point release or in ~2-4 weeks |
| No signal | Keep; suggest next check date |

Never recommend removal based only on a clean local journal.

### 4. Report

Summarize: installed vs latest available KWin; bug statuses with links; local journal hits
since 2026-09-30; recommendation (keep / update first / remove) and next check date.

### 5. Removal procedure (only when recommended)

1. Repo: delete `files/system/etc/environment` (or just the KWIN line if other entries
   exist), commit, push.
2. Machine: remove the line from `/etc/environment` too — local edits win over image
   defaults, so both places must change — then update and reboot.
3. Monitor 2-4 weeks / ~10 boots with the step-1 journal scan. On recurrence: restore the
   workaround in both places and note the KWin version in KDE #523021 (or a new report).
4. Once a full release cycle stays clean, retire this skill: delete
   `.opencode/skills/kwin-overlay-check/` from the repo, or keep it with a "workaround
   removed" banner here.

### Recovery if the screen is stuck on the wallpaper

- `Ctrl+Alt+F3`, then `Ctrl+Alt+F2` — forces KWin to re-apply the output configuration.
- If that fails: on tty3 run `sudo journalctl --sync` (preserves logs), then
  `sudo systemctl restart plasmalogin`, and log in again.
