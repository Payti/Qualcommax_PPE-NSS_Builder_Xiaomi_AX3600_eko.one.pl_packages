#!/usr/bin/env bash
set -euo pipefail

: "${REPO:?Missing REPO}"
KEEP_PER_VARIANT="${KEEP_PER_VARIANT:-2}"

for prefix in "ppe-nss-mesh" "ppe-nss"; do
  echo "--> Sprawdzanie starych wydań dla wariantu: ${prefix} (zostawiam ${KEEP_PER_VARIANT} najnowsze)..."

  if [ "$prefix" = "ppe-nss" ]; then
    # Wyklucz tagi ppe-nss-mesh-*, aby liczyć wyłącznie standardowy wariant ppe-nss
    mapfile -t tags < <(
      gh release list --repo "$REPO" --limit 100 --json tagName \
        --jq ".[] | select(.tagName | startswith(\"ppe-nss-\") and (startswith(\"ppe-nss-mesh-\") | not)) | .tagName"
    )
  else
    mapfile -t tags < <(
      gh release list --repo "$REPO" --limit 100 --json tagName \
        --jq ".[] | select(.tagName | startswith(\"${prefix}-\")) | .tagName"
    )
  fi

  total=${#tags[@]}
  if (( total <= KEEP_PER_VARIANT )); then
    echo "    Znaleziono ${total} wydań dla '${prefix}' — nic do usunięcia."
    continue
  fi

  for (( i=KEEP_PER_VARIANT; i<total; i++ )); do
    old_tag="${tags[$i]}"
    echo "    Usuwam stare wydanie i tag: ${old_tag}"
    gh release delete "$old_tag" --repo "$REPO" --yes --cleanup-tag || true
  done
done