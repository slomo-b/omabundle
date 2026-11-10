# shellcheck shell=bash
# AppImage adapter: extract metadata, install under ~/.local/opt, integrate.
#
# Metadata is read with unsquashfs, which never executes the file. Running an
# AppImage to ask it about itself would execute attacker-supplied code at
# install time, before the user ever decided to start the program.

# Candidate byte offsets of a squashfs superblock ("hsqs") inside the AppImage.
# "hsqs" also occurs as a literal in the AppImage runtime's own code, so the
# first hit is not necessarily the payload: a real ~950 KB runtime can contain
# a false "hsqs" before the superblock. Cap the scan and the number of hits.
appimage_offsets() {
  ( set +o pipefail
    head -c 33554432 -- "$1" | LC_ALL=C grep -abom64 'hsqs' | cut -d: -f1 )
}

# Offset of the actual squashfs payload. Probe every candidate with
# `unsquashfs -s`, which only reads the superblock and never executes the file.
appimage_offset() {
  local src=$1 off
  command -v unsquashfs >/dev/null 2>&1 || return 1
  while IFS= read -r off; do
    [[ -n $off ]] || continue
    if ( set +o pipefail
      unsquashfs -o "$off" -s -no-progress "$src" >/dev/null 2>&1 ); then
      printf '%s' "$off"
      return 0
    fi
  done < <(appimage_offsets "$src")
  return 1
}

appimage_list() { # src offset
  ( set +o pipefail
    unsquashfs -o "$2" -l -no-progress "$1" 2>/dev/null \
      | sed -e 's|^squashfs-root/||' \
      | grep -E '(^\.DirIcon$|\.(desktop|png|svg)$)' \
      | head -n 400 )
}

# Read one member through unsquashfs -cat into a size-capped temp file.
# -cat refuses symlinks, so a crafted .DirIcon cannot pull in /etc/passwd,
# and head -c bounds decompression of a malicious squashfs entry.
appimage_cat_member() { # src offset member dest max-bytes
  local src=$1 off=$2 member=$3 dest=$4 max=$5 size
  ( set +o pipefail
    unsquashfs -o "$off" -cat -no-progress "$src" "$member" 2>/dev/null \
      | head -c "$((max + 1))" >"$dest" ) || true
  size=$(stat -c %s -- "$dest" 2>/dev/null || printf 0)
  if (( size == 0 || size > max )); then
    rm -f -- "$dest"
    return 1
  fi
  return 0
}

extract_appimage_metadata() {
  local src=$1 dest=$2 off listing member attempt=0 icon_list
  command -v unsquashfs >/dev/null 2>&1 || return 2
  off=$(appimage_offset "$src") || return 1

  mkdir -p "$dest" || return 1
  chmod 700 "$dest" 2>/dev/null || true

  listing=$(appimage_list "$src" "$off") || true
  if [[ -z $listing ]]; then
    # A valid image may simply contain no .desktop/.png/.svg. Only treat an
    # empty listing as failure when unsquashfs itself cannot read the image.
    unsquashfs -o "$off" -l -no-progress "$src" >/dev/null 2>&1 && return 0
    return 1
  fi

  # The content, not the name, decides which .desktop is the main entry.
  while IFS= read -r member; do
    case $member in *.desktop) ;; *) continue ;; esac
    (( ++attempt > 50 )) && break
    appimage_cat_member "$src" "$off" "$member" "$dest/.desktop" 65536 || continue
    grep -q '^\[Desktop Entry\]' "$dest/.desktop" 2>/dev/null && break
    rm -f -- "$dest/.desktop"
  done <<<"$listing"

  # Icons in preference order: .DirIcon, then installed app icons, then any.
  # Only the first usable one is kept.
  icon_list=$(awk '
    /^\.DirIcon$/ { print "0\t" $0; next }
    /\/icons\/.*\/apps\// { print "1\t" $0; next }
    /\.(png|svg)$/ { print "2\t" $0 }
  ' <<<"$listing" | sort -t$'\t' -k1,1n -k2,2 | cut -f2-)

  attempt=0
  while IFS= read -r member; do
    [[ -n $member ]] || continue
    (( ++attempt > 30 )) && break
    appimage_cat_member "$src" "$off" "$member" "$dest/.icon" 4194304 || continue
    case $(file -b --mime-type -- "$dest/.icon" 2>/dev/null || true) in
      image/png | image/svg+xml) break ;;
    esac
    rm -f -- "$dest/.icon"
  done <<<"$icon_list"

  return 0
}

adapter_appimage_install() {
  local src work dfile name comment categories mime wmclass
  local slug version prefix binary icon icon_src inner rc

  src=$(readlink -f -- "$1") || die "Datei nicht gefunden: $1"
  need file

  step "AppImage erkannt, lese Metadaten"
  mktempdir work
  inner="$work/root"

  rc=0
  extract_appimage_metadata "$src" "$inner" || rc=$?

  if (( rc == 2 )); then
    # Without a squashfs reader there is no way to read the metadata without
    # executing the file, and executing a downloaded file before the user
    # starts it is exactly what this tool must not do.
    die "squashfs-tools fehlt. Lösung: omarchy pkg add squashfs-tools (Metadaten werden bewusst nicht durch Ausführen gelesen)."
  elif (( rc != 0 )); then
    die "AppImage-Payload nicht lesbar (kein squashfs gefunden)"
  fi

  if [[ -f $inner/.desktop ]]; then
    dfile="$inner/.desktop"
  elif [[ -d $inner ]]; then
    dfile=$( ( set +o pipefail
      find "$inner" -name '*.desktop' -type f 2>/dev/null | sort | head -n 1 ) ) || true
  fi

  [[ -n ${dfile:-} ]] || warn "Keine Metadaten gefunden – installiere ohne Menüeintrag"

  name=$(clean_text "$(desktop_field "$dfile" Name)")
  comment=$(clean_text "$(desktop_field "$dfile" Comment)")
  categories=$(desktop_field "$dfile" Categories)
  mime=$(desktop_field "$dfile" MimeType)
  wmclass=$(clean_text "$(desktop_field "$dfile" StartupWMClass)")

  [[ -n $name ]] || name=$(name_from_file "$src")

  slug=$(slugify "$name")
  is_safe_slug "$slug" || slug=$(slugify "$(name_from_file "$src")")
  is_safe_slug "$slug" || die "kein gültiger Programmname ableitbar"

  version=$(desktop_field "$dfile" Version)
  [[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || version=$(version_from_name "$src")

  prefix="$OMABUNDLE_PREFIX/$slug/$version"
  binary="$prefix/$slug.AppImage"

  if (( OMABUNDLE_DRYRUN )); then
    step "Würde installieren: $name $version → $prefix"
    return 0
  fi

  step "Installiere: $name $version → $prefix"

  mkdir -p "$prefix"
  install -m755 -- "$src" "$binary"

  icon_src=""
  if [[ -f $inner/.icon ]]; then
    icon_src="$inner/.icon"
  elif [[ -e $inner/.DirIcon ]]; then
    icon_src="$inner/.DirIcon"
  elif [[ -d $inner ]]; then
    icon_src=$(best_png "$inner")
  fi
  icon=$(install_icon "$slug" "$icon_src" "$inner")
  [[ -n $icon ]] || icon="application-x-executable"

  write_desktop "$slug" "$name" "$binary" "$icon" \
    "$comment" "$categories" "$mime" "$wmclass" >/dev/null
  link_binary "$slug" "$binary"
  refresh_caches

  record_and_report "$(jq -n \
    --arg kind appimage \
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
