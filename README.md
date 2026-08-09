# my-sway-distro

A custom atomic Fedora image built with [BlueBuild](https://blue-build.org/), based on
[uBlue's `base-main`](https://github.com/ublue-os/main) with Sway + Noctalia bolted on top.

**Included:**
- Sway (+ swaybg, swaylock, swayidle, foot terminal, portals, polkit agent)
- SDDM as the login manager (Noctalia doesn't ship a greeter yet)
- [Noctalia shell](https://docs.noctalia.dev/) (Quickshell-based) — via the Terra repo
- Ghostty — via Terra (kept `foot` too, as a tiny zero-dependency fallback terminal)
- Brave Browser
- 1Password (desktop app + `op` CLI)
- Dropbox
- Tailscale
- [uupd](https://github.com/ublue-os/uupd) — unified auto-updater for the OS image + Flatpaks, on a daily-ish timer
- zsh, set as the default login shell for real user accounts, with the
  [Starship prompt](https://starship.rs/) and [direnv](https://direnv.net/)'s
  hook wired in
- [atuin](https://atuin.sh/) — better shell history (SQLite-backed, searchable)
- Steam — via Flatpak
- Signal — via Flatpak
- Slack — via Flatpak (community-packaged)
- Zed editor and Determinate Nix — both installed at runtime, not baked into the image (see notes below)

## 1. Set this up as your own repo

1. Click **"Use this template"** (or just clone this scaffold) into your own GitHub repo.
2. Rename the image in `recipes/recipe.yml` (the `name:` field) — this becomes
   `ghcr.io/<your-github-username>/<name>`. Do a find-and-replace for
   `my-sway-distro` across `.github/workflows/build-iso.yml` and this
   README too, since those reference the image name directly.
3. Set up [container signing with cosign](https://blue-build.org/how-to/cosign/):
   ```
   cosign generate-key-pair
   ```
   Add `cosign.pub` to the repo root, and add the private key content as a repo
   secret named `SIGNING_SECRET`.
4. Push to GitHub and enable Actions on the repo. The workflow in
   `.github/workflows/build.yml` will build the image and push it to
   `ghcr.io/<you>/<name>:latest`.

## 2. Install / rebase to it

From an existing Fedora Atomic install (Silverblue, Kinoite, or any uBlue image):

```bash
# Rebase to the unsigned image first to pick up signing keys/policy
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/<you>/<name>:latest
sudo systemctl reboot

# Then rebase to the signed image
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/<you>/<name>:latest
sudo systemctl reboot
```

To install fresh on bare metal, use the bootable installer ISO:

1. In your repo on GitHub, go to **Actions → build-iso → Run workflow**
   (or just push a `v1.0.0`-style tag — that also triggers it).
2. When it finishes, grab `my-sway-distro.iso` from the **Releases** page
   it publishes to.
3. Flash it to a USB drive with
   [Fedora Media Writer](https://www.fedoraproject.org/en/workstation/download)
   (or `dd`) and boot it. It's a **netinstaller** — small download, boots
   Anaconda, and pulls your actual image from `ghcr.io` over the network
   during install — so the ISO stays tiny and always installs whatever
   you point it at, rather than needing to be rebuilt every time your
   image updates.
4. Walk through the normal Anaconda install steps it presents.

Prefer to build it locally instead of via Actions? The single command is:

```bash
sudo bluebuild generate-iso --iso-name my-sway-distro.iso \
  image ghcr.io/<you>/my-sway-distro:latest
```

See the [ISO how-to guide](https://blue-build.org/how-to/generate-iso/) for details —
under the hood it's a wrapper around
[JasonN3's build-container-installer](https://github.com/JasonN3/build-container-installer/).

## Notes / things worth knowing

- **Sway base image:** uBlue removed its dedicated `sway-atomic` image, so this
  builds Sway from scratch on `base-main`. It's a minimal, DIY assembly — you'll
  likely want to tweak the package list (add a wallpaper tool, notification
  daemon if you don't want Noctalia's, etc.) once you've booted it once.
- **Ghostty is installed but not wired up as the default terminal yet** —
  this recipe doesn't ship a `~/.config/sway/config`, so set your terminal
  keybind (e.g. `bindsym $mod+Return exec ghostty`) once you've booted and
  are editing your own Sway config.
- **zsh as default shell:** handled by `set-default-shell-zsh.service`
  (a system unit, runs `/usr/local/bin/set-default-shell-zsh.sh` as root)
  rather than the more commonly suggested `/etc/default/useradd` approach.
  The reason: that file only affects accounts created via the `useradd`
  command, and it's not guaranteed that Anaconda's own account-creation
  step during a fresh ISO install goes through it — so a declarative
  config-file tweak could silently not apply depending on install path.
  `usermod` run directly against every real user account (UID 1000-59999)
  at boot works regardless of *how* the account got created, and needs no
  password prompt (unlike `chsh`), so it's safe to run non-interactively.
  It's idempotent, so it costs nothing extra on later boots. One caveat:
  like any shell change, it takes effect on next login, not the current
  session.
- **direnv, starship, and atuin:** direnv and starship are both baked into
  the image as packages (starship comes via the `atim/starship` COPR — it
  was dropped from Fedora's own repos after F36). What still has to happen
  per-user, at first login, is wiring their init lines into `~/.zshrc`
  (there's no build-time equivalent of "append a line to every future
  user's dotfile"), plus installing atuin itself, which is a genuinely
  per-user binary. All three are handled by `zsh-extras.service`, a
  first-login user unit — same reasoning as Zed/Dropbox for keeping this
  runtime rather than build-time. The actual logic lives in
  `files/system/usr/local/bin/setup-zsh-extras.sh` if you want to add more
  later. It marks itself done in `~/.cache/zsh-extras-done` so it's a
  no-op after the first successful run, but retries on next login if it
  fails partway (e.g. no network yet).
- **Steam** comes from Flathub rather than as a native RPM — the standard,
  well-supported way to run it on Fedora Atomic. `base-main` already ships
  Flathub as a system remote, so the `default-flatpaks` module here just
  adds Steam to it; it installs (and self-updates) on boot rather than
  being tied to OS image rebuilds.
- **Noctalia:** installed from the [Terra repo](https://terrapkg.com), which is
  third-party/community-maintained (not built by the Noctalia team). If your
  Fedora version is 44+, it's also in the official Fedora repos directly — you
  can drop the Terra dependency for it in that case.
- **Auto-updates run via `uupd`.** `base-main` doesn't enable any auto-updater
  out of the box, so this recipe installs `uupd` from uBlue's own `ublue-os/packages`
  COPR (the `bling` module *looks* like the natural place for this, but it
  only offers the deprecated `ublue-update`, not `uupd` — hence the separate
  `dnf` module). `uupd.timer` runs roughly every 6 hours and pulls a new OS
  image (if your GitHub Action has built one) plus refreshes Flatpaks in one
  coordinated pass, staging the OS update for your next reboot — nothing
  applies live or force-reboots you. Since `base-main` inherits an
  `AutomaticUpdatePolicy=stage` default from upstream uBlue config, which
  would otherwise have `rpm-ostreed` *also* try to stage updates on its own
  schedule, the recipe ships an `/etc/rpm-ostreed.conf` override
  (`files/system/etc/rpm-ostreed.conf`) setting that to `none`, and disables
  `rpm-ostreed-automatic.timer` / masks `bootc-fetch-apply-updates.service`
  so `uupd` is the one and only update path.
  - Check status any time with `uupd --help` or by watching
    `systemctl status uupd.timer` / `journalctl -u uupd.service`.
  - Distrobox containers are deliberately left out of `uupd`'s scope by
    default (they're mutable and user-managed) — see the flag in `uupd`'s
    own README if you want to opt them in.
- **Nix and Zed are both installed at runtime, not build time.** Nix genuinely
  can't be installed cleanly at *container build time* on an OSTree/bootc
  image, because `/nix` needs to persist across deployments the way `/etc`
  and `/var` do, and that's only set up once the system is actually booted.
  So `determinate-nix-installer.service` (a **system** unit) runs once on
  first boot and installs it live — this is the same approach Determinate
  Systems documents for ostree-based distros. Zed doesn't have that
  constraint (its installer just drops files in `~/.local`), but since it's
  inherently a per-user, per-home install, baking it into the image doesn't
  buy you much either — so `zed-installer.service` (a **user** unit) runs
  Zed's own `install.sh` on first login instead, once per user. Both units
  are self-skipping: they check whether the thing they install already
  exists before doing anything, so they're harmless no-ops on every boot/
  login after the first. If you'd rather have Zed baked into the image
  instead, it's available via [Terra](https://terrapkg.com) as `zed` — just
  add it back to the `noctalia-shell` dnf module.
- If you're on Fedora 44+ and don't need flakes/Determinate's extras, the
  native `nix` dnf package is a simpler build-time alternative to the
  first-boot installer — just add it to the main `dnf` module instead.
- **1Password:** there's no hosted `.repo` file from 1Password, so one is
  vendored in `files/dnf/1password.repo` and referenced by filename in the
  recipe (per BlueBuild's convention for local repo files).
- **Dropbox:** comes from RPM Fusion's nonfree repo as `nautilus-dropbox`
  (the package name is legacy — it works fine without Nautilus/GNOME
  installed). The RPM only ships the `dropbox` CLI wrapper; the actual
  proprietary daemon binary gets downloaded to `~/.dropbox-dist` on first
  run, which is normal for this client and not an atomic-image issue since
  it lives in your regular writable home directory. `dropbox.service`
  handles starting it at login (`Type=forking`, since `dropbox start`
  daemonizes and returns — a plain `Type=simple` unit would think it died
  immediately). You'll only see its tray icon if your bar/shell has a
  systray widget enabled — Noctalia has one, just make sure it's on.
- Run `bluebuild validate recipes/recipe.yml` and
  `bluebuild build recipes/recipe.yml` locally before pushing, to catch
  mistakes early — see the
  [local build guide](https://blue-build.org/how-to/local/).
