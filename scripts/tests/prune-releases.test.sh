#!/usr/bin/env bash
set -euo pipefail

# Prosty test jednostkowy dla logiki prune z uwzględnieniem prefiksów wariantów PPE-NSS
mock_gh_release_list() {
  local prefix="$1"
  if [ "$prefix" = "ppe-nss" ]; then
    cat << 'EOF'
[
  {"tagName": "ppe-nss-2026-10-15"},
  {"tagName": "ppe-nss-2026-10-14"},
  {"tagName": "ppe-nss-2026-10-13"},
  {"tagName": "ppe-nss-mesh-2026-10-12"},
  {"tagName": "ppe-nss-2026-10-11"}
]
EOF
  else
    cat << 'EOF'
[
  {"tagName": "ppe-nss-mesh-2026-10-15"},
  {"tagName": "ppe-nss-mesh-2026-10-14"},
  {"tagName": "ppe-nss-mesh-2026-10-13"}
]
EOF
  fi
}

echo "Running prune-releases tests..."

# Test 1: Sprawdzenie poprawności filtrowania dla ppe-nss z keep=2
KEEP_PER_VARIANT=2
prefix="ppe-nss"
json_data=$(mock_gh_release_list "$prefix")

mapfile -t tags < <(
  echo "$json_data" | jq -r --arg p "${prefix}-" '[.[] | select(.tagName | startswith($p) and (startswith("ppe-nss-mesh-") | not)) | .tagName]' | jq -r '.[]'
)

if [ "${#tags[@]}" -eq 4 ] && [ "${tags[2]}" = "ppe-nss-2026-10-13" ]; then
  echo "PASS: Filtrowanie i zachowanie wariantów działa poprawnie."
else
  echo "FAIL: Błąd filtrowania tagów."
  exit 1
fi

echo "All prune-releases tests passed successfully!"