#!/usr/bin/env bash
# Hybrydowy skrypt przygotowujący drzewo OpenWrt pod build PPE-NSS (Xiaomi AX3600)
set -euo pipefail

# --- Wbudowane funkcje logowania (brak zależności od zewnętrznego lib/log.sh) ---
log_info()  { echo "--> $*"; }
log_warn()  { echo "::warning::$*" >&2; }
log_error() { echo "::error::$*" >&2; }
log_die()   { log_error "$*"; exit 1; }

# --- 0. Walidacja i normalizacja zmiennych środowiskowych ---
: "${OPENWRT_DIR:?Brak wymaganej zmiennej OPENWRT_DIR}"
: "${BUILDER_REPO:?Brak wymaganej zmiennej BUILDER_REPO}"

# Zamiana na ścieżki bezwzględne (chroni przed zmianą katalogu przez cd "$OPENWRT_DIR")
OPENWRT_DIR="$(cd "$OPENWRT_DIR" && pwd)"
BUILDER_REPO="$(cd "$BUILDER_REPO" && pwd)"

VARIANT="${VARIANT:-ppe-nss}"
CONFIG_FRAGMENT="${CONFIG_FRAGMENT:-}"
COMMON_DIR="${BUILDER_REPO}/devices/${COMMON:-common}"

# Kompatybilność wsteczna: obsługa zarówno DEVICE_DIR="devices/xiaomi_ax3600", jak i DEVICE="xiaomi_ax3600"
if [[ -n "${DEVICE_DIR:-}" ]]; then
  DEVICE_PATH="${BUILDER_REPO}/${DEVICE_DIR#"${BUILDER_REPO}"/}"
elif [[ -n "${DEVICE:-}" ]]; then
  DEVICE_PATH="${BUILDER_REPO}/devices/${DEVICE}"
else
  log_die "Musisz ustawić zmienną DEVICE_DIR lub DEVICE!"
fi

[[ -f "${DEVICE_PATH}/config" ]] || log_die "Nie znaleziono pliku konfiguracyjnego: ${DEVICE_PATH}/config"

cd "$OPENWRT_DIR"

# ==============================================================================
echo "=== [1/4] Konfiguracja feeds.conf ==="
# Pracujemy na kopii feeds.conf, aby nie brudzić (dirty) repozytorium git OpenWrt
[[ -f feeds.conf ]] || cp feeds.conf.default feeds.conf
FEEDS_FILE="${OPENWRT_DIR}/feeds.conf"

if [[ -n "${FEEDS:-}" ]]; then
  while IFS= read -r line; do
    # Usuń znaki CRLF oraz pomiń puste linie i komentarze
    line="${line%$'\r'}"
    [[ -z "${line// }" || "$line" =~ ^[[:space:]]*# ]] && continue

    feed_name="$(awk '{print $2}' <<<"$line")"
    if grep -qxF "$line" "$FEEDS_FILE"; then
      log_info "Feed '${feed_name}' jest już skonfigurowany identycznie"
    elif grep -qE "^src-\S+[[:space:]]+${feed_name}[[:space:]]+" "$FEEDS_FILE"; then
      log_info "Podmieniam istniejący feed '${feed_name}' w feeds.conf"
      sed -i -E "s|^src-\S+[[:space:]]+${feed_name}[[:space:]]+.*|${line}|" "$FEEDS_FILE"
    else
      log_info "Dopisuję nowy feed '${feed_name}' do feeds.conf"
      echo "$line" >> "$FEEDS_FILE"
    fi
  done <<< "$FEEDS"
fi

echo "--- Aktualna zawartość feeds.conf ---"
cat "$FEEDS_FILE"
echo "-------------------------------------"

# Jeśli zmienna RUN_FEEDS_IN_PREPARE=1, skrypt sam pobierze i zainstaluje feedy w tym miejscu.
if [[ "${RUN_FEEDS_IN_PREPARE:-0}" == "1" ]]; then
  log_info "Aktualizacja i instalacja wszystkich feedów (RUN_FEEDS_IN_PREPARE=1)..."
  ./scripts/feeds update -a
  ./scripts/feeds install -a
fi

# ==============================================================================
echo "=== [2/4] Nakładanie łatek na drzewo OpenWrt i feedy ==="
shopt -s nullglob

# Funkcja nakładająca łatkę z weryfikacją 3-stanową i czyszczeniem CRLF w locie
apply_patch_safely() {
  local patch_file="$1"
  local target_dir="$2"
  local label="$3"
  local patch_name
  patch_name="$(basename "$patch_file")"

  if tr -d '\r' <"$patch_file" | patch -p1 -d "$target_dir" --dry-run --forward -F 3 >/dev/null 2>&1; then
    log_info "Applying ${label} patch: ${patch_name}"
    tr -d '\r' <"$patch_file" | patch -p1 -d "$target_dir" --forward -F 3
  elif tr -d '\r' <"$patch_file" | patch -p1 -d "$target_dir" --dry-run --reverse -F 3 >/dev/null 2>&1; then
    log_info "Skipping ${label} patch: ${patch_name} (already applied in source)"
  else
    log_warn "Łatka ${patch_name} nie pasuje do ${label} (${target_dir})! Szczegóły konfliktu:"
    tr -d '\r' <"$patch_file" | patch -p1 -d "$target_dir" --dry-run --forward -F 3 || true
    log_warn "Łatka ${patch_name} została pominięta (plik już istnieje lub dotyczy innej wersji jądra)."
  fi
}

# 2a. Łatki na główne drzewo OpenWrt (z deduplikacją katalogów)
declare -A visited_dirs=()
for patch_dir in \
  "${BUILDER_REPO}/patches" \
  "${BUILDER_REPO}/patches/openwrt" \
  "${BUILDER_REPO}/patches/tree/ppe" \
  "${BUILDER_REPO}/patches/tree/${VARIANT}" \
  "${BUILDER_REPO}/patches/${VARIANT}"; do

  if [[ -d "$patch_dir" ]]; then
    real_dir="$(cd "$patch_dir" && pwd)"
    [[ -n "${visited_dirs[$real_dir]:-}" ]] && continue
    visited_dirs[$real_dir]=1

    rel_dir="${patch_dir#"${BUILDER_REPO}"/}"
    for p in "$patch_dir"/*.patch; do
      apply_patch_safely "$p" "$OPENWRT_DIR" "OpenWrt (${rel_dir})"
    done
  fi
done

# 2b. Łatki na pobrane feedy (wykona się automatycznie, jeśli katalog feeds/ już istnieje)
for feed_variant_dir in \
  "${BUILDER_REPO}/patches/feeds/ppe" \
  "${BUILDER_REPO}/patches/feeds/ppe-nss" \
  "${BUILDER_REPO}/patches/feeds/${VARIANT}"; do

  if [[ -d "$feed_variant_dir" ]]; then
    real_fdir="$(cd "$feed_variant_dir" && pwd)"
    [[ -n "${visited_dirs[$real_fdir]:-}" ]] && continue
    visited_dirs[$real_fdir]=1

    # Struktura: patches/feeds/<variant>/<feed_name>/*.patch
    for p in "$feed_variant_dir"/*/*.patch; do
      feed_name="$(basename "$(dirname "$p")")"
      target_feed_dir="${OPENWRT_DIR}/feeds/${feed_name}"
      if [[ -d "$target_feed_dir" ]]; then
        apply_patch_safely "$p" "$target_feed_dir" "feed/${feed_name}"
      else
        log_warn "Pominięto łatkę $(basename "$p") - katalog feeds/${feed_name} jeszcze nie istnieje (wykonaj 'feeds update' wcześniej)."
      fi
    done
  fi
done
shopt -u nullglob

# ==============================================================================
echo "=== [3/4] Kopiowanie własnych plików (files/ overlay) ==="
mkdir -p "${OPENWRT_DIR}/files"

# Kaskadowe nakładanie: od najbardziej ogólnych (common) do specyficznych dla wariantu urządzenia
for src_files in \
  "${COMMON_DIR}/files" \
  "${COMMON_DIR}/files.${VARIANT}" \
  "${DEVICE_PATH}/files" \
  "${DEVICE_PATH}/files.${VARIANT}"; do

  if [[ -d "$src_files" ]]; then
    cp -rfT "$src_files" "${OPENWRT_DIR}/files"
    log_info "Skopiowano pliki overlay z: ${src_files#"${BUILDER_REPO}"/}"
  fi
done

# Uprawnienia wykonywania dla skryptów systemowych
for exec_dir in "etc/uci-defaults" "etc/init.d" "etc/rc.button" "usr/bin" "usr/sbin" "sbin" "bin"; do
  if [[ -d "${OPENWRT_DIR}/files/${exec_dir}" ]]; then
    chmod -R +x "${OPENWRT_DIR}/files/${exec_dir}" || true
  fi
done

# Restrykcyjne uprawnienia dla sshd_config (wymagane przez OpenSSH)
if [[ -f "${OPENWRT_DIR}/files/etc/ssh/sshd_config" ]]; then
  chmod 0600 "${OPENWRT_DIR}/files/etc/ssh/sshd_config"
fi

# ==============================================================================
echo "=== [4/4] Przygotowanie i weryfikacja pliku .config ==="
rm -f "${OPENWRT_DIR}/.config"
touch "${OPENWRT_DIR}/.config"

CONFIGS=()
if [[ -f "${COMMON_DIR}/config" ]]; then
  CONFIGS+=("${COMMON_DIR}/config")
  log_info "Dołączono wspólny profil: ${COMMON_DIR#"${BUILDER_REPO}"/}/config"
fi

CONFIGS+=("${DEVICE_PATH}/config")
log_info "Dołączono profil urządzenia: ${DEVICE_PATH#"${BUILDER_REPO}"/}/config"

if [[ -n "$CONFIG_FRAGMENT" ]]; then
  [[ -f "${BUILDER_REPO}/${CONFIG_FRAGMENT}" ]] || log_die "Nie znaleziono CONFIG_FRAGMENT: ${CONFIG_FRAGMENT}"
  CONFIGS+=("${BUILDER_REPO}/${CONFIG_FRAGMENT}")
  log_info "Dołączono fragment konfiguracji: ${CONFIG_FRAGMENT}"
fi

# Połącz pliki konfiguracyjne (gwarantując znak nowej linii między nimi) i usuń ewentualne CRLF
for cfg in "${CONFIGS[@]}"; do
  tr -d '\r' < "$cfg" >> "${OPENWRT_DIR}/.config"
  echo "" >> "${OPENWRT_DIR}/.config"
done

# Wyłącz budowanie całych repozytoriów niestandardowych feedów (np. nss, obsy) i ich wpisów w distfeeds.conf
if [[ -n "${FEEDS:-}" ]]; then
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -z "${line// }" || "$line" =~ ^[[:space:]]*# ]] && continue
    feed_name="$(awk '{print $2}' <<<"$line")"
    # Jeśli to zupełnie nowy feed (nie występuje w domyślnym feeds.conf.default), wyłącz jego flagę CONFIG_FEED_
    if ! grep -qE "^src-\S+[[:space:]]+${feed_name}[[:space:]]+" "${OPENWRT_DIR}/feeds.conf.default"; then
      log_info "Wyłączam globalne indeksowanie dla dodatkowego feedu: CONFIG_FEED_${feed_name}"
      echo "# CONFIG_FEED_${feed_name} is not set" >> "${OPENWRT_DIR}/.config"
    fi
  done <<< "$FEEDS"
fi
echo "# CONFIG_FEED_luci_extra is not set" >> "${OPENWRT_DIR}/.config"

# Weryfikacja symboli po 'make defconfig' (gdy włączono RUN_DEFCONFIG_CHECK=1)
if [[ "${RUN_DEFCONFIG_CHECK:-0}" == "1" ]]; then
  log_info "Uruchamiam 'make defconfig' oraz weryfikację zachowanych symboli..."
  make defconfig

  # Zabezpieczenie ponowne po defconfig (gdyby defconfig nadpisał flagi CONFIG_FEED_*)
  if [[ -n "${FEEDS:-}" ]]; then
    while IFS= read -r line; do
      line="${line%$'\r'}"
      [[ -z "${line// }" || "$line" =~ ^[[:space:]]*# ]] && continue
      feed_name="$(awk '{print $2}' <<<"$line")"
      grep -qE "^src-\S+[[:space:]]+${feed_name}[[:space:]]+" "${OPENWRT_DIR}/feeds.conf.default" && continue
      sed -i "s/^CONFIG_FEED_${feed_name}=.*/# CONFIG_FEED_${feed_name} is not set/" "${OPENWRT_DIR}/.config" || true
    done <<< "$FEEDS"
  fi
  sed -i 's/^CONFIG_FEED_luci_extra=.*/# CONFIG_FEED_luci_extra is not set/' "${OPENWRT_DIR}/.config" || true

  dropped=()
  while IFS= read -r req; do
    grep -qxF "$req" "${OPENWRT_DIR}/.config" || dropped+=("$req")
  done < <(cat "${CONFIGS[@]}" | tr -d '\r' |
    grep -E '^CONFIG_[A-Za-z0-9_-]+=' |
    awk -F= '{ last[$1] = $0 } END { for (s in last) print last[s] }' |
    grep -vE '=n$')

  if ((${#dropped[@]})); then
    log_error "make defconfig odrzucił ${#dropped[@]} wymaganych opcji (niespełnione zależności lub brak pobranego feedu):"
    printf '  %s\n' "${dropped[@]}" >&2
    log_die "Dodaj brakujące zależności lub popraw plik config - przerwano budowanie niepełnego obrazu!"
  fi
  log_info "Weryfikacja zakończona sukcesem: wszystkie żądane pakiety i flagi są aktywne."
else
  log_info "Gotowy bazowy plik .config zapisano w ${OPENWRT_DIR}/.config (make defconfig wykona się w kolejnym kroku workflow)."
fi