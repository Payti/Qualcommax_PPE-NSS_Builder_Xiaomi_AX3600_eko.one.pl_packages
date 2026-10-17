#!/usr/bin/env bash
set -euo pipefail

: "${REPO:?Missing REPO}"
KEEP_PER_VARIANT="${KEEP_PER_VARIANT:-2}"

echo "--> Sprawdzanie starych wydań dla wariantu: ppe-nss (zostawiam ${KEEP_PER_VARIANT} najnowsze)..."
mapfile -t tags < <(
  gh release list --repo "$REPO" --limit 100 --json tagName \
    --jq '.[] | select(.tagName | startswith("ppe-nss-") and (startswith("ppe-nss-mesh-") | not)) | .tagName'
)

total=${#tags[@]}
if (( total <= KEEP_PER_VARIANT )); then
  echo "    Znaleziono ${total} wydań dla 'ppe-nss' — nic do usunięcia."
else
  for (( i=KEEP_PER_VARIANT; i<total; i++ )); do
    old_tag="${tags[$i]}"
    echo "    Usuwam stare wydanie i tag: ${old_tag}"
    gh release delete "$old_tag" --repo "$REPO" --yes --cleanup-tag || true
  done
fi

# Czyszczenie archiwalnych wydań ppe-nss-mesh-* (już niebudowanych osobno)
mapfile -t legacy_mesh_tags < <(
  gh release list --repo "$REPO" --limit 100 --json tagName \
    --jq '.[] | select(.tagName | startswith("ppe-nss-mesh-")) | .tagName'
)
for old_mesh_tag in "${legacy_mesh_tags[@]}"; do
  echo "    Usuwam archiwalne wydanie mesh: ${old_mesh_tag}"
  gh release delete "$old_mesh_tag" --repo "$REPO" --yes --cleanup-tag || true
done