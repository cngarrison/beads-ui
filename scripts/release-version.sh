#!/usr/bin/env bash
# scripts/release-version.sh — bump version, commit, tag, and push to trigger CI release
#
# Usage:
#   ./scripts/release-version.sh           # default: --patch
#   ./scripts/release-version.sh --patch   # 1.2.3 → 1.2.4
#   ./scripts/release-version.sh --minor   # 1.2.3 → 1.3.0
#   ./scripts/release-version.sh --major   # 1.2.3 → 2.0.0
#
# What it does:
#   1. Reads the current version from Info.plist (CFBundleShortVersionString)
#   2. Bumps the requested component; resets lower components to 0
#   3. Increments CFBundleVersion (build number integer)
#   4. Commits Info.plist with a chore: message
#   5. Creates an annotated git tag  vX.Y.Z
#   6. Pushes commit + tag to origin → triggers .github/workflows/release.yml

set -euo pipefail

PLIST="Info.plist"
BUMP="${1:---patch}"

# ── Validate argument ────────────────────────────────────────────────────────
case "$BUMP" in
  --patch|--minor|--major) ;;
  *)
    echo "Usage: $0 [--patch | --minor | --major]"
    exit 1
    ;;
esac

# ── Guard: must be run from repo root ────────────────────────────────────────
if [ ! -f "$PLIST" ]; then
  echo "❌  Info.plist not found. Run this script from the repo root."
  exit 1
fi

# ── Guard: working tree must be clean ────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "❌  Working tree is dirty. Commit or stash your changes first."
  exit 1
fi

# ── Guard: on main/master branch ─────────────────────────────────────────────
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
  echo "⚠️   You are on branch '$CURRENT_BRANCH', not main/master."
  read -r -p "Continue anyway? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0
fi

# ── Read current version ──────────────────────────────────────────────────────
CURRENT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

# ── Bump ─────────────────────────────────────────────────────────────────────
case "$BUMP" in
  --major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  --minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  --patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD=$((BUILD + 1))
TAG="v${NEW_VERSION}"

# ── Guard: tag must not already exist ────────────────────────────────────────
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "❌  Tag $TAG already exists. Nothing to do."
  exit 1
fi

echo ""
echo "  Current : ${CURRENT}  (build ${BUILD})"
echo "  New     : ${NEW_VERSION}  (build ${NEW_BUILD})"
echo "  Tag     : ${TAG}"
echo ""
read -r -p "Proceed? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Update Info.plist ─────────────────────────────────────────────────────────
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString ${NEW_VERSION}" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion ${NEW_BUILD}" "$PLIST"

echo "✓ Updated Info.plist"

# ── Commit ────────────────────────────────────────────────────────────────────
git add "$PLIST"
git commit -m "chore: bump version to ${NEW_VERSION} (build ${NEW_BUILD})"

echo "✓ Committed"

# ── Annotated tag ─────────────────────────────────────────────────────────────
git tag -a "$TAG" -m "Release ${TAG}"

echo "✓ Tagged ${TAG}"

# ── Push ─────────────────────────────────────────────────────────────────────
git push origin HEAD
git push origin "$TAG"

echo ""
echo "✅  ${TAG} pushed — GitHub Actions release workflow triggered."
echo "   https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]//;s/\.git$//')/actions"
