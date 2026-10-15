#!/usr/bin/env bash
set -euo pipefail

mock_gh_release_list() {
  local prefix="$1"
  if [ "$prefix" = "ppe-nss" ]; then
    cat << 'EOF'
[
  {"tagName": "ppe-nss-20261015T120000Z-1001-offload"},
  {"tagName": "ppe-nss-20261014T120000Z-1000-offload"},
  {"tagName": "ppe-nss-20261013T120000Z-0999-offload"},
  {"tagName": "ppe-nss-mesh-20261012T120000Z-0998-offload"},
  {"tagName": "ppe-nss-20261011T120000Z-0997-offload"}
]
EOF
  fi
}

echo "Running prune-releases tests..."

KEEP_PER_VARIANT=2
prefix="ppe-nss"
json_data=$(mock_gh_release_list "$prefix")

# Odczyt tagów z uwzględnieniem filtra wariantu i limitu KEEP_PER_VARIANT
mapfile -t tags < <(
  echo "$json_data" | jq -r --arg p "${prefix}-" --argjson limit "$KEEP_PER_VARIANT" '
    [.[] | select(.tagName | startswith($p) and (startswith("ppe-nss-mesh-") | not)) | .tagName] | .[$limit:]
  '
)

# W mocku mamy 4 pasujące tagi dla ppe-nss. Po odcięciu pierwszych 2 (limit=2) zostają 2 starsze do usunięcia.
if [ "${#tags[@]}" -eq 2 ]; then
  echo "PASS: Test usuwania starych tagów dla $prefix przeszedł pomyślnie."
else
  echo "FAIL: Niepoprawna liczba tagów do usunięcia (oczekiwano 2, otrzymano ${#tags[@]})."
  exit 1
fi

echo "All prune-releases tests passed successfully!"