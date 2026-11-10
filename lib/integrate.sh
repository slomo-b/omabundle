# shellcheck shell=bash
# Desktop integration: icons, .desktop entries, PATH links, cache refreshes.
# Everything stays inside the user's XDG directories.

ensure_dirs() {
  mkdir -p "$OMABUNDLE_PREFIX" "$OMABUNDLE_APPS" "$OMABUNDLE_BIN"
}

install_icon() {
  local slug=$1 src=$2 root=${3:-} mime ext dir real size
  [[ -n $src && -e $src ]] || return 0

  # The icon comes from an untrusted package: follow one symlink, but only
  # inside the extracted tree, and only for a plausible regular file.
  real=$(readlink -f -- "$src") || return 0
  if [[ -n $root ]]; then
    root=$(readlink -f -- "$root") || return 0
    [[ $real == "$root"/* ]] || {
      warn "Icon verweist aus dem Paket heraus – ignoriert"
      return 0
    }
  fi
  [[ -f $real ]] || {
    warn "Icon ist keine reguläre Datei – ignoriert"
    return 0
  }
  size=$(stat -c %s -- "$real" 2>/dev/null || printf '0')
  (( size > 0 && size <= 4194304 )) || {
    warn "Icon-Größe unplausibel (${size} Bytes) – ignoriert"
    return 0
  }

  mime=$(file -b --mime-type -- "$real" 2>/dev/null || true)

  case $mime in
    image/svg+xml) ext=svg dir=scalable ;;
    image/png) ext=png dir=256x256 ;;
    *) warn "Icon ($mime) wird nicht übernommen"; return 0 ;;
  esac

  mkdir -p "$OMABUNDLE_ICONS/$dir/apps"
  cp -f -- "$real" "$OMABUNDLE_ICONS/$dir/apps/$slug.$ext"
  printf '%s' "$slug"
}

OMABUNDLE_KNOWN_CATEGORIES="AudioVideo Audio Video Development Education Game Graphics Network Office Science Settings System Utility Building Debugger IDE GUIDesigner Profiling RevisionControl Translation Calendar ContactManagement Database Dictionary Chart Email Finance FlowChart PDA ProjectManagement Presentation Spreadsheet WordProcessor 2DGraphics VectorGraphics RasterGraphics 3DGraphics Scanning OCR Photography Publishing Viewer TextTools DesktopSettings HardwareSettings Printing PackageManager Dialup InstantMessaging Chat IRCClient Feed FileTransfer HamRadio News P2P RemoteAccess Telephony TelephonyTools VideoConference WebBrowser WebDevelopment Midi Mixer Sequencer Tuner TV AudioVideoEditing Player Recorder DiscBurning ActionGame AdventureGame ArcadeGame BoardGame BlocksGame CardGame KidsGame LogicGame RolePlaying Shooter Simulation SportsGame StrategyGame Art Construction Music Languages ArtificialIntelligence Astronomy Biology Chemistry ComputerScience DataVisualization Economy Electricity Geography Geology Geoscience History Humanities ImageProcessing Literature Maps Math NumericalAnalysis MedicalSoftware Physics Robotics Spirituality Sports ParallelComputing Amusement Archiving Compression Electronics Emulator Engineering FileTools FileManager TerminalEmulator Filesystem Monitor Security Accessibility Calculator Clock TextEditor Documentation Adult Core KDE GNOME GTK Qt Motif Java ConsoleOnly"

sanitize_categories() {
  local raw=${1-} out="" token
  local -a items
  IFS=';' read -ra items <<<"$raw"
  for token in "${items[@]}"; do
    token=${token//[[:space:]]/}
    [[ $token =~ ^[A-Za-z][A-Za-z0-9]{0,31}$ ]] || continue
    # unregistered values must use the X- extension namespace
    [[ " $OMABUNDLE_KNOWN_CATEGORIES " == *" $token "* ]] || token="X-$token"
    [[ ";$out;" == *";$token;"* ]] && continue
    out+="${out:+;}${token}"
  done
  printf '%s' "${out:-Utility}"
}

# slug name exec icon [comment] [categories] [mime] [wmclass]
write_desktop() {
  local slug=$1 name=$2 exec=$3 icon=$4
  local comment=${5:-} categories=${6:-} mime=${7:-} wmclass=${8:-}
  local file="$OMABUNDLE_APPS/$slug.desktop" err

  is_safe_slug "$slug" || die "ungültiger Programmname: $slug"
  mime=$(sanitize_mime_list "$mime")

  mkdir -p "$OMABUNDLE_APPS"
  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Version=1.5\n'
    printf 'Name=%s\n' "$(desktop_text "$name")"
    [[ -n $comment ]] && printf 'Comment=%s\n' "$(desktop_text "$comment")"
    printf 'Exec=%s %%U\n' "$(desktop_quote "$exec")"
    printf 'TryExec=%s\n' "$exec"
    printf 'Icon=%s\n' "$icon"
    printf 'Terminal=false\n'
    printf 'Categories=%s\n' "$(sanitize_categories "$categories")"
    [[ -n $mime ]] && printf 'MimeType=%s\n' "$mime"
    [[ -n $wmclass ]] && printf 'StartupWMClass=%s\n' "$(desktop_text "$wmclass")"
    printf 'X-Omabundle=%s\n' "$slug"
  } >"$file"

  if ! err=$(desktop-file-validate "$file" 2>&1); then
    warn "desktop-file-validate: $err"
  fi
  printf '%s' "$file"
}

# remove one .desktop from every association list in ~/.config/mimeapps.list
remove_app_from_mimeapps() { # desktop file name
  local app=${1-} file tmp
  [[ -n $app ]] || return 0
  file="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
  [[ -f $file ]] || return 0
  tmp=$(mktemp)
  awk -v app="$app" '
    {
      eq = index($0, "=")
      if (eq == 0) { print; next }
      key = substr($0, 1, eq - 1)
      val = substr($0, eq + 1)
      n = split(val, parts, ";")
      out = ""
      for (i = 1; i <= n; i++)
        if (parts[i] != "" && parts[i] != app)
          out = out (out == "" ? "" : ";") parts[i]
      if (out == "") next
      print key "=" out
    }
  ' "$file" >"$tmp"
  mv -f -- "$tmp" "$file"
}

link_binary() {
  local slug=$1 target=$2 dest="$OMABUNDLE_BIN/$slug"
  mkdir -p "$OMABUNDLE_BIN"
  if [[ -e $dest && ! -L $dest ]]; then
    warn "$dest existiert bereits und ist keine Verknüpfung – übersprungen"
    return 0
  fi
  ln -sfn -- "$target" "$dest"
}

refresh_caches() {
  update-desktop-database "$OMABUNDLE_APPS" 2>/dev/null || true
  [[ -d $OMABUNDLE_ICONS ]] && gtk-update-icon-cache -f -t "$OMABUNDLE_ICONS" 2>/dev/null || true
}

remove_integration() {
  local slug=$1
  rm -f -- "$OMABUNDLE_APPS/$slug.desktop"
  rm -f -- "$OMABUNDLE_ICONS/256x256/apps/$slug.png" \
    "$OMABUNDLE_ICONS/scalable/apps/$slug.svg"
  [[ -L $OMABUNDLE_BIN/$slug ]] && rm -f -- "$OMABUNDLE_BIN/$slug"
  remove_app_from_mimeapps "$slug.desktop"
  refresh_caches
}

# pick the largest extracted image as a fallback icon
best_png() {
  local dir=$1 f
  f=$( ( set +o pipefail
    find "$dir" -type f \( -iname '*.png' -o -iname '*.svg' \) -printf '%s\t%p\n' 2>/dev/null \
      | sort -rn | head -n 1 | cut -f2- ) ) || true
  printf '%s' "$f"
}
