#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Arthur Cissac

# Carries the settings of the official Vorssaint install over to this fork,
# through the app's own settings backup (--export-settings / --import-settings).
# Only preferences travel: the backup leaves out machine state by design, and
# this script does not copy the clipboard history or the scratchpad.
#
#   Fork/migrate-settings.sh export   1. with Vorssaint quit
#   ./build.sh --install              2. install the fork, do not open it yet
#   Fork/migrate-settings.sh import   3. then open the fork
#   Fork/migrate-settings.sh clean    4. delete the exported file
#
# FORK.md, "Migration des réglages", has the full checklist around these steps.
set -euo pipefail
cd "$(dirname "$0")/.."
source Fork/identity.sh

UPSTREAM_NAME="Vorssaint"
UPSTREAM_APP="/Applications/$UPSTREAM_NAME.app"
UPSTREAM_EXECUTABLE="$UPSTREAM_APP/Contents/MacOS/$UPSTREAM_NAME"
FORK_EXECUTABLE_NAME="${FORK_APP_NAME// /}"
FORK_APP="/Applications/$FORK_APP_NAME.app"
FORK_EXECUTABLE="$FORK_APP/Contents/MacOS/$FORK_EXECUTABLE_NAME"
# The export holds every preference, text snippets included: keep it private.
WORK_DIR="$HOME/.${FORK_EXECUTABLE_NAME:l}-migration"
EXPORT_FILE="$WORK_DIR/settings.plist"
PLIST_BUDDY=/usr/libexec/PlistBuddy

# Preferences that must not come along as they are:
#   launchAtLoginWanted       both apps would open at login with the same shortcuts;
#   *SharingEnabled           online sharing uploads to upstream's server.
FORCED_OFF=(launchAtLoginWanted screenshotSharingEnabled recorderSharingEnabled)

stop() { print -u2 "✗ $1"; exit 1; }
is_running() { pgrep -x "$1" >/dev/null 2>&1; }

export_settings() {
    [[ -x "$UPSTREAM_EXECUTABLE" ]] || stop "$UPSTREAM_APP is not installed: nothing to migrate."
    is_running "$UPSTREAM_NAME" && stop "Quit $UPSTREAM_NAME first, so its latest settings are saved."
    mkdir -p "$WORK_DIR"
    chmod 700 "$WORK_DIR"
    "$UPSTREAM_EXECUTABLE" --export-settings "$EXPORT_FILE"
    chmod 600 "$EXPORT_FILE"
    plutil -lint "$EXPORT_FILE" >/dev/null || stop "The export is not a valid property list."
    "$PLIST_BUDDY" -c 'Print :vorssaintBackupVersion' "$EXPORT_FILE" >/dev/null 2>&1 \
        || stop "The export does not look like a settings backup."
    local key
    for key in "${FORCED_OFF[@]}"; do
        "$PLIST_BUDDY" -c "Set :settings:$key false" "$EXPORT_FILE" 2>/dev/null \
            || "$PLIST_BUDDY" -c "Add :settings:$key bool false" "$EXPORT_FILE"
    done
    # For a dictionary, `plutil -extract … raw` prints one key per line.
    local count
    count="$(/usr/bin/plutil -extract settings raw -o - "$EXPORT_FILE" | wc -l | tr -d ' ')"
    print "✓ Exported to $EXPORT_FILE"
    print "  ($count preferences; forced off: ${FORCED_OFF[*]})"
    print "  Next: ./build.sh --install, then Fork/migrate-settings.sh import, before opening $FORK_APP_NAME."
}

import_settings() {
    [[ -f "$EXPORT_FILE" ]] || stop "No export found. Run: Fork/migrate-settings.sh export"
    [[ -x "$FORK_EXECUTABLE" ]] || stop "$FORK_APP is not installed. Run: ./build.sh --install"
    is_running "$FORK_EXECUTABLE_NAME" && stop "Quit $FORK_APP_NAME first: a running app saves its own settings back."
    "$FORK_EXECUTABLE" --import-settings "$EXPORT_FILE"
    local key value
    for key in "${FORCED_OFF[@]}"; do
        value="$(defaults read "$FORK_BUNDLE_ID" "$key" 2>/dev/null || print missing)"
        [[ "$value" == 0 ]] || stop "$key is '$value' in $FORK_BUNDLE_ID, expected 0."
    done
    print "✓ Imported into $FORK_BUNDLE_ID"
    if is_running "$UPSTREAM_NAME"; then
        print "  ⚠ $UPSTREAM_NAME is running: quit it before opening $FORK_APP_NAME."
    fi
    print "  Next: open $FORK_APP_NAME, grant its permissions again, then Fork/migrate-settings.sh clean."
}

clean() {
    if [[ -f "$EXPORT_FILE" ]]; then
        rm "$EXPORT_FILE"
        rmdir "$WORK_DIR" 2>/dev/null || true
        print "✓ Removed $EXPORT_FILE"
    else
        print "Nothing to remove."
    fi
}

case "${1:-}" in
    export) export_settings ;;
    import) import_settings ;;
    clean)  clean ;;
    *)
        print -u2 "usage: Fork/migrate-settings.sh export | import | clean"
        exit 2
        ;;
esac
