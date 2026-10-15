#!/usr/bin/env bash
set -euo pipefail

: "${OPENWRT_DIR:?Missing OPENWRT_DIR}"
: "${BUILDER_REPO:?Missing BUILDER_REPO}"
: "${DEVICE_DIR:?Missing DEVICE_DIR}"
VARIANT="${VARIANT:-ppe-nss}"

echo "=== [1/4] Konfiguracja feeds.conf.default ==="
FEEDS_FILE="${OPENWRT_DIR}/feeds.conf.default"

if [ -n "${FEEDS:-}" ]; then
  while IFS= read -r line; do
    # Pomiń puste linie i komentarze
    [[ -z "${line// }" || "$line" =~ ^# ]] && continue
    feed_name=$(awk '{print $2}' <<<"$line")
    if grep -Eq "^src-git(-full)?[[:space:]]+${feed_name}[[:space:]]+" "$FEEDS_FILE"; then
      echo "--> Podmieniam istniejący feed '${feed_name}' w feeds.conf.default"
      sed -i -E "s|^src-git(-full)?[[:space:]]+${feed_name}[[:space:]]+.*|${line}|" "$FEEDS_FILE"
    else
      echo "--> Dopisuję nowy feed '${feed_name}' do feeds.conf.default"
      echo "$line" >> "$FEEDS_FILE"
    fi
  done <<< "$FEEDS"
fi

echo "--- Aktualna zawartość feeds.conf.default ---"
cat "$FEEDS_FILE"
echo "---------------------------------------------"

echo "=== [2/4] Nakładanie łatek na drzewo OpenWrt (jeśli istnieją) ==="
shopt -s nullglob
for patch_dir in \
  "${BUILDER_REPO}/patches" \
  "${BUILDER_REPO}/patches/openwrt" \
  "${BUILDER_REPO}/patches/tree/ppe" \
  "${BUILDER_REPO}/patches/tree/${VARIANT}" \
  "${BUILDER_REPO}/patches/${VARIANT}"; do
  if [ -d "$patch_dir" ]; then
    for p in "$patch_dir"/*.patch; do
      patch_name="$(basename "$p")"
      patch_rel_dir="${patch_dir#"${BUILDER_REPO}/"}"

      # 1. Sprawdź (usuwając ewentualne znaki CRLF w locie), czy łatka wchodzi czysto
      if tr -d '\r' <"$p" | patch -p1 -d "$OPENWRT_DIR" --dry-run --forward -F 3 >/dev/null 2>&1; then
        echo "--> Applying OpenWrt patch: ${patch_name} (from ${patch_rel_dir})"
        tr -d '\r' <"$p" | patch -p1 -d "$OPENWRT_DIR" --forward -F 3
      # 2. Sprawdź, czy łatka jest już zaaplikowana w drzewie źródłowym (--reverse)
      elif tr -d '\r' <"$p" | patch -p1 -d "$OPENWRT_DIR" --dry-run --reverse -F 3 >/dev/null 2>&1; then
        echo "--> Skipping OpenWrt patch: ${patch_name} (ALREADY APPLIED in source tree)"
      # 3. Jeśli ani jedno, ani drugie - wypisz dokładny błąd z komendy patch!
      else
        echo "--> [WARNING] Patch ${patch_name} failed dry-run! Diagnostyka:"
        tr -d '\r' <"$p" | patch -p1 -d "$OPENWRT_DIR" --dry-run --forward -F 3 || true
      fi
    done
  fi
done
shopt -u nullglob

echo "=== [3/4] Kopiowanie własnych plików (files/ overlay) ==="
if [ -d "${BUILDER_REPO}/devices/common/files" ]; then
  mkdir -p "${OPENWRT_DIR}/files"
  cp -rfT "${BUILDER_REPO}/devices/common/files" "${OPENWRT_DIR}/files"
  echo "--> Skopiowano pliki z devices/common/files"
fi

if [ -d "${BUILDER_REPO}/${DEVICE_DIR}/files" ]; then
  mkdir -p "${OPENWRT_DIR}/files"
  cp -rfT "${BUILDER_REPO}/${DEVICE_DIR}/files" "${OPENWRT_DIR}/files"
  echo "--> Skopiowano pliki z ${DEVICE_DIR}/files"
fi

# Upewnij się, że skrypty startowe i uci-defaults mają prawa wykonywania
for exec_dir in "etc/uci-defaults" "etc/init.d" "etc/rc.button" "usr/bin" "sbin"; do
  if [ -d "${OPENWRT_DIR}/files/${exec_dir}" ]; then
    chmod -R +x "${OPENWRT_DIR}/files/${exec_dir}" || true
  fi
done

echo "=== [4/4] Przygotowanie bazowego pliku .config ==="
rm -f "${OPENWRT_DIR}/.config"
touch "${OPENWRT_DIR}/.config"

if [ -f "${BUILDER_REPO}/devices/common/config" ]; then
  cat "${BUILDER_REPO}/devices/common/config" >> "${OPENWRT_DIR}/.config"
  echo "" >> "${OPENWRT_DIR}/.config"
  echo "--> Dołączono wspólny plik devices/common/config"
fi

if [ -f "${BUILDER_REPO}/${DEVICE_DIR}/config" ]; then
  cat "${BUILDER_REPO}/${DEVICE_DIR}/config" >> "${OPENWRT_DIR}/.config"
  echo "--> Bazowy plik .config z ${DEVICE_DIR}/config został dopisany do ${OPENWRT_DIR}/.config"
else
  echo "::error::Nie znaleziono pliku ${BUILDER_REPO}/${DEVICE_DIR}/config!"
  exit 1
fi