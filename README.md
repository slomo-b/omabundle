# omabundle

omabundle installs portable Linux applications natively on Omarchy
(Arch Linux) and removes them cleanly again. No containers, no file-format
conversion, no foreign package manager, **no GUI** — after setup nothing
outside your user directories changes and nothing keeps running.

```
omabundle install ~/Downloads/Obsidian-1.5.3.AppImage
omabundle install ./app.flatpak          # or .flatpakref, or org.gimp.GIMP
omabundle list
omabundle remove obsidian
omabundle doctor
```

## What can be installed

| File | Detection | Install location |
|---|---|---|
| `.AppImage` (Type 1/2) | ELF plus `AI\x01`/`AI\x02` or SquashFS | `~/.local/opt/<slug>/<version>/` |
| `.pkg.tar.{zst,xz,gz}` | `.PKGINFO` inside the tar | `pacman` in a visible terminal |
| `.flatpak` | `metadata` with `[Application]` | Flatpak |
| `.flatpakref` | `[Flatpak Ref]` file | Flatpak |
| Flatpak app id | e.g. `org.gimp.GIMP` | Flatpak |
| `.tar.{zst,xz,gz}` or other archives `bsdtar` can read, containing `AppRun`/`bin/` | heuristic scan | `~/.local/opt/<slug>/<version>/app/` |

Deliberately unsupported — with an explanation rather than a silent error:

| Format | Reason |
|---|---|
| `.deb`, `.rpm` | needs `distrobox` or `debtap` |
| `.snap` | not supported on Arch/Omarchy |
| `.run` (self-extracting) | writes into the system at will |
| bare ELF / executable | no metadata; please use a tarball or AppImage |

`omabundle detect <file>` names the format and the reason, without changing
anything.

## Installing the tool

### GitHub with `install.sh` (recommended)

```bash
git clone -b v0.1.2 --depth 1 https://github.com/slomo-b/omabundle
cd omabundle/packaging
./install.sh              # installs into ~/.local, no root
omabundle integration enable   # set up double-click installation
```

Or fetch just `install.sh` from the release asset — a `.sha256` file ships
with the release:

```bash
curl -LO https://github.com/slomo-b/omabundle/releases/download/v0.1.2/install.sh
sha256sum install.sh      # 7d66bda3fb68f8edbcb386a5a39ae2e7cf6fdf3ed8a0b63d408a31b0528da2ab
bash install.sh           # never a curl | bash pipe, always run locally
omabundle integration enable
```

`install.sh` copies the scripts into `~/.local/share/omabundle` and creates
links for `omabundle`, `omab` and `omabundle-handle` in `~/.local/bin`. With
`./install.sh --enable` the double-click integration is set up right away;
`./install.sh uninstall` removes everything again. No privileged command is
ever run. The double-click integration resolves the handler through `PATH`
(see `bin/omabundle` → `integration_handler_path`).

### pacman via `makepkg`

```bash
git clone -b v0.1.2 --depth 1 https://github.com/slomo-b/omabundle
cd omabundle/packaging
makepkg -si               # system-wide install through pacman, sudo in terminal
omabundle integration enable   # then run as your normal user
```

Uninstall: `sudo pacman -Rns omabundle`, then `omabundle integration disable`.

### AUR

An AUR package will follow once AUR registration reopens. `packaging/PKGBUILD`
is ready and `packaging/README.md` documents the exact steps.

## Double-click installation

```bash
omabundle integration enable
omabundle integration status
omabundle integration disable
```

| File | Behavior |
|---|---|
| `.AppImage`, portable archives | installed silently, short notification; clicking the notification starts the app |
| `.flatpak`, `.flatpakref` | same |
| `.pkg.tar.*` | opens a visible terminal with a password prompt, because `pacman` needs sudo |
| `.deb`, `.rpm`, `.snap`, `.run` | notification with the reason, nothing else |

Deliberately **not** registered as a handler: `.tar.gz`, `.zip`, `.zst` and
bare executables, otherwise omabundle would take over every downloaded file.
For these formats use `omabundle install` (or `omabundle detect`).

## What a run does

1. **Detection** by magic bytes, never by the file name.
2. **Metadata read** (Name, Comment, categories, MIME types, icon) with
   `unsquashfs -cat` or from `.desktop` files — never by executing the
   downloaded file.
3. **Install into** `~/.local/opt/<slug>/<version>/` plus a symlink in
   `~/.local/bin/<slug>`.
4. **Integrate**: `.desktop` entry (validated with `desktop-file-validate`),
   icon into `~/.local/share/icons/hicolor`, cache refresh. Entries declare
   the app's own MIME types and never overwrite your default handlers — a
   bundle cannot silently take over PDFs.
5. **Ledger** in `~/.local/state/omabundle/db.json` — only what is recorded
   there can be removed again.

This makes removal exact: `omabundle remove <slug>` deletes only what
`install` created. `omabundle doctor` reports dead symlinks, missing icons
and stale ledger entries.

## Command line

```bash
omabundle install <file|app-id>   # AppImage, .pkg.tar.*, Flatpak, tarball
omabundle list                    # show the ledger
omabundle remove <slug>           # clean uninstall
omabundle doctor                  # check the whole installation
omabundle detect <file>           # detect the format, touch nothing
omabundle integration enable|status|disable
```

Options: `-n --dry-run` (changes nothing, not even `chmod` on the source
file), `--json` (machine-readable output), `-y --yes` (skip prompts,
important for pacman runs).

## Filesystem

| Path | Purpose |
|---|---|
| `~/.local/opt/<slug>/<version>/` | installed apps |
| `~/.local/bin/<slug>` | command to start the app |
| `~/.local/share/applications/<slug>.desktop` | menu entry |
| `~/.local/share/icons/hicolor/.../<slug>.png` / `svg` | icon |
| `~/.local/share/applications/omabundle-handle.desktop` | the invisible handler |
| `~/.local/share/mime/packages/omabundle.xml` | `application/x-appimage` and friends |
| `~/.config/mimeapps.list` | the 9 registered MIME types |
| `~/.local/state/omabundle/db.json` | ledger |
| `~/.local/state/omabundle/handle.log` | handler log |

## Security

The full audit is in [SECURITY.md](SECURITY.md): threat model, findings
(F1–F29), fixes and remaining risks. Highlights:

- **No code from the package is executed at install time.** AppImage metadata
  is read with `unsquashfs -cat`, not by running the AppImage.
- **Free-text fields** (Name, Comment, categories, MIME types) are filtered
  and sanitized before they end up in `.desktop` files or notifications.
- **Ledger paths** are checked against `~/.local/opt` with `realpath`; a
  tampered entry cannot point outside.
- **Archives** are capped by file count and total size; AppImage metadata is
  read per-entry with a size limit.
- **Privileges**: `sudo`/`pacman` run only inside a visible terminal after
  confirmation. The background handler never runs `sudo`.
- **Clicking the notification** starts the program through an argument
  array, not a shell string.

## Background operation

omabundle deliberately has **no graphical interface**. There are exactly two
paths:

1. **Double-click** a downloaded file in your file manager — after a one-time
   `omabundle integration enable`, installs happen silently in the
   background. The success notification can be clicked to launch what was
   just installed.
2. **Command line** for everything else (see above).

No window, no panel, no daemon, no plugin inside the `omarchy-shell`
process.

## License

MIT.

## Roadmap

- [x] P0: detection, AppImage, Arch package, Flatpak, portable, ledger, remove, doctor
- [x] P1: double-click installation (MIME handler, silent + notification)
- [x] Security audit: F1–F29
- [x] `install.sh` for installs without pacman
- [ ] P2: `omabundle update` (only when the source URL is known)
- [ ] P3: `.deb`/`.rpm` adapter with a distrobox hint
- [ ] AUR package once registration reopens
