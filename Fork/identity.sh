# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Arthur Cissac
#
# The fork's identity, defined once. Everything else derives from this file:
#   - build.sh sources it through Fork/build-hooks.zsh;
#   - Fork/brand.py parses it, so keep to plain KEY="value" lines: no shell
#     logic, no variable expansion.
#
# To rename the fork, change the values below and rebuild. Changing
# FORK_BUNDLE_ID makes a new app as far as macOS is concerned: permissions,
# preferences, Application Support and the fan helper registration start over.

FORK_APP_NAME="Hublot"
FORK_BUNDLE_ID="agency.nexflow.hublot"
FORK_SOURCE_URL="https://github.com/ArthurCissac/hublot"

# Hublot's own version, shown in the app and compared with the tags of the
# releases on FORK_SOURCE_URL (v0.2.0, v0.3.0-beta.1…). Raise it for every
# release, with its section in Fork/CHANGELOG.md.
FORK_VERSION="0.3.0"

# The Apple team of the Developer ID certificate the fork is signed with. The
# app and its privileged fan helper only talk to each other when both ends are
# signed by this team, so it must match the certificate build.sh picks. A
# renewed certificate keeps the same team: nothing to change here.
FORK_TEAM_ID="8222G9B2DZ"
