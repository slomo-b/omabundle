# Packaging

`PKGBUILD` builds an Arch package that installs omabundle under
`/usr/share/omabundle` and exposes three commands in `/usr/bin`:

```
omabundle
omab
omabundle-handle
```

The scripts resolve their own location with `readlink -f`, so the symlinks
work without patching paths.

## Dependencies

Runtime dependencies are declared in the `PKGBUILD`:

- `bash`, `coreutils`, `util-linux` — shell, `realpath`, `flock`
- `jq` — ledger and metadata
- `libarchive` — `bsdtar` for portable archives and detection
- `file` — icon and content sniffing
- `desktop-file-utils` — `desktop-file-validate`, `update-desktop-database`
- `xdg-utils` — `xdg-mime`
- `shared-mime-info` — `update-mime-database`
- `squashfs-tools` — `unsquashfs`, required for AppImage metadata

Optional: `fuse2` to run AppImages, `flatpak` to install Flatpaks.

## Release steps

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
   `updpkgsums` is in `pacman-contrib`. The committed `SKIP` is only a
   placeholder and must not reach the AUR.
4. Generate the AUR metadata file and test the build:
   ```bash
   makepkg --printsrcinfo > .SRCINFO
   makepkg -si
   ```
5. Verify the installed layout:
   ```bash
   pacman -Ql omabundle
   omabundle --help
   omabundle doctor
   ```
6. Publish to the AUR:
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

## Installing from the AUR

```bash
omarchy pkg aur add omabundle
omabundle integration enable
```

`omarchy pkg aur add` runs `makepkg` and installs with `pacman`; it requests
sudo in the terminal. The integration step is per-user and must not run as
root.
