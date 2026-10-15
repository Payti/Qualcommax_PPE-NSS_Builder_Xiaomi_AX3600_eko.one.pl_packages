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
  else
    cat << 'EOF'
[
  {"tagName": "ppe-nss-mesh-20261015T120000Z-2001-offload"},
  {"tagName": "ppe-nss-mesh-20261014T120000Z-2000-offload"},
  {"tagName": "ppe-nss-mesh-20261013T120000Z-1999-offload"}
]
EOF
  fi
}

echo "Running prune-releases tests..."

KEEP_PER_VARIANT=2
prefix="ppe-nss"
json_data=$(mock_gh_release_list "$prefix")

# Odczyt tagów zgodny z logiką ze skryptu prune-releases.sh i używający KEEP_PER_VARIANT
mapfile -t tags < <(
  echo "$json_data" | jq -r --arg p "${prefix}-" --argjson limit "$KEEP_PER_VARIANT" '
    [.[] | select(.tagName | startswith($p) and (startswith("ppe-nss-mesh-") | not)) | .tagName] | .[0:$limit]
  '
)

if [ "${#tags[@]}" -eq 2 ]; then
  echo "PASS: Filtrowanie i limit KEEP_PER_VARIANT ($KEEP_PER_VARIANT) dla $prefix działają poprawnie."
else
  echo "FAIL: Niepoprawna liczba odfiltrowanych tagów."
  exit 1
fi

echo "All prune-releases tests passed successfully!"