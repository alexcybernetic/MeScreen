#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./build.sh [Release|Debug]

Builds MeScreen for the current Mac architecture and writes the signed app to:
  ./Build/MeScreen.app

Tagged Release builds also create a versioned ZIP and SHA-256 checksum in:
  ./Dist/

Environment variables:
  ARCHITECTURE     Override the target architecture (arm64 or x86_64).
  RELEASE_VERSION  Explicit archive version (for example, 1.0.0).
  SIGNING_IDENTITY Code-signing identity. Defaults to ad-hoc signing (-).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if (( $# > 1 )); then
    usage >&2
    exit 2
fi

CONFIGURATION="${1:-Release}"
case "$CONFIGURATION" in
    Debug|Release) ;;
    *)
        echo "Error: configuration must be Debug or Release." >&2
        usage >&2
        exit 2
        ;;
esac

ARCHITECTURE="${ARCHITECTURE:-$(uname -m)}"
case "$ARCHITECTURE" in
    arm64|x86_64) ;;
    *)
        echo "Error: unsupported architecture '$ARCHITECTURE'." >&2
        exit 2
        ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
DIST_DIR="$ROOT_DIR/Dist"
APP_PATH="$BUILD_DIR/MeScreen.app"
ARCHIVE_PATH=""
CHECKSUM_PATH=""
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
TEMP_ROOT="${TMPDIR:-/tmp}"
RELEASE_STAGING_DIR=""

VERSION=""
if [[ "$CONFIGURATION" == "Release" ]]; then
    VERSION="${RELEASE_VERSION:-}"
    if [[ -z "$VERSION" ]]; then
        VERSION="$(git -C "$ROOT_DIR" describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || true)"
    fi

    if [[ -n "$VERSION" ]]; then
        VERSION="${VERSION#v}"

        if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){1,2}([.-][0-9A-Za-z.-]+)?$ ]]; then
            echo "Error: invalid release version '$VERSION'." >&2
            exit 1
        fi

        if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            WORKTREE_STATUS="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=normal)"
            if [[ -n "$WORKTREE_STATUS" ]]; then
                echo "Error: refusing to create a versioned archive from an uncommitted working tree." >&2
                exit 1
            fi
        fi

        ARCHIVE_NAME="MeScreen-v$VERSION-macOS-$ARCHITECTURE.zip"
        ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
        CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

        if [[ -e "$ARCHIVE_PATH" || -e "$CHECKSUM_PATH" ]]; then
            echo "Error: release artifact already exists; refusing to overwrite it." >&2
            exit 1
        fi
    fi
fi

DERIVED_DATA_DIR="$(mktemp -d "${TEMP_ROOT%/}/MeScreenDerivedData.XXXXXX")"

cleanup() {
    rm -rf "$DERIVED_DATA_DIR"
    if [[ -n "$RELEASE_STAGING_DIR" ]]; then
        rm -rf "$RELEASE_STAGING_DIR"
    fi
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR"
rm -rf "$APP_PATH" "$BUILD_DIR/MeScreen.app.dSYM" "$BUILD_DIR/MeScreen.swiftmodule"

echo "Building MeScreen ($CONFIGURATION, $ARCHITECTURE)..."

xcodebuild \
    -quiet \
    -project "$ROOT_DIR/MeScreen.xcodeproj" \
    -scheme MeScreen \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -destination "platform=macOS,arch=$ARCHITECTURE" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    DEPLOYMENT_POSTPROCESSING=YES \
    ENABLE_CODE_COVERAGE=NO \
    build

# CONFIGURATION_BUILD_DIR also receives compiler module metadata; only the app
# and optional dSYM are useful as build artifacts here.
rm -rf "$BUILD_DIR/MeScreen.swiftmodule"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
ENTITLEMENT_DETAILS="$(codesign -d --entitlements - "$APP_PATH" 2>&1)"

entitlement_value() {
    local key="$1"
    awk -v target="$key" '
        $0 == "\t[Key] " target { found = 1; next }
        found && /\[Bool\]/ { print $NF; exit }
        found && /\[Key\]/ { exit }
    ' <<< "$ENTITLEMENT_DETAILS"
}

require_entitlement() {
    local key="$1"
    local value
    value="$(entitlement_value "$key")"
    if [[ "$value" != "true" ]]; then
        echo "Error: required entitlement '$key' is missing." >&2
        exit 1
    fi
}

reject_entitlement() {
    local key="$1"
    if [[ "$ENTITLEMENT_DETAILS" == *"[Key] $key"* ]]; then
        echo "Error: forbidden entitlement '$key' is present." >&2
        exit 1
    fi
}

require_entitlement "com.apple.security.app-sandbox"
require_entitlement "com.apple.security.device.camera"
reject_entitlement "com.apple.security.files.user-selected.read-only"

if [[ "$CONFIGURATION" == "Release" ]]; then
    reject_entitlement "com.apple.security.get-task-allow"

    BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
    EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$BUNDLE_EXECUTABLE"

    if LC_ALL=C grep -aEq '/(Users|home)/[^/[:space:]]+' "$EXECUTABLE_PATH"; then
        echo "Error: Release executable contains an absolute user path." >&2
        exit 1
    fi

    if LC_ALL=C grep -aEiq '[A-Z0-9._%+-]+@[A-Z0-9.-]+[.][A-Z]{2,}' "$EXECUTABLE_PATH"; then
        echo "Error: Release executable contains an email address." >&2
        exit 1
    fi
fi

SIGNATURE_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if [[ "$SIGNATURE_DETAILS" == *"Signature=adhoc"* ]]; then
    echo "Warning: app is ad-hoc signed and cannot be notarized or publisher-verified." >&2
else
    echo "Signing identity verified: $SIGNING_IDENTITY"
fi

if [[ "$CONFIGURATION" == "Release" ]]; then
    if [[ -z "$VERSION" ]]; then
        echo "Release build is not tagged; skipping Dist archive."
    else
        BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
        if [[ "$VERSION" != "$BUNDLE_VERSION" ]]; then
            echo "Error: archive version '$VERSION' does not match bundle version '$BUNDLE_VERSION'." >&2
            exit 1
        fi

        mkdir -p "$DIST_DIR"
        RELEASE_STAGING_DIR="$(mktemp -d "${TEMP_ROOT%/}/MeScreenArchive.XXXXXX")"
        STAGED_ARCHIVE_PATH="$RELEASE_STAGING_DIR/$ARCHIVE_NAME"

        ditto -c -k --norsrc --keepParent "$APP_PATH" "$STAGED_ARCHIVE_PATH"

        if zipinfo -1 "$STAGED_ARCHIVE_PATH" | grep -q '^__MACOSX/'; then
            echo "Error: release archive contains extended metadata." >&2
            exit 1
        fi

        mv "$STAGED_ARCHIVE_PATH" "$ARCHIVE_PATH"

        (
            cd "$DIST_DIR"
            shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
        )
    fi
fi

echo
echo "Build complete: $APP_PATH"
if [[ -n "$ARCHIVE_PATH" ]]; then
    echo "Release archive: $ARCHIVE_PATH"
    echo "SHA-256 checksum: $CHECKSUM_PATH"
fi
