#!/usr/bin/env bash
# Sourceable helpers for staging external OpenCode imports.

# Sync external OpenCode imports from the tab-separated manifest on stdin into
# the provided staging root. The manifest is produced by setup.sh via Nix eval.
opencode_imports_sync() {
  local sync_root="$1"
  local manifest

  manifest=$(cat)

  # Eval succeeded before this function was called — reset the staging root so
  # removed manifest entries do not linger.
  if [ -d "$sync_root" ]; then
    chmod -R u+w "$sync_root" 2>/dev/null || true
  fi
  rm -rf "$sync_root"

  if [ -z "$manifest" ]; then
    return 0
  fi

  mkdir -p "$sync_root"
  printf '==> Syncing OpenCode imports into %s\n' "$sync_root"

  # Per-import accumulators (reset on each HEADER, consumed on END).
  local cur_name="" cur_source="" cur_mode=""
  local -a cur_rename_src=() cur_rename_dest=()
  local -a cur_exclude=()
  local -a cur_path_src=() cur_path_dest=()

  local tag a b c
  while IFS=$'\t' read -r tag a b c; do
    [ -z "$tag" ] && continue
    case "$tag" in
      HEADER)
        cur_name="$a" cur_source="$b" cur_mode="$c"
        cur_rename_src=() cur_rename_dest=()
        cur_exclude=()
        cur_path_src=() cur_path_dest=()
        ;;
      RENAME)
        cur_rename_src+=("$b") cur_rename_dest+=("$c")
        ;;
      EXCLUDE)
        cur_exclude+=("$b")
        ;;
      PATH)
        cur_path_src+=("$b") cur_path_dest+=("$c")
        ;;
      END)
        opencode_imports_process_import "$sync_root"
        ;;
      *)
        printf 'warning: unknown opencode-import record tag %q\n' "$tag" >&2
        ;;
    esac
  done <<<"$manifest"
}

opencode_imports_validate_rel() {
  local rel="$1" name="$2" kind="$3"

  case "$rel" in
    ""|/*|..|../*|*/..|*/../*)
      printf 'error: opencode-import "%s" has invalid %s path: %s\n' "$name" "$kind" "$rel" >&2
      exit 1
      ;;
  esac
}

opencode_imports_validate_dest_rel() {
  opencode_imports_validate_rel "$1" "$2" destination
}

opencode_imports_validate_source_rel() {
  opencode_imports_validate_rel "$1" "$2" source
}

# Stage src→stage/dest_rel as either a file or a directory copy. cp -L /-RL
# dereferences symlinks so the staging area is a clean tree of regular files.
# `cp -R src dst` copies *into* dst when dst already exists, so we wipe an
# existing destination first to keep the sync idempotent.
opencode_imports_stage_one() {
  local src="$1" stage="$2" dest_rel="$3" name="$4" dst

  opencode_imports_validate_dest_rel "$dest_rel" "$name"
  dst="$stage/$dest_rel"

  if [ -d "$src" ]; then
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -RL "$src" "$dst"
    chmod -R u+w "$dst" 2>/dev/null || true
  elif [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -L "$src" "$dst"
    chmod u+w "$dst" 2>/dev/null || true
  else
    printf 'warning: opencode-import "%s" missing path: %s\n' "$name" "$src" >&2
  fi
}

# Membership check against the cur_exclude array.
opencode_imports_import_excluded() {
  local rel="$1" i
  for ((i = 0; i < ${#cur_exclude[@]}; i++)); do
    [ "${cur_exclude[$i]}" = "$rel" ] && return 0
  done
  return 1
}

# Print the rename destination for a source-rel path, or the path itself when
# no rename rule matches.
opencode_imports_import_rename_for() {
  local rel="$1" i
  for ((i = 0; i < ${#cur_rename_src[@]}; i++)); do
    if [ "${cur_rename_src[$i]}" = "$rel" ]; then
      printf '%s' "${cur_rename_dest[$i]}"
      return 0
    fi
  done
  printf '%s' "$rel"
}

# Process the import described by the cur_* state. Validates schema, expands
# `~` in source, then either cherry-picks (explicit mode) or walks the standard
# layout (auto mode).
opencode_imports_process_import() {
  local sync_root="$1"
  local source="$cur_source"

  opencode_imports_validate_dest_rel "$cur_name" "$cur_name"

  # Tilde expansion. Only `~` and `~/...` are supported; the `~user/...` form
  # would require user-database lookup.
  # shellcheck disable=SC2088
  case "$source" in
    "~"|"~/"*) source="$HOME${source#\~}" ;;
    "~"*)
      printf 'warning: opencode-import "%s" uses unsupported ~user/ form: %s\n' "$cur_name" "$source" >&2
      return 0
      ;;
  esac

  local stage="$sync_root/$cur_name"

  # Mutual-exclusion validation: `paths` cannot mix with rename/exclude.
  # Misconfiguration is fatal — make the user fix the flake before any
  # downstream nix build runs against an inconsistent staging tree.
  if [ "$cur_mode" = "explicit" ]; then
    if [ ${#cur_rename_src[@]} -gt 0 ]; then
      # shellcheck disable=SC2016
      printf 'error: opencode-import "%s" sets both `paths` and `rename` (mutually exclusive)\n' "$cur_name" >&2
      exit 1
    fi
    if [ ${#cur_exclude[@]} -gt 0 ]; then
      # shellcheck disable=SC2016
      printf 'error: opencode-import "%s" sets both `paths` and `exclude` (mutually exclusive)\n' "$cur_name" >&2
      exit 1
    fi
    local i
    for ((i = 0; i < ${#cur_path_src[@]}; i++)); do
      opencode_imports_validate_source_rel "${cur_path_src[$i]}" "$cur_name"
      opencode_imports_validate_dest_rel "${cur_path_dest[$i]}" "$cur_name"
    done
    mkdir -p "$stage"
    for ((i = 0; i < ${#cur_path_src[@]}; i++)); do
      opencode_imports_stage_one "$source/${cur_path_src[$i]}" "$stage" "${cur_path_dest[$i]}" "$cur_name"
    done
    return 0
  fi

  # Auto mode: walk the standard layout.
  local sub entry rel dest
  mkdir -p "$stage"
  for sub in commands skills agents plugins rules; do
    [ -d "$source/$sub" ] || continue
    for entry in "$source/$sub"/*; do
      [ -e "$entry" ] || continue
      rel="$sub/$(basename "$entry")"
      opencode_imports_import_excluded "$rel" && continue
      dest=$(opencode_imports_import_rename_for "$rel")
      opencode_imports_stage_one "$entry" "$stage" "$dest" "$cur_name"
    done
  done

  # Top-level opencode.*.json (excluding bare opencode.json) + package.json.
  for entry in "$source"/opencode.*.json "$source"/package.json; do
    [ -f "$entry" ] || continue
    rel="$(basename "$entry")"
    [ "$rel" = "opencode.json" ] && continue
    opencode_imports_import_excluded "$rel" && continue
    dest=$(opencode_imports_import_rename_for "$rel")
    opencode_imports_stage_one "$entry" "$stage" "$dest" "$cur_name"
  done

  # Rename entries pointing at non-standard sources (e.g. mcp.fragment.json →
  # opencode.foo.mcp.json) — anything referenced by `rename` whose src wasn't
  # auto-discovered.
  local i
  for ((i = 0; i < ${#cur_rename_src[@]}; i++)); do
    rel="${cur_rename_src[$i]}"
    dest="${cur_rename_dest[$i]}"
    opencode_imports_validate_dest_rel "$dest" "$cur_name"
    [ -e "$stage/$dest" ] && continue
    [ -e "$source/$rel" ] || continue
    opencode_imports_stage_one "$source/$rel" "$stage" "$dest" "$cur_name"
  done
}
