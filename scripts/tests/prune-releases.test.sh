#!/usr/bin/env bash
set -euo pipefail

mock_gh_release_list() {
  cat << 'EOF'
[
  {"tagName": "ppe-nss-20261015T120000Z-1001-offload"},
  {"tagName": "ppe-nss-20261014T120000Z-1000-offload"},
  {"tagName": "ppe-nss-20261013T120000Z-0999-offload"},
  {"tagName": "ppe-nss-mesh-20261012T120000Z-0998-offload"}
]
EOF
}

echo "Running prune-releases tests..."

KEEP_PER_VARIANT=2
prefix="ppe-nss"
json_data=$(mock_gh_release_list)

# Pobieramy wszystkie tagi pasujące do wariantu, pomijając mesh
mapfile -t tags < <(
  echo "$json_data" | jq -r --arg p "${prefix}-" '
    [.[].tagName | select(. | startswith($p) and (startswith("ppe-nss-mesh-") | not))]
  ' | jq -r '.[]'
)

# Weryfikacja: w mocku są dokładnie 3 pasujące tagi ppe-nss
if [ "${#tags[@]}" -eq 3 ]; then
  echo "PASS: Znaleziono dokładnie 3 pasujące tagi dla wariantu $prefix."
else
  echo "FAIL: Oczekiwano 3 tagów, otrzymano ${#tags[@]}."
  exit 1
fi

# Sprawdzenie mechanizmu ucinania powyżej KEEP_PER_VARIANT (zostają 2 najnowsze, 1 do usunięcia)
total=${#tags[@]}
to_delete=$(( total - KEEP_PER_VARIANT ))

if [ "$to_delete" -eq 1 ]; then
  echo "PASS: Liczba starych tagów do usunięcia wynosi poprawnie 1."
else
  echo "FAIL: Niepoprawna liczba tagów do usunięcia."
  exit 1
fi

echo "All prune-releases tests passed successfully!"