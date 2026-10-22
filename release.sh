#!/usr/bin/env bash

# Cuts a Nudget release from a Mac that has the Developer ID certificate:
# builds a signed universal app, notarizes and staples it, zips it into dist/,
# and publishes it as a GitHub release for the tag v<version>.
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your login keychain
#      (Xcode > Settings > Accounts > Manage Certificates > +).
#   2. Notarization credentials stored in the keychain, using an app-specific
#      password from account.apple.com:
#        xcrun notarytool store-credentials nudget --apple-id YOU --team-id TEAMID
#   3. The GitHub CLI, signed in (gh auth login). Without it the script still
#      builds and notarizes, then prints the manual publish steps.
#
# Usage:
#   ./release.sh 1.0.0

set -euo pipefail

version="${1:-}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: ./release.sh <version>, e.g. ./release.sh 1.0.0" >&2
    exit 1
fi

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$project_dir/build/Nudget.app"
dist_dir="$project_dir/dist"
zip_name="Nudget-$version.zip"
zip_path="$dist_dir/$zip_name"
tag="v$version"
profile="${NOTARY_PROFILE:-nudget}"

cd "$project_dir"

if [ -n "$(git status --porcelain)" ]; then
    echo "The working tree has uncommitted changes. Commit or stash them first." >&2
    exit 1
fi
git fetch -q origin main
if ! git merge-base --is-ancestor HEAD origin/main; then
    echo "HEAD is not on origin/main yet. Push your commits first." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already exists." >&2
    exit 1
fi

identity="${CODESIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [ -z "$identity" ]; then
    echo "No 'Developer ID Application' identity found in your keychain." >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "No notarization credentials stored under the profile '$profile'. Run:" >&2
    echo "  xcrun notarytool store-credentials $profile --apple-id YOU --team-id TEAMID" >&2
    exit 1
fi

echo "Building $version, signing as: $identity"
CODESIGN_IDENTITY="$identity" \
NUDGET_VERSION="$version" \
NUDGET_BUILD="$(git rev-list --count HEAD)" \
    ./build.sh

rm -rf "$dist_dir"
mkdir -p "$dist_dir"

echo "Submitting for notarization (this usually takes a minute or two)..."
ditto -c -k --keepParent "$app_dir" "$zip_path"
submission="$(xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait --output-format json || true)"
status="$(printf '%s' "$submission" | plutil -extract status raw -o - - 2>/dev/null || true)"
if [ "$status" != "Accepted" ]; then
    submission_id="$(printf '%s' "$submission" | plutil -extract id raw -o - - 2>/dev/null || true)"
    if [ -n "$submission_id" ]; then
        xcrun notarytool log "$submission_id" --keychain-profile "$profile"
    fi
    echo "Notarization failed (status: ${status:-unknown})." >&2
    exit 1
fi

xcrun stapler staple "$app_dir"
spctl --assess --type exec --verbose=2 "$app_dir"

# Re-zip so the download carries the staple.
rm -f "$zip_path"
ditto -c -k --keepParent "$app_dir" "$zip_path"
(cd "$dist_dir" && shasum -a 256 "$zip_name" > "$zip_name.sha256")

if ! command -v gh >/dev/null 2>&1; then
    echo "Built and notarized $zip_path."
    echo "The GitHub CLI is not installed, so publish by hand:"
    echo "  git tag -a $tag -m 'Nudget $version' && git push origin $tag"
    echo "  then upload dist/$zip_name at https://github.com/mwardio/nudget/releases/new?tag=$tag"
    exit 0
fi

git tag -a "$tag" -m "Nudget $version"
git push origin "$tag"
gh release create "$tag" "$zip_path" "$zip_path.sha256" \
    --verify-tag \
    --title "Nudget $version" \
    --generate-notes
echo "Published $tag."
