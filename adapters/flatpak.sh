# shellcheck shell=bash
# Flatpak adapter: bundles, .flatpakref files and plain app IDs.

require_flatpak() {
  command -v flatpak >/dev/null 2>&1 \
    || die "flatpak ist nicht installiert. Lösung: omarchy pkg add flatpak"
}

flatpak_install_ref() {
  local src=$1
  if [[ $(id -u) -eq 0 ]]; then
    flatpak install --system --noninteractive -y -- "$src"
  else
    flatpak install --user --noninteractive -y -- "$src"
  fi
}

adapter_flatpak_install() {
  local src appid version meta
  src=$(readlink -f -- "$1") || die "Datei nicht gefunden: $1"
  require_flatpak

  case $2 in
    bundle)
      meta=$(bsdtar -xOf "$src" metadata 2>/dev/null || true)
      appid=$(sed -n 's/^name=//p' <<<"$meta" | head -n 1)
      ;;
    ref)
      appid=$(sed -n 's/^Name=//p' "$src" | head -n 1)
      [[ -n $appid ]] || appid=$(sed -n 's/^Url=.*\///p' "$src" | head -n 1)
      ;;
    *) die "interner Fehler: unbekannter Flatpak-Typ $2" ;;
  esac

  [[ -z $appid || $appid =~ ^[A-Za-z0-9._-]+$ ]] || die "ungültige App-ID im Flatpak"
  [[ -z $appid ]] || is_safe_slug "$(slugify "$appid")" || die "ungültige App-ID im Flatpak"

  step "Flatpak: ${appid:-$(basename -- "$src")}"

  if (( OMABUNDLE_DRYRUN )); then
    step "Würde ausführen: flatpak install --user -y $src"
    return 0
  fi

  flatpak_install_ref "$src"

  [[ -n $appid ]] || die "App-ID konnte nicht ermittelt werden"
  version=$(clean_text "$(flatpak info --user "$appid" 2>/dev/null | sed -n 's/^ *Version: *//p' | head -n 1)")
  [[ -n $version ]] || version="-"

  record_and_report "$(jq -n \
    --arg kind flatpak \
    --arg slug "$(slugify "$appid")" \
    --arg name "$appid" \
    --arg version "$version" \
    --arg ref "$appid" \
    --arg source "$src" \
    --arg installed_at "$(date -Iseconds)" \
    '{kind: $kind, slug: $slug, name: $name, version: $version,
      ref: $ref, source: $source, installed_at: $installed_at}')"
}

adapter_flatpak_install_id() {
  local appid=$1 version
  require_flatpak
  step "Flatpak-App-ID: $appid"
  (( OMABUNDLE_DRYRUN )) && { step "Würde ausführen: flatpak install --user flathub $appid"; return 0; }

  flatpak install --user --noninteractive -y flathub "$appid"
  version=$(clean_text "$(flatpak info --user "$appid" 2>/dev/null | sed -n 's/^ *Version: *//p' | head -n 1)")
  [[ -n $version ]] || version="-"

  record_and_report "$(jq -n \
    --arg kind flatpak --arg slug "$(slugify "$appid")" --arg name "$appid" \
    --arg version "$version" --arg ref "$appid" --arg source "flathub" \
    --arg installed_at "$(date -Iseconds)" \
    '{kind: $kind, slug: $slug, name: $name, version: $version,
      ref: $ref, source: $source, installed_at: $installed_at}')"
}
