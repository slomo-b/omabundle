# shellcheck shell=bash
# Format detection by content, not by file name.

hex4() { head -c 4 -- "$1" | od -An -tx1 | tr -d ' \n'; }
hex8() { head -c 8 -- "$1" | od -An -tx1 | tr -d ' \n'; }

# bytes 8..10 of an ELF AppImage are "AI\x01" (type 1) or "AI\x02" (type 2)
appimage_marker() {
  dd if="$1" bs=1 skip=8 count=3 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

detect_kind() {
  local f=$1 listing=''

  [[ -f $f ]] || return 1
  [[ -r $f ]] || return 1

  # .deb: "!<arch>\n"
  [[ $(hex8 "$f") == 213c617263683e0a ]] && { printf 'deb'; return; }
  # .rpm: ED AB EE DB
  [[ $(hex4 "$f") == edabeedb ]] && { printf 'rpm'; return; }
  # bare squashfs at offset 0 is how snaps are packaged (AppImages carry a
  # runtime first, so their "hsqs" sits further in)
  [[ $(hex4 "$f") == 68737173 ]] && { printf 'snap'; return; }

  if [[ $(hex4 "$f") == 7f454c46 ]]; then
    case $(appimage_marker "$f") in
      414901|414902) printf 'appimage'; return ;;
    esac
    # squashfs payload without the AI marker: still an AppImage in practice
    if ( set +o pipefail; head -c 1048576 -- "$f" | grep -qa 'hsqs' ); then
      printf 'appimage'; return
    fi
    printf 'elf'; return
  fi

  # Cap the listing: a crafted archive with millions of entries must not be
  # able to balloon this shell's memory.
  if listing=$( ( set +o pipefail; bsdtar -tf "$f" 2>/dev/null | head -n 5000 ) ) \
    && [[ -n $listing ]]; then
    case $listing in
      *"meta/snap.yaml"*) printf 'snap'; return ;;
    esac
    if grep -qx '.PKGINFO' <<<"$listing" \
      && bsdtar -xOf "$f" .PKGINFO 2>/dev/null | grep -q '^pkgname = '; then
      printf 'archpkg'; return
    fi
    if grep -qx 'metadata' <<<"$listing" \
      && bsdtar -xOf "$f" metadata 2>/dev/null | grep -q '^\[Application\]'; then
      printf 'flatpak'; return
    fi
    printf 'portable'; return
  fi

  if [[ $f == *.flatpakref ]] \
    || ( set +o pipefail; head -c 4096 -- "$f" | grep -qa '^\[Flatpak Ref\]' ); then
    printf 'flatpakref'; return
  fi

  # self-extracting shell installer: recognised, deliberately refused
  if ( set +o pipefail; head -c 64 -- "$f" | grep -qa '^#!.*\(sh\|bash\)' ); then
    printf 'run'; return
  fi

  printf 'unknown'
}

detect_reason() {
  case $1 in
    appimage) printf 'AppImage – wird nativ installiert (fuse2 nur zum Starten nötig).' ;;
    archpkg) printf 'Arch-Paket – Installation über pacman (sudo, im Terminal).' ;;
    flatpak | flatpakref) printf 'Flatpak – Installation über flatpak (--user).' ;;
    portable) printf 'Portables Archiv – wird nach ~/.local/opt entpackt.' ;;
    deb) printf 'Debian/Ubuntu-Paket – Arch nutzt pacman. Nächster Schritt: distrobox oder debtap.' ;;
    rpm) printf 'Fedora/RHEL-Paket – Arch nutzt pacman. Nächster Schritt: distrobox.' ;;
    snap) printf 'snapd ist auf Arch/Omarchy nicht unterstützt.' ;;
    run) printf 'Selbstentpackender Installer wird bewusst nicht ausgeführt (schreibt unkontrolliert ins System).' ;;
    elf) printf 'Nackte Binärdatei ohne Metadaten – bitte als Tarball oder AppImage beziehen.' ;;
    *) printf 'Format nicht erkannt.' ;;
  esac
}
