# Packaging

The primary install path is `install.sh` (user-level, no root). The
`PKGBUILD` remains for pacman users and for a future AUR package:

```
packaging/install.sh          # user-level install into ~/.local
packaging/PKGBUILD            # pacman install into /usr/share/omabundle
packaging/omabundle.install   # pacman install/upgrade messages
```

## `install.sh`

Runs from a checked-out omabundle tree or from the `install.sh` asset that
ships with each release. It never escalates privileges:

```bash
./install.sh            # install into ~/.local
./install.sh --enable   # also run `omabundle integration enable`
./install.sh uninstall  # refuses links that belong to another install
./install.sh status
```

It is idempotent: re-running it upgrades the installed tree in place.

## `PKGBUILD`

Builds an Arch package that installs omabundle under
`/usr/share/omabundle` and exposes three commands in `/usr/bin`:

```
omabundle
omab
omabundle-handle
```

The scripts resolve their own location with `readlink -f`, so the symlinks
work without patching paths.

### Dependencies

- `bash`, `coreutils`, `util-linux` — shell, `realpath`, `flock`
- `jq` — ledger and metadata
- `libarchive` — `bsdtar` for portable archives and detection
- `file` — icon and content sniffing
- `desktop-file-utils` — `desktop-file-validate`, `update-desktop-database`
- `xdg-utils` — `xdg-mime`
- `shared-mime-info` — `update-mime-database`
- `squashfs-tools` — `unsquashfs`, required for AppImage metadata

Optional: `fuse2` to run AppImages, `flatpak` to install Flatpaks.

### AUR release steps

1. Bump `pkgver` in `PKGBUILD` and commit.
2. Tag and push the release:
   ```bash
   git tag -s "v$pkgver" -m "omabundle $pkgver"
   git push origin "v$pkgver"
   ```
3. Fill the source checksum:
   ```bash
   cd packaging
   updpkgsums
   ```
   `updpkgsums` is in `pacman-contrib`.
4. Generate the AUR metadata file and test the build:
   ```bash
   makepkg --printsrcinfo > .SRCINFO
   makepkg -si
   ```
5. Publish to the AUR once registration reopens:
   ```bash
   git clone ssh://aur@aur.archlinux.org/omabundle.git /tmp/aur-omabundle
   cp PKGBUILD .SRCINFO omabundle.install /tmp/aur-omabundle/
   cd /tmp/aur-omabundle
   git add PKGBUILD .SRCINFO omabundle.install
   git commit -m "omabundle $pkgver"
   git push
   ```

Only `PKGBUILD`, `.SRCINFO` and the `.install` file belong in the AUR
repository. The source archive stays on GitHub.
