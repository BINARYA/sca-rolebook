#!/usr/bin/env bash
set -euo pipefail

BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"

# In GitHub Actions, possiamo leggere base/head dalla PR
if [[ -z "$BASE_SHA" && -n "${GITHUB_EVENT_PATH:-}" ]]; then
  BASE_SHA="$(jq -r '.pull_request.base.sha' "$GITHUB_EVENT_PATH")"
  HEAD_SHA="$(jq -r '.pull_request.head.sha' "$GITHUB_EVENT_PATH")"
fi

# Fallback: se non abbiamo SHA, controlliamo tutti gli svg del repo
if [[ -z "$BASE_SHA" || -z "$HEAD_SHA" || "$BASE_SHA" == "null" || "$HEAD_SHA" == "null" ]]; then
  echo "WARN: base/head SHA non disponibili. Scansiono tutti gli SVG nel repo."
  mapfile -t SVG_FILES < <(git ls-files '*.svg' || true)
else
  mapfile -t SVG_FILES < <(git diff --name-only "$BASE_SHA" "$HEAD_SHA" -- '*.svg' || true)
fi

if [[ ${#SVG_FILES[@]} -eq 0 ]]; then
  echo "OK: nessun file .svg modificato."
  exit 0
fi

# Pattern "red flag" (tienili stretti e poi allargali solo se serve)
BAD_REGEX=(
  '<script'
  'on[a-zA-Z]+[[:space:]]*='
  'javascript:'
  '<foreignObject'
  '<!DOCTYPE'
  '<!ENTITY'
  'xlink:href[[:space:]]*='
  'href[[:space:]]*='
  'http://|https://'
)

fail=0

echo "Scansione SVG:"
for f in "${SVG_FILES[@]}"; do
  if [[ ! -f "$f" ]]; then
    continue
  fi
  echo " - $f"
  for rx in "${BAD_REGEX[@]}"; do
    if grep -Einqi "$rx" "$f"; then
      echo "   ❌ Trovato pattern sospetto ($rx) in $f"
      # mostra le righe incriminate
      grep -Einq "$rx" "$f" || true
      grep -Ein "$rx" "$f" | head -n 10 || true
      fail=1
    fi
  done
done

if [[ $fail -eq 1 ]]; then
  echo ""
  echo "Blocco PR: SVG contiene elementi potenzialmente attivi/pericolosi."
  echo "Se è un falso positivo, valuta di convertire in PNG o sanitizzare l'SVG."
  exit 1
fi

echo "OK: nessun pattern sospetto rilevato."
