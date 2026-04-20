#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# commit-msg hook: replace conventional commit prefix with gitmoji.
set -euo pipefail

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

# If message already starts with a known emoji, leave it alone
set +u
for e in "${gitmoji[@]}"; do [[ "$first_line" == "$e"* ]] && exit 0; done
set -u

# Extract prefix (before first ":")
if [[ "$first_line" =~ ^([a-z]+):\ (.*) ]]; then
    prefix="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"

    if [[ -v "gitmoji[$prefix]" ]]; then
        # Replace first line, preserve rest of message
        emoji="${gitmoji[$prefix]}"
        { echo "$emoji $rest"; tail -n +2 "$msg_file"; } > "$msg_file.tmp"
        mv "$msg_file.tmp" "$msg_file"
    else
        prefixes=$(printf '%s\n' "${!gitmoji[@]}" | sort | sed 's/^/  /')
        echo "Unknown prefix '$prefix'. Valid prefixes:" >&2
        echo "$prefixes" >&2
        exit 1
    fi
else
    prefixes=$(printf '%s\n' "${!gitmoji[@]}" | sort | sed 's/^/  /')
    echo "Missing conventional commit prefix. Valid prefixes:" >&2
    echo "$prefixes" >&2
    exit 1
fi
