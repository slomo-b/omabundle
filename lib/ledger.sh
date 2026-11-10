# shellcheck shell=bash
# Ledger: what was installed where, so remove/doctor can act on it.

ledger_path() { printf '%s/db.json' "$OMABUNDLE_STATE"; }

ledger_init() {
  mkdir -p "$OMABUNDLE_STATE"
  chmod 700 "$OMABUNDLE_STATE" 2>/dev/null || true
  local db
  db=$(ledger_path)
  [[ -s $db ]] || printf '{"version":1,"entries":[]}\n' >"$db"
  chmod 600 "$db" 2>/dev/null || true
}

ledger_put() {
  local entry=$1 db tmp
  ledger_init
  db=$(ledger_path)
  tmp=$(mktemp "$OMABUNDLE_STATE/.db.XXXXXX")
  if ! flock "$OMABUNDLE_STATE/db.lock" \
    jq --argjson e "$entry" \
    '.entries = ([.entries[] | select(.slug != $e.slug)] + [$e])' "$db" >"$tmp"; then
    rm -f "$tmp"
    die "Ledger konnte nicht geschrieben werden: $db"
  fi
  mv -f "$tmp" "$db"
}

ledger_get() {
  ledger_init
  jq -c --arg s "$1" '.entries[] | select(.slug == $s)' "$(ledger_path)"
}

ledger_has() {
  [[ -n $(ledger_get "$1" 2>/dev/null) ]]
}

ledger_delete() {
  local slug=$1 db tmp
  ledger_init
  db=$(ledger_path)
  tmp=$(mktemp "$OMABUNDLE_STATE/.db.XXXXXX")
  flock "$OMABUNDLE_STATE/db.lock" \
    jq --arg s "$slug" '.entries = [.entries[] | select(.slug != $s)]' "$db" >"$tmp"
  mv -f "$tmp" "$db"
}

ledger_list() {
  ledger_init
  jq -c '.entries[]' "$(ledger_path)"
}

# shared by every adapter: persist, then print JSON or a human summary
record_and_report() {
  local entry=$1
  ledger_put "$entry"

  if (( OMABUNDLE_JSON )); then
    printf '%s\n' "$entry"
    return 0
  fi

  printf '\n%s✓%s %s %s (%s)\n' "$grn" "$rst" \
    "$(jq -r '.name' <<<"$entry")" \
    "$(jq -r '.version // "-"' <<<"$entry")" \
    "$(jq -r '.kind' <<<"$entry")"
  printf '  Befehl:  %s\n' "$(jq -r '.slug' <<<"$entry")"
  if [[ $(jq -r '.prefix // empty' <<<"$entry") != "" ]]; then
    printf '  Ablage:  %s\n' "$(jq -r '.prefix' <<<"$entry")"
  fi
  printf '  Entfernen: omabundle remove %s\n' "$(jq -r '.slug' <<<"$entry")"
}
