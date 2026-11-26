#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Arthur Cissac
"""Build-time identity pass for the fork.

Upstream's name and identifiers appear in about 1,500 lines of user-visible
text that upstream edits constantly. Rewriting those files in the repository
would conflict on every rebase, so the fork leaves them untouched and renames
at build time instead: this tool writes a mirror of the app sources in which
the identity rules below have been applied, and build.sh compiles the mirror.
New upstream strings are therefore renamed automatically, and the tests keep
compiling the original sources.

Usage:
  brand.py sources <source-dir> <mirror-dir>   write or refresh the mirror
  brand.py resources <staged-app-bundle>       rename the texts of a staged bundle
  brand.py audit [<source-dir>]                report what the rules would touch
  brand.py selftest                            check the rules themselves

The fork's identity comes from Fork/identity.sh, the only place it is written.
"""

import json
import os
import re
import sys
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parent.parent
IDENTITY_FILE = REPOSITORY / "Fork" / "identity.sh"

# Fork-owned Swift sources live in this subfolder of the app sources. They are
# mirrored verbatim: they name upstream on purpose (attribution, coexistence).
FORK_SOURCE_FOLDER = "Fork"

# Mirror files carry their own suffix. Swift derives `#fileID` from the module
# and the file's base name, and warns when two different paths yield the same
# one: a mirror file named like its original would collide with the path its
# `#sourceLocation` directive declares, once per file in every compiler job.
MIRROR_SUFFIX = ".mirror.swift"

# The entry point is the exception: Swift only accepts top-level code in a file
# named main.swift, so its mirror keeps that name and gets no directive.
# Diagnostics in main.swift therefore show the mirror's path.
ENTRY_POINT = "main.swift"

# Upstream services the fork must never send data to. Requests to an ".invalid"
# host fail at name resolution (RFC 2606), so nothing leaves the machine.
DISABLED_HOST = "upstream-service-disabled.invalid"

IDENTITY_KEYS = {
    "FORK_APP_NAME": re.compile(r"[A-Za-z0-9][A-Za-z0-9 ._-]*"),
    "FORK_BUNDLE_ID": re.compile(r"[A-Za-z0-9]+(\.[A-Za-z0-9-]+)+"),
    "FORK_SOURCE_URL": re.compile(r"https://[A-Za-z0-9./_-]+"),
}
OPTIONAL_IDENTITY_KEYS = {
    "FORK_VERSION": re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?"),
    "FORK_TEAM_ID": re.compile(r"[A-Z0-9]{10}"),
}


def fail(message):
    print(f"brand.py: {message}", file=sys.stderr)
    sys.exit(1)


def load_identity(path=IDENTITY_FILE):
    """Reads the KEY="value" lines of Fork/identity.sh.

    Values are validated because they are spliced into Swift string literals
    and property lists: a quote or a backslash would change the code.
    """
    assignment = re.compile(r'^([A-Z][A-Z0-9_]*)="([^"]*)"\s*$')
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = assignment.match(line)
        if match:
            values[match.group(1)] = match.group(2)
    for key, shape in IDENTITY_KEYS.items():
        if key not in values:
            fail(f"{path.name} does not define {key}")
        if not shape.fullmatch(values[key]):
            fail(f"{path.name}: {key} has an unexpected value: {values[key]!r}")
    for key, shape in OPTIONAL_IDENTITY_KEYS.items():
        if key in values and not shape.fullmatch(values[key]):
            fail(f"{path.name}: {key} has an unexpected value: {values[key]!r}")
    return values


def is_copyright_line(line):
    return "©" in line or "Copyright" in line


class Rule:
    def __init__(self, name, pattern, replacement, skips_copyright=False):
        self.name = name
        self.pattern = re.compile(pattern)
        self.replacement = replacement
        self.skips_copyright = skips_copyright


def build_rules(identity):
    """The identity rules, applied in this order to every line.

    Order matters only for the first two: the full bundle id is rewritten
    before the bare prefix, so "com.vorssaint.utils.dev" keeps its ".dev".
    """
    bundle_id = identity["FORK_BUNDLE_ID"]
    rules = [
        # The app's own bundle id, also where the app recognises itself.
        Rule("bundle-id", r"(?<![A-Za-z0-9_-])com\.vorssaint\.utils(?![A-Za-z0-9_-])", bundle_id),
        # The reverse-DNS prefix: queue labels, pasteboard types, the checks
        # that protect the app's own files from its cleaner and uninstaller.
        Rule("id-prefix", r"(?<![A-Za-z0-9_-])com\.vorssaint(?![A-Za-z0-9_-])", bundle_id),
        # Feedback and online sharing post to upstream's server.
        Rule("upstream-host", r"screenshots\.vorssaint\.com", DISABLED_HOST),
        # The visible name. An uppercase letter, a digit or an underscore right
        # after it means a compound identifier ("VorssaintBuildCommit"), left
        # alone; a lowercase suffix is a declension ("Vorssaintu"), renamed.
        # Copyright lines keep the original author's name.
        Rule("app-name", r"(?<![A-Za-z0-9_])Vorssaint(?![A-Z0-9_])",
             identity["FORK_APP_NAME"], skips_copyright=True),
    ]
    if "FORK_TEAM_ID" in identity:
        # Upstream's Apple team, required of both ends of the fan helper's XPC
        # connection. The fork is signed by its own team.
        rules.append(Rule("team-id", r"(?<![A-Z0-9])3D485NHW29(?![A-Z0-9])", identity["FORK_TEAM_ID"]))
    return rules


STRING_START = re.compile(r'(#*)("""|")')


def text_mask(source):
    """Marks every character that sits inside a string literal or a comment.

    A small Swift lexer: line and nested block comments, single-line and
    multi-line strings, raw strings ("#"), and interpolations, whose content
    is code again. It only has to be right enough to tell a renamed string
    from a renamed identifier; an unterminated single-line string resyncs at
    the end of its line.
    """
    length = len(source)
    mask = bytearray(length)
    stack = []  # ["string", multiline, hashes] or ["interpolation", depth]
    index = 0
    while index < length:
        if stack and stack[-1][0] == "string":
            _, multiline, hashes = stack[-1]
            quote = '"""' if multiline else '"'
            closing = quote + "#" * hashes
            if source.startswith(closing, index):
                index += len(closing)
                stack.pop()
                continue
            if source[index] == "\\" and source.startswith("#" * hashes, index + 1):
                after = index + 1 + hashes
                if after < length and source[after] == "(":
                    stack.append(["interpolation", 1])
                    index = after + 1
                    continue
                end = min(after + 1, length)
                mask[index:end] = b"\x01" * (end - index)
                index = end
                continue
            if not multiline and source[index] == "\n":
                stack.pop()
                index += 1
                continue
            mask[index] = 1
            index += 1
            continue

        if source.startswith("//", index):
            end = source.find("\n", index)
            end = length if end == -1 else end
            mask[index:end] = b"\x01" * (end - index)
            index = end
            continue
        if source.startswith("/*", index):
            depth, end = 1, index + 2
            while end < length and depth:
                if source.startswith("/*", end):
                    depth, end = depth + 1, end + 2
                elif source.startswith("*/", end):
                    depth, end = depth - 1, end + 2
                else:
                    end += 1
            mask[index:end] = b"\x01" * (end - index)
            index = end
            continue
        opening = STRING_START.match(source, index)
        if opening:
            stack.append(["string", opening.group(2) == '"""', len(opening.group(1))])
            index = opening.end()
            continue
        if stack and stack[-1][0] == "interpolation":
            if source[index] == "(":
                stack[-1][1] += 1
            elif source[index] == ")":
                stack[-1][1] -= 1
                if stack[-1][1] == 0:
                    stack.pop()
        index += 1
    return mask


def apply_rules(source, rules, check_code=True):
    """Returns (renamed text, per-rule counts, matches found in code).

    Replacements never add or remove a line, so compiler diagnostics keep the
    original line numbers. A match outside a literal or a comment would rename
    an identifier: it is reported instead of trusted.
    """
    counts = {rule.name: 0 for rule in rules}
    in_code = []
    # Most files mention none of this: skip the lexer and the line walk.
    if not any(rule.pattern.search(source) for rule in rules):
        return source, counts, in_code
    mask = text_mask(source) if check_code else None
    lines = source.split("\n")
    offset = 0
    for number, line in enumerate(lines, start=1):
        original = line
        for rule in rules:
            if rule.skips_copyright and is_copyright_line(original):
                continue
            if check_code:
                for match in rule.pattern.finditer(original):
                    start, end = offset + match.start(), offset + match.end()
                    if not all(mask[start:end]):
                        in_code.append((number, rule.name, original.strip()))
            line, replaced = rule.pattern.subn(rule.replacement, line)
            counts[rule.name] += replaced
        lines[number - 1] = line
        offset += len(original) + 1
    return "\n".join(lines), counts, in_code


def swift_sources(source_dir):
    return sorted(path for path in source_dir.rglob("*.swift") if path.is_file())


def write_if_changed(destination, content):
    """Leaves an identical file untouched, so the compiler does not rebuild it."""
    if destination.exists() and destination.read_text(encoding="utf-8") == content:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, destination)
    return True


def mirror_sources(source_dir, mirror_dir, rules):
    """Writes the renamed mirror; returns (files, written, removed, problems)."""
    expected, written, problems = set(), 0, []
    for source_path in swift_sources(source_dir):
        relative = source_path.relative_to(source_dir)
        text = source_path.read_text(encoding="utf-8")
        if relative.parts[0] != FORK_SOURCE_FOLDER:
            text, _, in_code = apply_rules(text, rules)
            problems += [(source_path, number, name, line) for number, name, line in in_code]
        if relative.name == ENTRY_POINT:
            destination = mirror_dir / relative
        else:
            # Diagnostics and #file then name the real file, not the mirror.
            text = f"#sourceLocation(file: {json.dumps(source_path.as_posix())}, line: 1)\n" + text
            destination = mirror_dir / relative.with_name(relative.stem + MIRROR_SUFFIX)
        expected.add(destination)
        if write_if_changed(destination, text):
            written += 1
    removed = 0
    if mirror_dir.is_dir():
        for stale in sorted(mirror_dir.rglob("*.swift")):
            if stale not in expected:
                stale.unlink()
                removed += 1
        for folder in sorted((p for p in mirror_dir.rglob("*") if p.is_dir()), reverse=True):
            if not any(folder.iterdir()):
                folder.rmdir()
    return len(expected), written, removed, problems


def report_problems(problems):
    for path, number, name, line in problems:
        print(f"{path}:{number}: error: rule '{name}' matches outside a string literal or a "
              f"comment: {line}", file=sys.stderr)
    fail(f"{len(problems)} match(es) in code. Renaming an identifier would change the program: "
         "rename it upstream-side or tighten the rule.")


def command_sources(arguments):
    if len(arguments) != 2:
        fail("usage: brand.py sources <source-dir> <mirror-dir>")
    source_dir, mirror_dir = Path(arguments[0]), Path(arguments[1])
    if not source_dir.is_dir():
        fail(f"{source_dir} is not a directory")
    rules = build_rules(load_identity())
    files, written, removed, problems = mirror_sources(source_dir, mirror_dir, rules)
    if problems:
        report_problems(problems)
    print(f"  identity pass: {files} files, {written} rewritten, {removed} removed -> {mirror_dir}")


# Permission prompts the fork words itself, where it uses a permission for
# something upstream does not: upstream's camera text promises that nothing is
# recorded, and the fork's camera bubble goes into screen recordings. {name} is
# the app's name. French and English only, as for every text the fork adds:
# the other languages show the English one.
BUNDLE_TEXTS = {
    "NSCameraUsageDescription": {
        "en": "{name} shows your camera in the preview window you open and, when you turn the camera on "
              "for a screen recording, in a bubble that is part of the video. Nothing leaves your Mac.",
        "fr": "{name} affiche votre caméra dans la fenêtre d’aperçu que vous ouvrez et, quand vous activez "
              "la caméra pour un enregistrement d’écran, dans une bulle qui fait partie de la vidéo. "
              "Rien ne quitte votre Mac.",
    },
}


# Keys the fork adds to the staged Info.plist, which upstream does not set:
# the local network prompt (macOS 15 and later ask before an app reaches a
# device at home, here Home Assistant, ForkHome) and plain http to local
# hosts only (NSAllowsLocalNetworking: `.local` names, single labels and
# local addresses; every other host still needs https).
BUNDLE_ADDITIONS = {
    "NSLocalNetworkUsageDescription": {
        "en": "{name} connects to your Home Assistant and your 3D printer on your local network to show and "
              "control the devices you choose.",
        "fr": "{name} se connecte à votre Home Assistant et à votre imprimante 3D sur votre réseau local pour "
              "afficher et piloter les appareils que vous choisissez.",
    },
}
LOCAL_NETWORKING = ("\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsLocalNetworking</key>\n"
                    "\t\t<true/>\n\t</dict>\n")


def xml_escape(value):
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def add_bundle_entries(targets, name):
    """Adds the fork's own keys to a staged bundle. Returns how many files it changed.

    Running it again on the same bundle changes nothing; a key upstream sets
    itself stops the build, so its text is reviewed instead of overwritten.
    """
    changed = 0
    for target in targets:
        text = target.read_text(encoding="utf-8")
        updated = text
        if target.name == "Info.plist":
            insert = ""
            for key, texts in BUNDLE_ADDITIONS.items():
                ours = xml_escape(texts["en"].format(name=name))
                if f"<key>{key}</key>" not in updated:
                    insert += f"\t<key>{key}</key>\n\t<string>{ours}</string>\n"
                elif ours not in updated:
                    fail(f"{target}: upstream now sets {key}: review BUNDLE_ADDITIONS in Fork/brand.py")
            if "<key>NSAllowsLocalNetworking</key>" not in updated:
                if "<key>NSAppTransportSecurity</key>" in updated:
                    fail(f"{target}: upstream now sets NSAppTransportSecurity: merge NSAllowsLocalNetworking "
                         "into it in Fork/brand.py")
                insert += LOCAL_NETWORKING
            end = updated.rfind("</dict>")
            if end < 0:
                fail(f"{target}: no root dictionary to add the fork's keys to")
            updated = updated[:end] + insert + updated[end:]
        else:
            language = target.parent.name.removesuffix(".lproj")
            for key, texts in BUNDLE_ADDITIONS.items():
                if language in texts and language != "en" and f'"{key}"' not in updated:
                    value = texts[language].format(name=name).replace("\\", "\\\\").replace('"', '\\"')
                    updated = updated.rstrip("\n") + f'\n"{key}" = "{value}";\n'
        if updated != text:
            target.write_text(updated, encoding="utf-8")
            changed += 1
    return changed


def set_plist_string(text, key, value):
    """Replaces the <string> that follows <key>key</key> in an XML property list.

    Returns None when the key is not there.
    """
    pattern = re.compile(r"(<key>" + re.escape(key) + r"</key>\s*<string>)(.*?)(</string>)", re.S)
    if not pattern.search(text):
        return None
    escaped = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return pattern.sub(lambda match: match.group(1) + escaped + match.group(3), text, count=1)


def set_strings_value(text, key, value):
    """Replaces the value of "key" = "..."; in a .strings file. None when the key is not there."""
    pattern = re.compile(r'("' + re.escape(key) + r'"\s*=\s*")((?:[^"\\]|\\.)*)(";)')
    if not pattern.search(text):
        return None
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return pattern.sub(lambda match: match.group(1) + escaped + match.group(3), text, count=1)


def reword_bundle_texts(targets, name):
    """Puts the fork's own permission prompts in a staged bundle. Returns how many it wrote."""
    reworded = 0
    for key, texts in BUNDLE_TEXTS.items():
        for target in targets:
            text = target.read_text(encoding="utf-8")
            if target.name == "Info.plist":
                # The base text, shown in every language without one of its own.
                updated = set_plist_string(text, key, texts["en"].format(name=name))
                if updated is None:
                    fail(f"{target}: no {key} to reword. Upstream changed its permission texts: "
                         "review BUNDLE_TEXTS in Fork/brand.py")
            else:
                language = target.parent.name.removesuffix(".lproj")
                updated = set_strings_value(text, key, texts.get(language, texts["en"]).format(name=name))
                if updated is None:
                    continue  # this language then shows the base text
            if updated != text:
                target.write_text(updated, encoding="utf-8")
            reworded += 1
    return reworded


def command_resources(arguments):
    """Renames the visible name in a staged bundle's Info.plist and InfoPlist.strings,
    then puts in the permission prompts the fork words itself.

    Only the name rule applies here: build.sh sets the identifiers itself, and
    the copyright line keeps the original author.
    """
    if len(arguments) != 1:
        fail("usage: brand.py resources <staged-app-bundle>")
    bundle = Path(arguments[0])
    contents = bundle / "Contents"
    if not (contents / "Info.plist").is_file():
        fail(f"{bundle} is not a staged app bundle")
    name_rule = [rule for rule in build_rules(load_identity()) if rule.name == "app-name"]
    targets = [contents / "Info.plist"] + sorted(contents.glob("Resources/*.lproj/InfoPlist.strings"))
    renamed = 0
    for target in targets:
        text = target.read_text(encoding="utf-8")
        updated, counts, _ = apply_rules(text, name_rule, check_code=False)
        if updated != text:
            target.write_text(updated, encoding="utf-8")
        renamed += counts["app-name"]
    reworded = reword_bundle_texts(targets, load_identity()["FORK_APP_NAME"])
    added = add_bundle_entries(targets, load_identity()["FORK_APP_NAME"])
    print(f"  identity pass: {renamed} names renamed, {reworded} permission texts reworded, "
          f"{added} files given the fork's own keys in {len(targets)} bundle resource files")


def command_audit(arguments):
    source_dir = Path(arguments[0]) if arguments else REPOSITORY / "Sources" / "Vorssaint"
    rules = build_rules(load_identity())
    totals = {rule.name: 0 for rule in rules}
    touched, problems = 0, []
    sources = swift_sources(source_dir)
    for source_path in sources:
        if source_path.relative_to(source_dir).parts[0] == FORK_SOURCE_FOLDER:
            continue
        text = source_path.read_text(encoding="utf-8")
        _, counts, in_code = apply_rules(text, rules)
        problems += [(source_path, number, name, line) for number, name, line in in_code]
        if any(counts.values()):
            touched += 1
        for name, count in counts.items():
            totals[name] += count
    print(f"{len(sources)} Swift files under {source_dir}, {touched} touched by the identity pass")
    for name, count in totals.items():
        print(f"  {name:<14} {count} replacement(s)")
    if problems:
        report_problems(problems)
    print("no match outside string literals and comments")


def command_selftest(_arguments):
    identity = {"FORK_APP_NAME": "Hublot", "FORK_BUNDLE_ID": "agency.nexflow.hublot",
                "FORK_SOURCE_URL": "https://example.invalid/fork", "FORK_TEAM_ID": "ABCDE12345"}
    rules = build_rules(identity)
    cases = [
        # The visible name, including punctuation and declensions around it.
        ('title: "Vorssaint"', 'title: "Hublot"'),
        ('"Sobre o Vorssaint"', '"Sobre o Hublot"'),
        ('"Vorssaint: ativo"', '"Hublot: ativo"'),
        ('"Vorssaint-Einstellungen"', '"Hublot-Einstellungen"'),
        ('"Vorssaint.app"', '"Hublot.app"'),
        ('"nastavení Vorssaintu"', '"nastavení Hublotu"'),
        ('"Vorssaint (Developer)"', '"Hublot (Developer)"'),
        # Compound identifiers are not the name.
        ('keepAwakeActiveIconVorssaint: "x"', 'keepAwakeActiveIconVorssaint: "x"'),
        ('"VorssaintBuildCommit"', '"VorssaintBuildCommit"'),
        ('"VorssaintMenuBarItem"', '"VorssaintMenuBarItem"'),
        ('"libVorssaintNowPlaying.dylib"', '"libVorssaintNowPlaying.dylib"'),
        ('"vorssaintBackupVersion"', '"vorssaintBackupVersion"'),
        # Upstream keeps its copyright and its own links.
        ('static let copyright = "© 2026 Vorssaint"', 'static let copyright = "© 2026 Vorssaint"'),
        ('// Copyright (C) 2026 Vorssaint', '// Copyright (C) 2026 Vorssaint'),
        ('"https://github.com/vorssaint/vorssaint-utils"', '"https://github.com/vorssaint/vorssaint-utils"'),
        ('"https://vorssaint.com"', '"https://vorssaint.com"'),
        # Identifiers.
        ('"com.vorssaint.utils"', '"agency.nexflow.hublot"'),
        ('"com.vorssaint.utils.dev"', '"agency.nexflow.hublot.dev"'),
        ('"com.vorssaint.utils.fan-control"', '"agency.nexflow.hublot.fan-control"'),
        ('hasPrefix("com.vorssaint")', 'hasPrefix("agency.nexflow.hublot")'),
        ('label: "com.vorssaint.metrics"', 'label: "agency.nexflow.hublot.metrics"'),
        ('"xcom.vorssaint.utils"', '"xcom.vorssaint.utils"'),
        ('"https://screenshots.vorssaint.com/v1/feedback"',
         f'"https://{DISABLED_HOST}/v1/feedback"'),
        ('static let teamID = "3D485NHW29"', 'static let teamID = "ABCDE12345"'),
    ]
    failures = 0
    for before, expected in cases:
        after, _, _ = apply_rules(before, rules)
        if after != expected:
            print(f"  FAIL  {before!r}\n        expected {expected!r}\n        got      {after!r}")
            failures += 1
        again, _, _ = apply_rules(after, rules)
        if again != after:
            print(f"  FAIL  not idempotent: {before!r} -> {after!r} -> {again!r}")
            failures += 1

    # Renaming never moves a line.
    sample = '// Vorssaint\nlet a = "Vorssaint"\n/* Vorssaint\n */\nlet b = """\n  Vorssaint\n  """\n'
    renamed, counts, in_code = apply_rules(sample, rules)
    if renamed.count("\n") != sample.count("\n") or counts["app-name"] != 4 or in_code:
        print(f"  FAIL  multi-line sample: {counts} {in_code}")
        failures += 1

    # A match in code is reported, including inside an interpolation.
    for code, expected_hits in [
        ("let x = Vorssaint.shared", 1),
        ('let x = "a \\(Vorssaint.shared) b"', 1),
        ('let x = "a \\(name) Vorssaint"', 0),
        ('let x = #"raw \\(Vorssaint)"#', 0),
        ('let x = "escaped \\" Vorssaint"', 0),
        ("/* outer /* inner */ Vorssaint */", 0),
        ('let x = "" // Vorssaint', 0),
    ]:
        _, _, hits = apply_rules(code, rules)
        if len(hits) != expected_hits:
            print(f"  FAIL  code detection: {code!r} -> {len(hits)} hit(s), expected {expected_hits}")
            failures += 1

    # The fork's own permission prompts: one value replaced, nothing else touched.
    plist = "\t<key>NSCameraUsageDescription</key>\n\t<string>old</string>\n\t<key>Other</key>\n\t<string>old</string>\n"
    strings = '"NSCameraUsageDescription" = "old \\"quoted\\" text";\n"Other" = "old";\n'
    text_cases = [
        (set_plist_string(plist, "NSCameraUsageDescription", "a < b & c"),
         plist.replace("<string>old</string>", "<string>a &lt; b &amp; c</string>", 1)),
        (set_plist_string(plist, "NSMissing", "x"), None),
        (set_strings_value(strings, "NSCameraUsageDescription", 'new "text"'),
         '"NSCameraUsageDescription" = "new \\"text\\"";\n"Other" = "old";\n'),
        (set_strings_value(strings, "NSMissing", "x"), None),
    ]
    for got, expected in text_cases:
        if got != expected:
            print(f"  FAIL  permission text: expected {expected!r}\n        got      {got!r}")
            failures += 1
    for key, texts in {**BUNDLE_TEXTS, **BUNDLE_ADDITIONS}.items():
        for language in ("en", "fr"):
            template = texts.get(language, "")
            # The name comes from Fork/identity.sh, never from the text itself.
            if "{name}" not in template or identity["FORK_APP_NAME"] in template:
                print(f"  FAIL  {key} ({language}): the text must name the app through {{name}} only")
                failures += 1

    if failures:
        fail(f"selftest: {failures} failure(s)")
    print(f"BRAND SELFTEST OK ({len(cases)} rule cases)")


COMMANDS = {
    "sources": command_sources,
    "resources": command_resources,
    "audit": command_audit,
    "selftest": command_selftest,
}


def main(arguments):
    if not arguments or arguments[0] not in COMMANDS:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    COMMANDS[arguments[0]](arguments[1:])


if __name__ == "__main__":
    main(sys.argv[1:])
