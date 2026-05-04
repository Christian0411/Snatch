#!/usr/bin/env bash
# scripts/release.sh — Snatch release pipeline.
#
#   scripts/release.sh [--publish] <version>
#
#   <version>        e.g. 1.0.0  (no v prefix; matches Info.plist)
#   --publish        Tag, push, and create a draft GitHub release with the DMG
#                    attached. Without this flag, the script stops after
#                    producing a stapled DMG locally — useful for dry runs.
#
# Pre-reqs:
#   - Developer ID Application cert in the login keychain.
#   - notarytool keychain profile named "snatch-notarize"
#     (xcrun notarytool store-credentials snatch-notarize ...).
#   - Working tree clean, on main branch.
#   - Info.plist's CFBundleShortVersionString matches <version>.
#   - scripts/release-notes-<version>.md exists (only checked under --publish).

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────────────────
PUBLISH=false
if [[ "${1:-}" == "--publish" ]]; then
    PUBLISH=true
    shift
fi
if [[ $# -ne 1 ]]; then
    echo "usage: $0 [--publish] <version>" >&2
    exit 64
fi
VERSION="$1"
TAG="v${VERSION}"

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

BUILD="${ROOT}/build"
ARCHIVE="${BUILD}/Snatch.xcarchive"
EXPORT="${BUILD}/export"
APP="${EXPORT}/Snatch.app"
ZIP="${BUILD}/Snatch.zip"
DMG="${BUILD}/Snatch-${VERSION}.dmg"
DMG_STAGING="${BUILD}/dmg-staging"
NOTES="${ROOT}/scripts/release-notes-${VERSION}.md"

NOTARIZE_PROFILE="snatch-notarize"
TEAM_ID="8E765EZVAM"

# ── Pre-flight ────────────────────────────────────────────────────────────────
echo "▸ Pre-flight checks"

# Working tree clean.
if ! git diff --quiet || ! git diff --staged --quiet; then
    echo "✗ Working tree not clean. Commit or stash first." >&2
    exit 1
fi

# On main.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${BRANCH}" != "main" ]]; then
    echo "✗ Not on main (currently ${BRANCH}). Releases only ship from main." >&2
    exit 1
fi

# Info.plist version matches.
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' App/Info.plist)"
if [[ "${PLIST_VERSION}" != "${VERSION}" ]]; then
    echo "✗ Info.plist CFBundleShortVersionString is '${PLIST_VERSION}', expected '${VERSION}'." >&2
    echo "  Bump it in a separate commit before re-running." >&2
    exit 1
fi

# Cert present.
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "✗ No 'Developer ID Application' cert in keychain." >&2
    exit 1
fi

# Capture full identity (e.g. "Developer ID Application: Christian Canizares (8E765EZVAM)").
DEV_ID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 \
    | sed -E 's/^[ \t]*[0-9]+\)[ \t]+[A-F0-9]+[ \t]+"(.+)"$/\1/')"
echo "  signing identity: ${DEV_ID}"

# Notarytool credentials.
if ! xcrun notarytool history --keychain-profile "${NOTARIZE_PROFILE}" >/dev/null 2>&1; then
    echo "✗ notarytool keychain profile '${NOTARIZE_PROFILE}' missing." >&2
    echo "  Set up via: xcrun notarytool store-credentials ${NOTARIZE_PROFILE} ..." >&2
    exit 1
fi

# Release notes (only under --publish).
if [[ "${PUBLISH}" == "true" && ! -f "${NOTES}" ]]; then
    echo "✗ Missing ${NOTES}. Create it before --publish." >&2
    exit 1
fi

# gh logged in (only under --publish).
if [[ "${PUBLISH}" == "true" ]]; then
    if ! gh auth status >/dev/null 2>&1; then
        echo "✗ gh CLI not logged in. Run: gh auth login" >&2
        exit 1
    fi
fi

echo "  ok"

# ── Clean ────────────────────────────────────────────────────────────────────
echo "▸ Clean"
rm -rf "${BUILD}"
mkdir -p "${BUILD}"

# ── Archive ──────────────────────────────────────────────────────────────────
echo "▸ Archive (xcodebuild)"
xcodebuild \
    -project Snatch.xcodeproj \
    -scheme Snatch \
    -configuration Release \
    -archivePath "${ARCHIVE}" \
    archive | tail -2

# ── Export ───────────────────────────────────────────────────────────────────
echo "▸ Export"
xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE}" \
    -exportPath "${EXPORT}" \
    -exportOptionsPlist "${ROOT}/scripts/ExportOptions.plist" | tail -2

# ── Verify .app signing locally ──────────────────────────────────────────────
echo "▸ Verify signing"
codesign --verify --deep --strict --verbose=2 "${APP}"
echo "  ok"

# ── Notarize the .app ────────────────────────────────────────────────────────
echo "▸ Notarize .app (this takes 1–5 min)"
ditto -c -k --keepParent "${APP}" "${ZIP}"
APP_SUBMIT_OUTPUT="$(xcrun notarytool submit "${ZIP}" \
    --keychain-profile "${NOTARIZE_PROFILE}" \
    --wait 2>&1)"
echo "${APP_SUBMIT_OUTPUT}"
if ! grep -q "status: Accepted" <<< "${APP_SUBMIT_OUTPUT}"; then
    SUBMISSION_ID="$(grep -E "id: " <<< "${APP_SUBMIT_OUTPUT}" | head -1 | awk '{print $2}')"
    echo "✗ .app notarization failed. Submission id: ${SUBMISSION_ID}" >&2
    echo "  Fetch log: xcrun notarytool log ${SUBMISSION_ID} --keychain-profile ${NOTARIZE_PROFILE}" >&2
    exit 1
fi

# ── Staple .app ──────────────────────────────────────────────────────────────
echo "▸ Staple .app"
xcrun stapler staple "${APP}"
xcrun stapler validate "${APP}"

# ── Build DMG ────────────────────────────────────────────────────────────────
echo "▸ Build DMG"
mkdir -p "${DMG_STAGING}"
cp -R "${APP}" "${DMG_STAGING}/"
ln -sfn /Applications "${DMG_STAGING}/Applications"
hdiutil create \
    -volname Snatch \
    -srcfolder "${DMG_STAGING}" \
    -format UDZO \
    -ov \
    "${DMG}" >/dev/null

# ── Sign DMG ─────────────────────────────────────────────────────────────────
echo "▸ Sign DMG"
codesign --force --sign "${DEV_ID}" "${DMG}"

# ── Notarize DMG ─────────────────────────────────────────────────────────────
echo "▸ Notarize DMG (this takes 1–5 min)"
DMG_SUBMIT_OUTPUT="$(xcrun notarytool submit "${DMG}" \
    --keychain-profile "${NOTARIZE_PROFILE}" \
    --wait 2>&1)"
echo "${DMG_SUBMIT_OUTPUT}"
if ! grep -q "status: Accepted" <<< "${DMG_SUBMIT_OUTPUT}"; then
    SUBMISSION_ID="$(grep -E "id: " <<< "${DMG_SUBMIT_OUTPUT}" | head -1 | awk '{print $2}')"
    echo "✗ DMG notarization failed. Submission id: ${SUBMISSION_ID}" >&2
    echo "  Fetch log: xcrun notarytool log ${SUBMISSION_ID} --keychain-profile ${NOTARIZE_PROFILE}" >&2
    exit 1
fi

# ── Staple DMG ───────────────────────────────────────────────────────────────
echo "▸ Staple DMG"
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"

# ── Final Gatekeeper check ───────────────────────────────────────────────────
echo "▸ Final Gatekeeper check"
spctl -a -t open --context context:primary-signature "${DMG}"
echo "  ok"

# ── Stop here unless --publish ───────────────────────────────────────────────
echo
echo "✓ DMG ready: ${DMG}"
echo "  size: $(du -h "${DMG}" | awk '{print $1}')"

if [[ "${PUBLISH}" != "true" ]]; then
    echo
    echo "Dry run complete. To publish, re-run with: $0 --publish ${VERSION}"
    exit 0
fi

# ── Tag + push + draft release ───────────────────────────────────────────────
echo
echo "▸ Tag + push"
git tag "${TAG}"
git push origin "${TAG}"

echo "▸ Create draft GitHub release"
gh release create "${TAG}" \
    --title "Snatch ${VERSION}" \
    --notes-file "${NOTES}" \
    --draft \
    "${DMG}"

echo
echo "✓ Draft release created."
echo "  Eyeball it on the GitHub web UI, then click 'Publish release'."
