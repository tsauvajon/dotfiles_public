#!/usr/bin/env bash
# Patch a single-line empty-string field in a Nix file.
#
# Idempotent helper used by scripts/bootstrap-keys.sh to fill
# `signingKey = "";`, `name = "";`, and `email = "";` with concrete
# values during first-run setup. Kept as a standalone script so the
# patch contract can be exercised in isolation by a Nix flake check.
#
# Usage:
#   patch-empty-string-field.sh <flake-file> <field> <value>
#
# Matches lines of the form (any indentation):
#   <field> = "";
# and replaces the empty literal with <value>.
#
# Exit codes:
#   0  Patched, or the field is already set to <value> (idempotent).
#   2  Field is set to a different non-empty value (caller decides).
#   3  Field exists but is not in the empty-literal `""` form
#      (e.g. `null`, multi-line, comment-stripped). Caller should
#      ask the user to set it manually.
#   4  Flake file does not exist.
#   64 Usage error (wrong arg count, empty arg).
#
# Notes:
#   - <value> is spliced in as a literal string after escaping the
#     sed-replacement metacharacters `\` and `&`. The caller is still
#     responsible for not passing values that contain `"` or
#     newlines, since those would corrupt the resulting Nix string
#     literal.
#   - The sed delimiter is `|`, so `/` in <value> is safe and needs
#     no escaping.
set -euo pipefail
umask 077

if [ "$#" -ne 3 ]; then
  printf 'usage: %s <flake-file> <field> <value>\n' "$(basename "$0")" >&2
  exit 64
fi

file="$1"
field="$2"
value="$3"

if [ -z "$file" ] || [ -z "$field" ] || [ -z "$value" ]; then
  printf 'error: file, field, and value must all be non-empty\n' >&2
  exit 64
fi

if [ ! -f "$file" ]; then
  printf 'error: flake file not found: %s\n' "$file" >&2
  exit 4
fi

# Shape detection. We only patch the empty-literal form to avoid
# clobbering a hand-edited value or a non-string expression.
empty_re="^[[:space:]]*${field}[[:space:]]*=[[:space:]]*\"\"[[:space:]]*;"
existing_re="^[[:space:]]*${field}[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*;"

if grep -Eq "$empty_re" "$file"; then
  # Empty literal — patch it. Escape `\` and `&` in the replacement
  # so they are not interpreted by sed (the delimiter `|` does not
  # need escaping).
  escaped_value=$(printf '%s' "$value" | sed -e 's/[\\&]/\\&/g')
  backup="$file.bak"
  if ! sed -i.bak -E \
    "s|^([[:space:]]*${field}[[:space:]]*=[[:space:]]*)\"\"([[:space:]]*;.*)$|\\1\"${escaped_value}\"\\2|" \
    "$file"; then
    rm -f "$backup"
    printf 'error: sed failed while patching %s in %s\n' "$field" "$file" >&2
    exit 1
  fi
  rm -f "$backup"
  printf 'patched %s in %s\n' "$field" "$file"
  exit 0
fi

# Already set to a string literal — extract the current value.
current=$(grep -E "$existing_re" "$file" | head -n1 | sed -E "s|${existing_re}.*|\\1|") || current=""
if [ -n "$current" ]; then
  if [ "$current" = "$value" ]; then
    # Idempotent: already the desired value.
    exit 0
  fi
  printf 'warning: %s in %s is already set to %s; not overwriting with %s\n' \
    "$field" "$file" "\"$current\"" "\"$value\"" >&2
  exit 2
fi

# Field present but in some other shape (null, multi-line, etc.) or
# not present at all. Either way we cannot safely patch.
printf 'warning: %s in %s is not in the empty-literal form; set it manually to %s\n' \
  "$field" "$file" "\"$value\"" >&2
exit 3
