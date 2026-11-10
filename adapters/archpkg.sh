# shellcheck shell=bash
# Arch package adapter: hands the file to pacman, which is the only thing
# allowed to touch the system package database.

adapter_archpkg_install() {
  local src info pkgname pkgver pkgdesc
  src=$(readlink -f -- "$1") || die "Datei nicht gefunden: $1"
  need bsdtar

  info=$(bsdtar -xOf "$src" .PKGINFO 2>/dev/null) \
    || die "kein .PKGINFO im Paket – kein gültiges Arch-Paket"
  pkgname=$(sed -n 's/^pkgname = //p' <<<"$info" | head -n 1)
  pkgver=$(clean_text "$(sed -n 's/^pkgver = //p' <<<"$info" | head -n 1)")
  pkgdesc=$(clean_text "$(sed -n 's/^pkgdesc = //p' <<<"$info" | head -n 1)")
  [[ $pkgname =~ ^[a-z0-9@._+-]+$ ]] || die "ungültiger Paketname im .PKGINFO"
  [[ -n $pkgname ]] || die "Paketname nicht lesbar"
  [[ $pkgver =~ ^[A-Za-z0-9._+~:-]*$ ]] || pkgver="-"

  step "Arch-Paket: $pkgname $pkgver"
  warn "Lokales Paket – pacman prüft die Signatur, nicht die Herkunft."

  if (( OMABUNDLE_DRYRUN )); then
    step "Würde ausführen: sudo pacman -U --needed $src"
    return 0
  fi

  confirm "pacman -U $pkgname $pkgver ausführen (sudo)?" || die "abgebrochen"

  if [[ $(id -u) -eq 0 ]]; then
    pacman -U --needed --noconfirm -- "$src"
  else
    sudo pacman -U --needed --noconfirm -- "$src"
  fi

  pacman -Q -- "$pkgname" >/dev/null 2>&1 \
    || die "pacman meldet Erfolg, aber $pkgname ist nicht installiert"

  record_and_report "$(jq -n \
    --arg kind archpkg \
    --arg slug "$(slugify "$pkgname")" \
    --arg name "$pkgname" \
    --arg version "$pkgver" \
    --arg pkg "$pkgname" \
    --arg desc "$pkgdesc" \
    --arg source "$src" \
    --arg installed_at "$(date -Iseconds)" \
    '{kind: $kind, slug: $slug, name: $name, version: $version,
      pkg: $pkg, description: $desc, source: $source,
      installed_at: $installed_at}')"
}
