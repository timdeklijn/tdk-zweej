# tdk-zweej

A custom atomic Fedora image built with [BlueBuild](https://blue-build.org/), based on
[uBlue's `kinoite-main`](https://github.com/ublue-os/main) with KDE Plasma.

**Included:**
- KDE Plasma desktop
- kitty terminal — native RPM from Fedora's repos
- Sublime Text and Sublime Merge
- VLC and Kdenlive — media player and video editor, as native RPMs rather
  than Flatpaks (see notes below)
- Firefox with working H.264 video playback — the base image's `noopenh264`
  stub is replaced with Cisco's real `openh264` codec plus the
  `mozilla-openh264` Firefox plugin and `gstreamer1-plugin-openh264`
  (see notes below)
- Brave Browser
- 1Password (desktop app + `op` CLI)
- Dropbox
- Tailscale
- Local Kubernetes tooling: kind, kubectl, kubectx, Helm, k9s, stern,
  kustomize, and yq; use rootless Podman as kind's provider
- goose — AI agent: Desktop (GUI) baked in from the newest upstream RPM
  at build time, CLI installed per-user at runtime
- [uupd](https://github.com/ublue-os/uupd) — unified auto-updater for the OS image + Flatpaks, on a daily-ish timer
- zsh, set as the default login shell for real user accounts, with the
  [Starship prompt](https://starship.rs/) and [direnv](https://direnv.net/)'s
  hook wired in
- [nushell](https://www.nushell.sh/) (`nu`) — pinned upstream release, not the
  Fedora package (Fedora is stuck at 0.99.1; see notes below)
- [atuin](https://atuin.sh/) — better shell history (SQLite-backed, searchable)
- Steam — via Flatpak
- Signal — via Flatpak
- Slack — via Flatpak (community-packaged)
- Spotify — via Flatpak
- Obsidian — via Flatpak (note-taking app; Obsidian publishes no official
  RPM, and Flatpak is its only first-party Linux package besides
  Snap/AppImage)
- Zed editor, opencode, Pi, the goose CLI, and Determinate Nix — all
  installed at runtime, not baked into the image (see notes below)

## 1. Set this up as your own repo

1. Click **"Use this template"** (or just clone this scaffold) into your own GitHub repo.
2. Rename the image in `recipes/recipe.yml` (the `name:` field) — this becomes
   `ghcr.io/<your-github-username>/<name>`. Do a find-and-replace for
   `tdk-zweej` across `.github/workflows/build-iso.yml` and this
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
2. When it finishes, download **every** numbered
   `tdk-zweej.iso.part-*` file (`part-000`, `part-001`, and so on) plus
   `tdk-zweej.iso.sha256` from the **Releases** page it publishes to. GitHub
   limits individual release assets to 2 GiB, so the ISO is published in parts.
3. In the directory containing those files, combine the parts in order and
   verify the reconstructed ISO. Do not flash the individual parts:

   ```bash
   cat tdk-zweej.iso.part-* > tdk-zweej.iso
   sha256sum --check tdk-zweej.iso.sha256
   ```

4. Flash it to a USB drive with
   [Fedora Media Writer](https://www.fedoraproject.org/en/workstation/download)
   (or `dd`) and boot it. It's a **netinstaller** — small download, boots
   Anaconda, and pulls your actual image from `ghcr.io` over the network
   during install — so the ISO stays tiny and always installs whatever
   you point it at, rather than needing to be rebuilt every time your
   image updates.
5. Walk through the normal Anaconda install steps it presents.

Prefer to build it locally instead of via Actions? The single command is:

```bash
sudo bluebuild generate-iso --iso-name tdk-zweej.iso \
  image ghcr.io/<you>/tdk-zweej:latest
```

See the [ISO how-to guide](https://blue-build.org/how-to/generate-iso/) for details —
under the hood it's a wrapper around
[JasonN3's build-container-installer](https://github.com/JasonN3/build-container-installer/).

## Notes / things worth knowing

- **Local Kubernetes:** `kind`, `kubectl`, `kubectx`, Helm, `k9s`, `stern`,
  `kustomize`, and `yq` are baked into the image. The uBlue base image already
  includes Podman, so use it rootlessly rather than adding Docker or a
  host-level Kubernetes distribution. After booting a rebuilt image, create a
  disposable development cluster with:
  ```bash
  KIND_EXPERIMENTAL_PROVIDER=podman \
    systemd-run --scope --user -p Delegate=yes kind create cluster --name dev
  kubectl cluster-info --context kind-dev
  ```
  `kind` writes the `kind-dev` context to `~/.kube/config`; `kubectl` and Helm
  use it automatically. Delete the cluster and its Podman containers with:
  ```bash
  KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name dev
  ```
  For multi-node testing, pass a kind configuration file to `kind create
  cluster --config <file>`. Rootless kind is appropriate for application and
  manifest development. Use a VM-backed cluster instead if you need privileged
  workloads, block-device mounts, or behavior matching a production node.
- **zsh as default shell:** handled by `set-default-shell-zsh.service`
  (a system unit, runs `/usr/bin/set-default-shell-zsh.sh` as root)
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
- **zsh extras:** direnv, zoxide, and starship are baked into the image as
  packages (starship comes via the `atim/starship` COPR — it was dropped from
  Fedora's own repos after F36). What still has to happen per-user, at first
  login, is wiring their init lines into `~/.zshrc` (there's no build-time
  equivalent of "append a line to every future user's dotfile"), plus
  installing atuin itself, which is a genuinely per-user binary.
  `zsh-extras.service` — a first-login user unit, same reasoning as
  Zed/Dropbox for keeping this runtime rather than build-time — appends one
  clearly marked, project-managed block to `~/.zshrc` holding the user-local
  PATH (`~/.local/bin`, `~/.atuin/bin`) and the init lines for direnv,
  zoxide and starship, then installs atuin if `~/.atuin/bin/atuin` is absent
  and initializes it from that same block. It never overwrites unrelated user
  configuration. The actual logic lives in
  `files/system/usr/bin/setup-zsh-extras.sh` if you want to add more
  later. A `~/.cache/zsh-extras-done` marker makes it a no-op after the first
  successful run, but it retries on next login if it fails partway (e.g. no
  network yet).
- **nushell is a pinned upstream binary, not Fedora's `nushell` RPM.** Fedora
  still ships 0.99.1 in both F44 and F45, while upstream is at 0.116.1
  (Oct 2026) — about a year and 17 releases behind, and nushell's command
  surface and config format move between releases, so the RPM would be a
  shell that no longer matches the current docs. The recipe therefore
  installs the official `x86_64-unknown-linux-gnu` tarball and verifies it
  against the hash from upstream's published `SHA256SUMS` (same pattern as
  kubectx/stern/kanata). Consequences worth knowing:
  - **It only moves when you bump it.** Version and hash are pinned in
    `recipes/recipe.yml`; nothing updates `nu` on its own. Bump all five
    occurrences (two in the URL, the tar member, the install source, the
    hash) from the release page.
  - **The gnu build's only shared libs are `libz`, `libgcc_s`, `libm` and
    `libc`** — all already in the image, so no openssl or LDAP stack gets
    pulled in. It is not a static musl binary; a musl variant also exists
    upstream if that ever matters.
  - **`/usr/bin/nu` is not in `/etc/shells`**, so `chsh -s /usr/bin/nu`
    will refuse. That's deliberate — zsh stays the default via
    `set-default-shell-zsh.service`. Install nushell as a login shell only
    if you actually want to replace zsh, and add it to `/etc/shells` via
    `files/system/etc/shells` first.
  - **Only `nu` is installed, none of the bundled `nu_plugin_*` binaries.**
    Add them to the tar member list if you want `plugin add` targets.
  - **`nu-extras.service` wires the shell up, at login.** Two of the pieces
    can't live in the image, so a user unit does them per-user:
    - **Generated init scripts.** Nushell has no `eval`, so `starship init nu`
      (a script that hardcodes the starship path and probes nu features:
      `job list`, `term size`) and `zoxide init nushell` (commands plus an
      `env_change.PWD` hook) have to exist as files. They land in
      `~/.local/share/nushell/vendor/autoload/starship.nu` (the only path
      nushell autoloads without a config entry) and
      `~/.cache/tdk-zweej/zoxide.nu` (sourced from `config.nu`). The unit
      stamps the nu/starship/zoxide versions they were generated from and
      rewrites them only when one moves, so a `uupd` pull can't leave a stale
      file that fails quietly — steady state is two greps and three
      `--version` calls.
    - **Managed blocks** in `~/.config/nushell/config.nu` (the zoxide
      `source`, `alias vim = nvim`, and the direnv hook — nvim comes from the
      Nix profile, not the image, and nu aliases resolve lazily, so a missing
      nvim fails only when `vim` is actually typed rather than at shell
      startup) and `env.nu` (prepends `~/.local/bin` and `~/.atuin/bin` to
      `PATH`, guarded so repeat logins can't stack duplicates — those are
      where zed, goose, opencode and atuin install). Same contract as the zsh
      block: append once, marked `# >>> tdk-zweej managed >>>`, never
      overwrite anything else, no-op once present. A block you wrote by hand
      is detected and left untouched.
  - **Nu gets a different prompt style from zsh, on purpose.** starship reads
    `$STARSHIP_CONFIG`, so `env.nu` points nu's starship at
    `~/.config/starship-nu.toml` while zsh keeps the stock look (no
    `~/.config/starship.toml` exists, and nothing exports `STARSHIP_CONFIG`
    there, so the two shells ignore each other's styling). The file ships in
    the image at `files/system/usr/share/tdk-zweej/starship-nu.toml` and the
    unit copies it into `$HOME` only if it's missing — after that it is yours,
    so an image bump never clobbers your tweaks. Delete it and log in again to
    restore it, or delete it and drop the `STARSHIP_CONFIG` lines to fall back
    to starship's default prompt.
    - **It's tokyo-night's layout, recoloured green.** Same segment order and
      light→dark ramp, six greens: `#95d5b2` (leading bar, plus the text inside
      the git/language segments), `#40916c` (directory), `#2d6a4f` (git),
      `#1b4332` (languages), `#081c15` (time), `#e9f5ec` (directory text).
    - **Two things were fixed rather than recoloured.** tokyo-night's leading
      segment is `dev-apple` (U+E711) — an Apple logo on every OS — so it is
      `dev-linux` (U+E712) here, same Devicons set as the glyph it replaced, so
      any font that drew the apple draws this, with identical metrics. And
      `#769ff0` did double duty upstream as both the `$directory` background
      *and* the text colour inside the git/language segments; with green those
      two roles need different lightness, so the inner text uses the pale mint
      while the separators keep the medium green (otherwise the text sits at
      ~1.8:1 against its own background).
    - The icons and ``/`` separators need a Nerd Font — kitty already has one.
  - **direnv hooks via `pre_prompt`, not `env_change.PWD`.** The cookbook's
    `env_change.PWD` recipe only ever *loads*: that hook runs before `$env.PWD`
    is updated, so `direnv export json` sees the directory you just left, and
    nothing is reverted when you `cd` out — variables and PATH entries leak into
    the next project. The `pre_prompt` variant (same page, same code) runs after
    the change and both loads and unloads: inside a dir with an `.envrc` the
    variable and PATH entry appear, and after `cd` out both are gone. The cost
    is one `direnv export json` per prompt, which is the trade the cookbook
    itself flags.
  - **atuin is still unwired for nu.** It would need `atuin init nu` written to
    a file and sourced, the same treatment starship and zoxide get, plus a guard
    because the binary only appears after its own first-login installer runs.
- **Steam** comes from Flathub rather than as a native RPM — the standard,
  well-supported way to run it on Fedora Atomic. `kinoite-main` already ships
  Flathub as a system remote, so the `default-flatpaks` module here just
  adds Steam to it; it installs (and self-updates) on boot rather than
  being tied to OS image rebuilds.
- **LibreOffice is a native RPM, chosen the same way as VLC and Kdenlive** —
  only Writer and Calc are installed, since the goal is reading/editing docx
  and xlsx files rather than a full office suite. Fedora's own repos carry it
  at current upstream versions, so the Flatpak (which would pull the ~500 MiB
  freedesktop.org runtime the image doesn't carry) buys nothing. Weak
  dependencies are disabled in the module — they'd add help packs,
  dictionaries, and langpacks — leaving a measured ~346 MiB across 11
  packages, dominated by `libreoffice-core`. The `libreoffice-kf6` package
  supplies the Qt6/KF6 VCL plugin, so LibreOffice renders with native KDE
  dialogs and widget style. Headless conversion works out of the box:
  ```bash
  soffice --headless --convert-to pdf report.docx
  soffice --headless --convert-to csv sheet.xlsx
  ```
- **Firefox gets real H.264 playback** — Fedora Atomic images ship
  `noopenh264`, a stub that satisfies the `libopenh264.so.8` dependency
  but decodes nothing, leaving Firefox unable to play H.264 video. The
  image instead installs Cisco's real `openh264` codec (from the
  `fedora-cisco-openh264` repo, enabled by default in Fedora's repos),
  which `Obsoletes` the stub so dnf replaces it in the same transaction —
  the build-time equivalent of `rpm-ostree override remove noopenh264
  --install openh264 ...` on a live system. `mozilla-openh264` is the
  Firefox GMP plugin that loads it, and `gstreamer1-plugin-openh264`
  covers GStreamer apps.
- **VLC and Kdenlive are native RPMs, not Flatpaks** — the opposite of
  Steam, for concrete reasons rather than preference. Both are in Fedora's
  own repos at the same versions as upstream/Flathub (VLC 3.0.23,
  Kdenlive 26.08.1 at the time of writing), and the base image already
  carries the full ffmpeg and codec stack they use, so native installs get
  complete codec and hardware-acceleration support. Kinoite already ships
  Qt6/KF6, so the marginal cost is small (~21 MiB for VLC, ~137 MiB for
  Kdenlive); the Flatpaks would additionally pull the KDE 5.15 (VLC) and
  KDE 6.10 (Kdenlive) runtimes for no version benefit. The trade-off is
  that updates arrive with the OS image (staged by `uupd`, applied on
  reboot) rather than updating live in a sandbox. VLC's optional
  `vlc-plugins-freeworld` RPM from RPM Fusion is *not* installed — the
  image's full ffmpeg build covers the common formats; add it to the
  "Media apps" dnf module if you need something exotic.
- **KDE Plasma:** provided by the `kinoite-main` base image.
- **Auto-updates run via `uupd`.** `kinoite-main` doesn't enable any auto-updater
  out of the box, so this recipe installs `uupd` from uBlue's own `ublue-os/packages`
  COPR (the `bling` module *looks* like the natural place for this, but it
  only offers the deprecated `ublue-update`, not `uupd` — hence the separate
  `dnf` module). `uupd.timer` runs roughly every 6 hours and pulls a new OS
  image (if your GitHub Action has built one) plus refreshes Flatpaks in one
  coordinated pass, staging the OS update for your next reboot — nothing
  applies live or force-reboots you. Since `kinoite-main` inherits an
  `AutomaticUpdatePolicy=stage` default from upstream uBlue config, which
  would otherwise have `rpm-ostreed` *also* try to stage updates on its own
  schedule, the recipe ships an `/etc/rpm-ostreed.conf` override
  (`files/system/etc/rpm-ostreed.conf`) setting that to `none`, and disables
  `rpm-ostreed-automatic.timer` / masks `bootc-fetch-apply-updates.service`
  so `uupd` is the one and only update path.
  - Check status any time with `uupd --help` or by watching
    `systemctl status uupd.timer` / `journalctl -u uupd.service`.
  - Homebrew is not used by this image, so its `uupd` module is disabled in
    `/etc/uupd/config.json`.
  - Distrobox containers are deliberately left out of `uupd`'s scope by
    default (they're mutable and user-managed) — see the flag in `uupd`'s
    own README if you want to opt them in.
- **Nix and Zed are both installed at runtime, not build time.** The image
  includes an empty, mode-000 `/nix` mount point because Fedora Atomic cannot
  create new top-level directories after boot. On first boot,
  `determinate-nix-installer.service` uses Determinate's **ostree** planner to
  bind-mount persistent `/var/home/nix` at `/nix` and install Nix there. Zed
  doesn't have that
  constraint (its installer just drops files in `~/.local`), but since it's
  inherently a per-user, per-home install, baking it into the image doesn't
  buy you much either — so `zed-installer.service` (a **user** unit) runs
  Zed's own `install.sh` on first login instead, once per user. Both units
  are self-skipping: they check whether the thing they install already
  exists before doing anything, so they're harmless no-ops on every boot/
  login after the first. If you'd rather have Zed baked into the image
  instead, it's available via [Terra](https://terrapkg.com) as `zed` — add a
  `dnf` module pointing at Terra's repo (the image no longer configures it).
  opencode follows the same runtime pattern for the same reason: it's a
  per-user install that self-updates, so `opencode-installer.service` (a
  user unit) runs its own `install.sh` on first login, once per user. It
  runs with `--no-modify-path` so `~/.zshrc` stays under the
  `tdk-zweej managed` block, then symlinks `~/.opencode/bin/opencode` into
  `~/.local/bin` — where Zed's installer also lands, and which is already
  on PATH.
  Pi follows the same pattern for the same reason: it's a per-user install
  that self-updates (its managed install lives under
  `~/.pi/agent/install` and updates with `pi update`), so
  `pi-installer.service` (a user unit) runs Pi's installer on first login,
  once per user, then symlinks `~/.pi/agent/bin/pi` into `~/.local/bin` the
  same way. The installer only prompts and edits shell profiles when a
  terminal is attached, so `~/.zshrc` stays under the `tdk-zweej managed`
  block. One real difference from opencode and Zed: Pi's installer needs
  Node.js 22.19+ and npm, so the image bakes in `nodejs24-bin` and
  `nodejs24-npm-bin` — Fedora 44 ships Node as parallel-installable version
  streams, and only the `-bin` subpackages put `node`/`npm`/`npx` on PATH.
  Pi itself is still not baked in.
- **goose is split in two: Desktop baked in, CLI per-user.** There is no
  goose dnf repo and no Flathub listing (upstream publishes only a `.deb`,
  an `.rpm` and a Flatpak *bundle* as release assets), so the GUI is
  installed from upstream's release RPM. No version is pinned: every build
  resolves the newest release, which means your nightly CI + `uupd` is what
  advances the GUI. The tag is read from the `/releases/latest` redirect
  rather than the GitHub API, so CI never trips the unauthenticated rate
  limit, and because upstream publishes no checksums the build logs the
  SHA-256 of the RPM it installed instead of verifying one. That is the
  trade: reproducible builds gave way to tracking upstream — worth knowing,
  and reversible by pinning the version and hash again. Note the upstream
  repo moved from `block/goose` to `aaif-goose/goose`. It costs ~146 MiB
  download / ~515 MiB installed (it's Electron).
  The GUI does not update itself — Electron auto-update needs an AppImage —
  so new GUI versions arrive through the nightly rebuild, not from inside
  the app.
  The CLI follows the Zed/opencode/Pi pattern instead:
  `goose-installer.service` (a user unit) runs upstream's `download_cli.sh`
  on first login, once per user, into `~/.local/bin/goose` — deliberately,
  because `goose update` rewrites its own binary and `/usr` is read-only.
  Both halves share the same provider/model config in `~/.config/goose`, so
  configuring one configures the other. Neither prompts during the build or
  first login: run `goose configure` (or use the Desktop welcome screen)
  once to pick a provider.
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
- **Emacs is installed but does not start automatically.** The `emacs` RPM is
  in the image; there is no XDG autostart entry. Start the daemon yourself
  with `emacs --daemon` (or let `emacsclient -c -a ""` fall back to spawning
  it), then connect with `emacsclient -c`; close a frame with `C-x 5 0` and
  stop the daemon with `emacsclient -e '(kill-emacs)'`. If you want it at
  login, prefer the `emacs.service` user unit (`systemctl --user enable
  --now emacs`) over an autostart file, so the socket has a single owner.
- Run `bluebuild validate recipes/recipe.yml` and
  `bluebuild build recipes/recipe.yml` locally before pushing, to catch
  mistakes early — see the
  [local build guide](https://blue-build.org/how-to/local/).
