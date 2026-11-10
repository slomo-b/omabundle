# shellcheck shell=bash
# Shared helpers for omabundle. Sourced by bin/omabundle; not executable.

if [[ -t 2 ]]; then
  red=$'\033[31m' grn=$'\033[32m' ylw=$'\033[33m' dim=$'\033[2m' rst=$'\033[0m'
else
  red='' grn='' ylw='' dim='' rst=''
fi

log() { printf '%s\n' "$*" >&2; }
warn() { printf '%s%s%s\n' "$ylw" "$*" "$rst" >&2; }
die() { printf '%somabundle: %s%s\n' "$red" "$*" "$rst" >&2; exit 1; }
step() { printf '%s→%s %s\n' "$dim" "$rst" "$*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "fehlende Abhängigkeit: $1"
}

# find | head is a SIGPIPE trap under pipefail
first_line() {
  ( set +o pipefail; "$@" | head -n 1 )
}

OMABUNDLE_TMPDIRS=()
# usage: mktempdir <varname>   (no command substitution — that would run in a
# subshell and lose the cleanup list)
mktempdir() {
  local -n _out=$1
  _out=$(mktemp -d "${TMPDIR:-/tmp}/omabundle.XXXXXX")
  OMABUNDLE_TMPDIRS+=("$_out")
}
cleanup_tmpdirs() {
  local d
  for d in ${OMABUNDLE_TMPDIRS[@]+"${OMABUNDLE_TMPDIRS[@]}"}; do
    rm -rf -- "$d"
  done
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-64 \
    | sed -e 's/-$//'
}

version_from_name() {
  local base
  base=$(basename -- "$1")
  if [[ $base =~ [-_]([0-9]+(\.[0-9]+)+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '1'
  fi
}

# "TestApp-1.2.0.tar.gz" -> "TestApp"
name_from_file() {
  local base out
  base=$(basename -- "$1")
  base=${base%.AppImage}
  base=${base%.appimage}
  base=${base%.tar.gz}
  base=${base%.tar.xz}
  base=${base%.tar.zst}
  base=${base%.tgz}
  base=${base%.zip}
  out=$(printf '%s' "$base" | sed -E 's/[-_ ]v?[0-9]+(\.[0-9]+)+.*$//')
  out=$(printf '%s' "$out" | sed -E 's/[-_ ](x86_64|amd64|aarch64|arm64|i[3-6]86|linux).*$//I')
  [[ -n $out ]] || out=$base
  printf '%s' "$out"
}

# first non-empty value of a key in a .desktop file, ignoring [Lang] variants
desktop_field() {
  local file=$1 key=$2 line
  [[ -n $file && -r $file ]] || return 0
  line=$(grep -m1 -E "^${key}=" "$file" 2>/dev/null || true)
  printf '%s' "${line#*=}"
}

# A ledger path must resolve to exactly <prefix>/<slug>/<version>.
# The ledger is user-writable, so never let it point rm outside our tree.
prefix_is_safe() { # slug prefix
  local slug=$1 prefix=$2 root real rest
  is_safe_slug "$slug" || return 1
  root=$(realpath -m -- "$OMABUNDLE_PREFIX" 2>/dev/null) || return 1
  real=$(realpath -m -- "$prefix" 2>/dev/null) || return 1
  [[ $real == "$root/$slug/"* ]] || return 1
  rest=${real#"$root/$slug/"}
  [[ -n $rest && $rest != */* ]]
}

confirm() {
  local prompt=$1
  (( OMABUNDLE_YES )) && return 0
  [[ -t 0 ]] || die "Bestätigung nötig, aber kein Terminal ($prompt). Nutze --yes."
  local reply
  read -r -p "$prompt [j/N] " reply
  [[ $reply == [jJyY]* ]]
}

# strip C0 control characters (terminal escapes, bell, etc.) from untrusted text
clean_text() {
  printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037\177' | tr '\n\r\t' '   '
}

is_safe_slug() {
  local s=${1-}
  (( ${#s} > 0 && ${#s} <= 64 )) || return 1
  [[ $s =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

is_safe_mime() {
  [[ ${1-} =~ ^[A-Za-z0-9][A-Za-z0-9.+-]*/[A-Za-z0-9][A-Za-z0-9.+-]*$ ]]
}

# keep only syntactically valid, unique MIME types; drop anything else
sanitize_mime_list() {
  local raw=${1-} out="" m n=0
  local -a items
  IFS=';' read -ra items <<<"$raw"
  for m in "${items[@]}"; do
    m=${m//[[:space:]]/}
    is_safe_mime "$m" || continue
    [[ ";$out;" == *";$m;"* ]] && continue
    (( n++ >= 20 )) && break
    out+="${out:+;}${m}"
  done
  printf '%s' "$out"
}

desktop_quote() {
  # `%` starts a field code in Exec=, so it must be doubled
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/[\\"$`]/\\&/g' -e 's/%/%%/g')"
}

# collapse anything that would break a single-line desktop field
desktop_text() {
  clean_text "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}
