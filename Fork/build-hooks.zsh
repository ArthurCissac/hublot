# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Arthur Cissac
#
# The fork's hooks into build.sh, sourced right after build.sh picks the
# upstream identity. build.sh itself only gains one-line calls to what is
# defined here, so a rebase on upstream rarely conflicts.
#
# Sourcing this file sets variables, defines functions and, outside `--test`,
# checks the signing certificate. `--test` runs read it too, and must keep
# compiling and checking the original sources whatever the keychain holds.

source Fork/identity.sh

# --- Identity ----------------------------------------------------------------
# build.sh has just set upstream's name, executable and bundle id for the
# requested variant; replace them with the fork's. Everything build.sh derives
# afterwards follows from these three: the fan helper and Now Playing adapter
# ids, the bundle path, the install destination, the process it stops.
if (( DEV )); then
    APP_NAME="$FORK_APP_NAME (Developer)"
    EXECUTABLE="${FORK_APP_NAME// /}Developer"
    APP_BUNDLE_ID="$FORK_BUNDLE_ID.dev"
else
    APP_NAME="$FORK_APP_NAME"
    EXECUTABLE="${FORK_APP_NAME// /}"
    APP_BUNDLE_ID="$FORK_BUNDLE_ID"
fi

# --- Artwork -------------------------------------------------------------------
# Upstream's name and logo are trademarks (TRADEMARKS.md): the fork ships its
# own. Tools/MakeIcon.swift and the adaptive icon step read this folder instead
# of Resources/Brand. Fork/Tools/MakePlaceholderBrand.swift redraws its contents.
export BRAND_DIR="Fork/Brand"

# --- Signing guard -------------------------------------------------------------
# build.sh signs with the first "Developer ID Application" identity it finds
# and, when there is none, quietly falls back to a local self-signed identity,
# then to an ad-hoc signature. For the fork that fallback is a trap: an expired
# or missing certificate would change the signature of the installed app without
# a word, macOS would drop its Accessibility and Screen Recording grants, and
# the fan helper would refuse an app that is no longer signed by FORK_TEAM_ID.
# So a build stops here instead, before compiling anything.
#
# Escape hatch: FORK_ALLOW_LOCAL_SIGNING=1 lets a `--dev` build go on with the
# local identity, for working without the certificate at hand. It never covers
# `--install`: nothing signed that way may land in /Applications.
fork_require_signing_identity() {
    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' | head -1 || true)"
    if [[ "$identity" == *"($FORK_TEAM_ID)"* ]]; then
        return 0
    fi
    if [[ "${FORK_ALLOW_LOCAL_SIGNING:-0}" == 1 ]] && (( DEV && ! INSTALL )); then
        print -u2 "  ⚠ FORK_ALLOW_LOCAL_SIGNING=1: no Developer ID for team $FORK_TEAM_ID, signing this"
        print -u2 "    Developer build locally. Its permissions will not carry over to a properly signed build."
        return 0
    fi
    print -u2 "✗ No valid Developer ID Application certificate for team $FORK_TEAM_ID in the keychain."
    if [[ -n "$identity" ]]; then
        print -u2 "  Found instead:${identity#*\)}"
    fi
    print -u2 "  $FORK_APP_NAME is signed with that certificate; any other signature would make macOS"
    print -u2 "  forget the app's permissions and lock it out of its fan helper. See FORK.md, \"Signature\"."
    if [[ "${FORK_ALLOW_LOCAL_SIGNING:-0}" == 1 ]]; then
        print -u2 "  FORK_ALLOW_LOCAL_SIGNING=1 only covers --dev builds that are not installed."
    else
        print -u2 "  To build the Developer variant anyway, without installing it:"
        print -u2 "    FORK_ALLOW_LOCAL_SIGNING=1 ./build.sh --dev"
    fi
    exit 1
}
(( TEST )) || fork_require_signing_identity

# --- Identity pass over the sources --------------------------------------------
# Where the renamed mirror of Sources/Vorssaint lives. It sits under
# build/objects because a release build empties the rest of build/ first.
FORK_APP_SRC="build/objects/fork-sources"

# Points the app compilation at the renamed mirror (see Fork/brand.py).
fork_brand_sources() {
    python3 Fork/brand.py sources Sources/Vorssaint "$FORK_APP_SRC"
    APP_SOURCES=("$FORK_APP_SRC"/**/*.swift)
}

# --- Tests ---------------------------------------------------------------------
# The harness compiles an explicit list of upstream sources plus Tests/*.swift.
# The fork's pure logic (Sources/Vorssaint/Fork/Core) and its tests (Fork/Tests)
# join that list here, so build.sh only gains a one-line call. The call is not
# optional: upstream sources the harness compiles (Core/Defaults.swift) name
# fork keys declared in that folder.
fork_test_sources() {
    TEST_SOURCES+=(Sources/Vorssaint/Fork/Core/*.swift Fork/Tests/*.swift)
}

# --- Identity pass over the staged bundle --------------------------------------
# Renames the visible name in the staged Info.plist and InfoPlist.strings (the
# permission prompts), and records where this fork's source lives so the app
# can link to it. The files under Resources/ stay as upstream ships them.
fork_brand_bundle_resources() {
    python3 Fork/brand.py resources "$1"
    /usr/libexec/PlistBuddy -c "Add :ForkSourceURL string $FORK_SOURCE_URL" "$1/Contents/Info.plist"
    # Hublot's own version, the upstream one it is based on kept beside it,
    # and Hublot's changelog for What's New and the release notes page.
    if [[ -n "${FORK_VERSION:-}" ]]; then
        local base
        base=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist")
        /usr/libexec/PlistBuddy -c "Add :ForkBaseVersion string $base" "$1/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $FORK_VERSION" "$1/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $FORK_VERSION" "$1/Contents/Info.plist"
    fi
    [[ -f Fork/CHANGELOG.md ]] && cp Fork/CHANGELOG.md "$1/Contents/Resources/CHANGELOG.md"
    # The Care window's pictures (lot 9j), made for Hublot.
    if [[ -d Fork/Resources/Care ]]; then
        mkdir -p "$1/Contents/Resources/ForkCare"
        cp Fork/Resources/Care/*.jpg "$1/Contents/Resources/ForkCare/"
    fi
    # Only a published build (Fork/release.sh) updates itself; one installed
    # from a work branch never replaces itself with a public release.
    if [[ "${HUBLOT_RELEASE:-0}" == "1" ]]; then
        /usr/libexec/PlistBuddy -c "Add :ForkReleaseBuild bool true" "$1/Contents/Info.plist"
    fi
    return 0
}
