#!/usr/bin/env bash
set -euo pipefail

: "${UPSTREAM_REPO:?Missing UPSTREAM_REPO}"
: "${UPSTREAM_REF:?Missing UPSTREAM_REF}"
: "${NSS_REPO:?Missing NSS_REPO}"
: "${NSS_REF:?Missing NSS_REF}"
: "${REPO:?Missing REPO}"
: "${EVENT_NAME:?Missing EVENT_NAME}"
RELEASE_PREFIX="${RELEASE_PREFIX:-ppe-nss}"

echo "--> Checking latest commit for ${UPSTREAM_REPO} (${UPSTREAM_REF})..."
upstream_sha=$(git ls-remote "https://github.com/${UPSTREAM_REPO}.git" "refs/heads/${UPSTREAM_REF}" | awk '{print $1}')
if [ -z "$upstream_sha" ]; then
  upstream_sha=$(gh api "repos/${UPSTREAM_REPO}/commits/${UPSTREAM_REF}" --jq '.sha')
fi

echo "--> Checking latest commit for ${NSS_REPO} (${NSS_REF})..."
nss_sha=$(git ls-remote "https://github.com/${NSS_REPO}.git" "refs/heads/${NSS_REF}" | awk '{print $1}')
if [ -z "$nss_sha" ]; then
  nss_sha=$(gh api "repos/${NSS_REPO}/commits/${NSS_REF}" --jq '.sha')
fi

echo "Resolved UPSTREAM_SHA: ${upstream_sha}"
echo "Resolved NSS_SHA:      ${nss_sha}"

{
  echo "sha=${upstream_sha}"
  echo "upstream_sha=${upstream_sha}"
  echo "nss_sha=${nss_sha}"
} >> "$GITHUB_OUTPUT"

# Dla ręcznego uruchomienia (workflow_dispatch) lub pusha w repozytorium zawsze buduj
if [ "$EVENT_NAME" != "schedule" ]; then
  echo "--> Triggered by '${EVENT_NAME}' — forcing build (need=true)."
  echo "need=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Dla harmonogramu (schedule) porównaj SHA z najnowszym wydaniem (Release)
latest_tag=$(gh release list --repo "$REPO" --limit 20 --json tagName --jq "[.[] | select(.tagName | startswith(\"${RELEASE_PREFIX}-\"))][0].tagName // empty" || true)

if [ -z "$latest_tag" ]; then
  echo "--> No previous '${RELEASE_PREFIX}-*' release found — build needed (need=true)."
  echo "need=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

release_body=$(gh release view "$latest_tag" --repo "$REPO" --json body --jq '.body' || true)

if grep -Fq "${UPSTREAM_REPO}@${upstream_sha}" <<<"$release_body" && \
   grep -Fq "${NSS_REPO}@${nss_sha}" <<<"$release_body"; then
  echo "--> Latest release (${latest_tag}) already matches both OpenWrt and NSS SHAs — skipping build (need=false)."
  echo "need=false" >> "$GITHUB_OUTPUT"
else
  echo "--> Upstream changes detected since ${latest_tag} — build needed (need=true)."
  echo "need=true" >> "$GITHUB_OUTPUT"
fi