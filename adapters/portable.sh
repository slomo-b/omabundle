# shellcheck shell=bash
# Portable adapter: tarballs/zip that ship a runnable tree (AppRun, bin/…).

find_launcher() {
  local root=$1 c
  if [[ -f $root/AppRun && -x $root/AppRun ]]; then
    printf '%s' "$root/AppRun"
    return
  fi
  for c in "$root"/*.sh "$root"/bin/* "$root"/usr/bin/*; do
    [[ -f $c && -x $c ]] || continue
    case $c in
      *.so|*.so.*|*.a) continue ;;
    esac
    printf '%s' "$c"
    return
  done
  c=$( ( set +o pipefail; find "$root" -maxdepth 2 -type f -perm -u+x \
    ! -path '*/lib/*' ! -path '*/lib64/*' ! -path '*/share/*' -print 2>/dev/null | head -n 1 ) ) || true
  printf '%s' "$c"
}

adapter_portable_install() {
  local src work root launcher rel dfile name comment categories mime
  local slug version prefix binary icon icon_src count derived launcher_real work_real
  local entries total avail

  src=$(readlink -f -- "$1") || die "Datei nicht gefunden: $1"
  need bsdtar

  # Bound resource use before writing anything: a crafted archive must not be
  # able to exhaust inodes or fill the disk just by being double-clicked.
  entries=$( ( set +o pipefail; bsdtar -tf "$src" 2>/dev/null | head -n 20001 | wc -l ) ) || true
  (( entries <= 20000 )) || die "Archiv enthält zu viele Dateien (mehr als 20000)"
  total=$( ( set +o pipefail; bsdtar -tvf "$src" 2>/dev/null | head -n 20001 \
    | awk '{ s += $5 } END { printf "%.0f", s }' ) ) || true
  [[ $total =~ ^[0-9]+$ ]] || total=0
  avail=$(df -B1 --output=avail "${TMPDIR:-/tmp}" 2>/dev/null | tail -n 1 | tr -d ' ') || avail=0
  if [[ $avail =~ ^[0-9]+$ ]] && (( total > 0 && total + 104857600 > avail )); then
    die "Archiv ist zu groß für den freien Platz (${total} Bytes benötigt, ${avail} verfügbar)"
  fi

  step "Archiv erkannt, entpacke zum Prüfen"
  mktempdir work
  work_real=$(readlink -f -- "$work") || die "Arbeitsordner nicht auflösbar"
  bsdtar -xf "$src" -C "$work" || die "Archiv konnte nicht entpackt werden"

  count=$(find "$work" -mindepth 1 -maxdepth 1 | wc -l)
  root=$(first_line find "$work" -mindepth 1 -maxdepth 1)
  if [[ $count -ne 1 || ! -d $root || -L $root ]]; then
    root=$work
  fi
  # A single top-level symlink must not redirect the scan/copy to $HOME or /.
  root=$(readlink -f -- "$root") || die "Archivwurzel nicht auflösbar"
  [[ $root == "$work_real" || $root == "$work_real"/* ]] \
    || die "Archiv verweist aus dem Extraktionsordner heraus"

  launcher=$(find_launcher "$root")
  [[ -n $launcher ]] || die "keine ausführbare Datei im Archiv gefunden"
  launcher_real=$(readlink -f -- "$launcher") || die "Startprogramm nicht auflösbar"
  [[ $launcher_real == "$root"/* ]] \
    || die "Startprogramm verweist aus dem Archiv heraus"
  launcher=$launcher_real

  dfile=$( ( set +o pipefail; find "$root" -maxdepth 4 -name '*.desktop' -type f | head -n 1 ) ) || true

  name=$(clean_text "$(desktop_field "$dfile" Name)")
  comment=$(clean_text "$(desktop_field "$dfile" Comment)")
  categories=$(desktop_field "$dfile" Categories)
  mime=$(desktop_field "$dfile" MimeType)

  [[ -n $name ]] || {
    if [[ $root != "$work_real" ]]; then
      derived=$(basename -- "$root")
    else
      derived=$src
    fi
    name=$(name_from_file "$derived")
  }

  slug=$(slugify "$name")
  is_safe_slug "$slug" || slug=$(slugify "$(name_from_file "$src")")
  is_safe_slug "$slug" || die "kein gültiger Programmname ableitbar"
  version=$(version_from_name "$src")

  rel=${launcher#"$root"/}
  prefix="$OMABUNDLE_PREFIX/$slug/$version"
  binary="$prefix/app/$rel"

  if (( OMABUNDLE_DRYRUN )); then
    step "Würde installieren: $name $version → $prefix (Start: $rel)"
    return 0
  fi

  step "Installiere: $name $version → $prefix (Start: $rel)"

  mkdir -p "$prefix/app"
  cp -a -- "$root/." "$prefix/app/"
  chmod u+x -- "$binary" 2>/dev/null || true

  icon_src=""
  [[ -e $root/.DirIcon ]] && icon_src=$(readlink -f -- "$root/.DirIcon")
  [[ -n $icon_src ]] || icon_src=$(best_png "$root")
  icon=$(install_icon "$slug" "$icon_src" "$root")
  [[ -n $icon ]] || icon="application-x-executable"

  write_desktop "$slug" "$name" "$binary" "$icon" \
    "$comment" "$categories" "$mime" >/dev/null
  link_binary "$slug" "$binary"
  refresh_caches

  record_and_report "$(jq -n \
    --arg kind portable \
    --arg slug "$slug" \
    --arg name "$name" \
    --arg version "$version" \
    --arg prefix "$prefix" \
    --arg binary "$binary" \
    --arg source "$src" \
    --arg sha256 "$(sha256sum -- "$src" | cut -d' ' -f1)" \
    --arg installed_at "$(date -Iseconds)" \
    '{kind: $kind, slug: $slug, name: $name, version: $version,
      prefix: $prefix, binary: $binary, source: $source,
      sha256: $sha256, installed_at: $installed_at}')"
}
