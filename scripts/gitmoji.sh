#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# commit-msg hook: replace conventional commit prefix with gitmoji.
# Grammar: type[(scope)][!]: description
set -euo pipefail

BOOM='💥'

script_dir="$(cd "$(dirname "$0")" && pwd)"
msg_file="$1"
source_type="${2:-}"

# Don't modify merge, squash or amend messages
case "$source_type" in
    merge|squash|commit) exit 0 ;;
esac

# Load mapping table (set +u: declare -A incompatible with nounset)
set +u
# shellcheck source=gitmoji.cfg
source "$script_dir/gitmoji.cfg"
set -u

first_line=$(head -n 1 "$msg_file")

# If message already starts with a known emoji, leave it alone.
# Round-trip safety: a previously-rewritten "✨💥 msg" matches on "✨".
set +u
for e in "${gitmoji[@]}"; do [[ "$first_line" == "$e"* ]] && exit 0; done
set -u

list_prefixes() {
    printf '%s\n' "${!gitmoji[@]}" | sort | sed 's/^/  /'
}

re_full='^([a-z]+)(\(([a-z0-9._/-]+)\))?(!)?: (.+)$'
re_empty_scope='^[a-z]+\(\)!?: '

if [[ "$first_line" =~ $re_full ]]; then
    prefix="${BASH_REMATCH[1]}"
    # Optional groups: bash leaves their BASH_REMATCH slots as empty
    # strings; `:-` is defensive for older bash + nounset interaction.
    scope="${BASH_REMATCH[3]:-}"
    bang="${BASH_REMATCH[4]:-}"
    rest="${BASH_REMATCH[5]}"

    if [[ -v "gitmoji[$prefix]" ]]; then
        emoji="${gitmoji[$prefix]}"
        if [[ -n "$bang" ]]; then emoji="${emoji}${BOOM}"; fi
        if [[ -n "$scope" ]]; then rest="${scope}: ${rest}"; fi
        { echo "$emoji $rest"; tail -n +2 "$msg_file"; } > "$msg_file.tmp"
        mv "$msg_file.tmp" "$msg_file"
    else
        echo "Unknown prefix '$prefix'. Valid prefixes:" >&2
        list_prefixes >&2
        exit 1
    fi
elif [[ "$first_line" =~ $re_empty_scope ]]; then
    bad_prefix="${first_line%%(*}"
    echo "Empty scope in '${bad_prefix}()'. Scope must be non-empty. Valid prefixes:" >&2
    list_prefixes >&2
    exit 1
else
    echo "Missing or malformed conventional commit prefix." >&2
    echo "Expected: type[(scope)][!]: description" >&2
    echo "Valid prefixes:" >&2
    list_prefixes >&2
    exit 1
fi
