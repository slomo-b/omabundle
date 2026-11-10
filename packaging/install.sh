#!/usr/bin/env bash
# omabundle user-level installer: no root, no package manager.
#
# Runs from a checked-out or extracted omabundle tree and installs into
# ~/.local. `makepkg -si` (packaging/PKGBUILD) is the preferred install for a
# pacman-managed system; this script exists for machines where that is not
# wanted or not possible.
set -euo pipefail
umask 077

SELF=$(readlink -f -- "${BASH_SOURCE[0]}")
ROOT=$(cd -- "$(dirname -- "$SELF")/.." && pwd)

PREFIX="$HOME/.local"
TARGET="$PREFIX/share/omabundle"
LINKS=(omabundle omab omabundle-handle omabundle-omarchy-remove omabundle-remove-picker)

die()  { printf 'install.sh: %s\n' "$1" >&2; exit 1; }
says() { printf '%s\n' "$1"; }

usage() {
  cat <<'EOF'
Usage: install.sh [install|uninstall|status] [--enable]

Commands:
  install     copy the checked-out omabundle into ~/.local (default)
  uninstall   remove an install.sh-managed copy from ~/.local
  status      show what is currently installed

Options:
  --enable    also run `omabundle integration enable` afterwards
EOF
}

action=install
while (($#)); do
  case $1 in
    install | uninstall | status) action=$1 ;;
    --enable) enable=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
  shift
done

link_target_of() { # cmd
  local link="$PREFIX/bin/$1"
  [[ -L $link ]] || return 1
  readlink -- "$link"
}

is_ours() { # cmd: present and pointing at this install
  [[ $(link_target_of "$1" 2>/dev/null || true) == "$TARGET/bin/$1" ]]
}

cmd_install() {
  mkdir -p "$TARGET/bin" "$TARGET/lib" "$TARGET/adapters" "$PREFIX/bin"

  install -m755 "$ROOT/bin/omabundle" "$TARGET/bin/omabundle"
  install -m755 "$ROOT/bin/omabundle-handle" "$TARGET/bin/omabundle-handle"
  install -m755 "$ROOT/bin/omabundle-omarchy-remove" "$TARGET/bin/omabundle-omarchy-remove"
  install -m755 "$ROOT/bin/omabundle-remove-picker" "$TARGET/bin/omabundle-remove-picker"
  install -m644 "$ROOT"/lib/*.sh "$TARGET/lib/"
  install -m644 "$ROOT"/adapters/*.sh "$TARGET/adapters/"
  install -m644 "$ROOT/LICENSE" "$TARGET/LICENSE"
  install -m644 "$ROOT/README.md" "$TARGET/README.md"
  install -m644 "$ROOT/SECURITY.md" "$TARGET/SECURITY.md"

  for cmd in "${LINKS[@]}"; do
    ln -sfn "$TARGET/bin/$cmd" "$PREFIX/bin/$cmd"
  done

  case ":$PATH:" in
    *":$PREFIX/bin:"*) : ;;
    *) says "Hinweis: $PREFIX/bin ist nicht im PATH." ;;
  esac

  says "omabundle installiert nach $TARGET"
  says "Nächster Schritt: omabundle integration enable"
  if [[ ${enable:-0} == 1 ]]; then
    says
    says "Aktiviere Doppelklick-Integration..."
    "$PREFIX/bin/omabundle" integration enable
  fi
}

cmd_uninstall() {
  for cmd in "${LINKS[@]}"; do
    [[ -L $PREFIX/bin/$cmd ]] || continue
    is_ours "$cmd" || die "$PREFIX/bin/$cmd gehört nicht zu dieser Installation."
  done

  for cmd in "${LINKS[@]}"; do
    is_ours "$cmd" && rm -f -- "$PREFIX/bin/$cmd"
  done
  rm -rf -- "$TARGET"
  says "omabundle entfernt ($TARGET)"
}

cmd_status() {
  if [[ -x $PREFIX/bin/omabundle ]]; then
    says "installiert: $PREFIX/bin/omabundle -> $(readlink -- "$PREFIX/bin/omabundle" 2>/dev/null || echo 'reguläre Datei')"
  else
    says "nicht installiert"
  fi
  for cmd in "${LINKS[@]}"; do
    is_ours "$cmd" && says "$cmd: verwaltet von install.sh"
  done
}

case $action in
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
esac
