#!/bin/sh
# lint-design-tokens.sh -- add-themes-and-layout design.md D12.
#
# Views draw colors through the theme tokens (`Theme.accent`, `Theme.danger`,
# ...; ios/Shared/Theme.swift), never literal colors, so every theme -- and
# Increase Contrast / colour-blind-safe resolution -- reaches every screen.
# This fails on literal colors in the app, widget and Shared sources:
#   - Color(red:/hue:/white:  and UIColor(red:/hue:/white:
#   - named system colors (.red, .green, .blue, ... and Color.<same>)
#   - .white / .black inside foregroundStyle/tint/fill/stroke/background,
#     and Color.white / Color.black
# Exemptions live in tools/design-token-allowlist.txt, one
# `path:regex  # reason` per line (path is matched as a suffix of the file
# path; an empty regex exempts the whole file). Comment lines are ignored.
#
# POSIX sh + grep -E (no \b, which BSD grep on the macOS runners lacks), so
# it runs the same in Git Bash and in CI. Prints `file:line: <source>` per
# violation and exits 1 if there are any. Usage:
#   sh tools/lint-design-tokens.sh [dir ...]   (default: the app sources)

set -eu
# Byte-wise matching: much faster, and the patterns are ASCII.
LC_ALL=C
export LC_ALL

cd "$(dirname "$0")/.."
ALLOWLIST="tools/design-token-allowlist.txt"
if [ "$#" -eq 0 ]; then
    set -- ios/GarminFood ios/Shared ios/GarminFoodWidget
fi

W='([^A-Za-z0-9_]|$)'
NAMED='(red|green|blue|orange|yellow|purple|pink|teal|mint|cyan|indigo|brown|gray)'
PATTERN="(Color|UIColor)\((red|hue|white):"
PATTERN="$PATTERN|Color\.($NAMED|white|black)$W"
PATTERN="$PATTERN|(^|[^A-Za-z0-9_])\.$NAMED$W"
PATTERN="$PATTERN|\.(foregroundStyle|tint|fill|stroke|background)\((.*[^A-Za-z0-9_])?\.(white|black)$W"

tmp="${TMPDIR:-/tmp}/lint-design-tokens.$$"
trap 'rm -f "$tmp".*' EXIT

grep -rEn --include='*.swift' "$PATTERN" "$@" > "$tmp.hits" || true

# Allowlist, parsed once: "path<TAB>regex" (reasons, blanks, comments dropped).
tab=$(printf '\t')
sed -e 's/[[:space:]]#.*$//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' \
    -e "s/:/$tab/" "$ALLOWLIST" > "$tmp.allow"

: > "$tmp.bad"
while IFS= read -r hit; do
    file=${hit%%:*}
    rest=${hit#*:}
    line=${rest%%:*}
    source=${rest#*:}
    trimmed=${source#"${source%%[! $tab]*}"}

    case "$trimmed" in
        //*) continue ;;
    esac

    allowed=no
    while IFS="$tab" read -r path regex; do
        case "$file" in
            *"$path") ;;
            *) continue ;;
        esac
        if [ -z "$regex" ] || printf '%s\n' "$source" | grep -Eq -- "$regex"; then
            allowed=yes
            break
        fi
    done < "$tmp.allow"

    if [ "$allowed" = no ]; then
        echo "$file:$line: $trimmed" >> "$tmp.bad"
    fi
done < "$tmp.hits"

if [ -s "$tmp.bad" ]; then
    cat "$tmp.bad"
    echo "lint-design-tokens: literal colors found; use a Theme token or add a justified line to $ALLOWLIST" >&2
    exit 1
fi
echo "lint-design-tokens: OK"
