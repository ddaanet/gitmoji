#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# commit-msg hook: replace conventional commit prefix with gitmoji.
# Grammar: type[(scope)][!]: description
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
msg_file="$1"
first_line=$(head -n 1 "$msg_file")

# Git-authored messages are not ours to rewrite. A state marker in the
# git dir means an in-progress merge, squash-merge, cherry-pick or
# revert is being committed, so the message came from git rather than
# the user — rejecting it would strand the operation.
#
# The marker is the signal because nothing else suffices: git passes
# the commit-msg hook exactly one argument (there is no source-type to
# consult), and the message file is COMMIT_EDITMSG rather than
# MERGE_MSG whenever a conflicted or interrupted merge is completed by
# hand. GIT_DIR is not exported into the hook environment either.
git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [[ -n "$git_dir" ]]; then
    for m in MERGE_HEAD SQUASH_MSG CHERRY_PICK_HEAD REVERT_HEAD; do
        [[ -e "$git_dir/$m" ]] && exit 0
    done
fi

# Autosquash subjects carry no marker, so the first line is the only
# available signal. The trailing space keeps this from matching an
# unrelated subject that merely starts with one of these words.
re_autosquash='^(fixup|squash|amend)! '
[[ "$first_line" =~ $re_autosquash ]] && exit 0

# Load mapping table (set +u: declare -A incompatible with nounset)
set +u
# shellcheck source=gitmoji.cfg
source "$script_dir/gitmoji.cfg"
set -u

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
    scope="${BASH_REMATCH[3]}"
    bang="${BASH_REMATCH[4]}"
    rest="${BASH_REMATCH[5]}"

    if [[ -v "gitmoji[$prefix]" ]]; then
        emoji="${gitmoji[$prefix]}"
        if [[ -n "$bang" ]]; then emoji="${emoji}💥"; fi
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
