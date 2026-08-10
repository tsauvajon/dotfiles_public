#!/usr/bin/env bash
# Bootstrap the per-machine SSH key used by the dotfiles.
#
# This script is intentionally idempotent. It creates the missing personal key,
# fills git.{name,email,signingKey} in the private flake when it can do so
# safely, and prints upload instructions only when useful.
set -euo pipefail
umask 077

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
patch_helper="$script_dir/lib/patch-empty-string-field.sh"

show_keys=0
name_arg="${DOTFILES_GIT_NAME:-}"
email_arg="${DOTFILES_GIT_EMAIL:-}"

usage() {
  cat <<USAGE
usage: $(basename "$0") [--show] [--name "Full Name"] [--email "you@example.com"]

Generates the default SSH key and patches git.{name,email,signingKey}
in ~/.config/dotfiles/flake.nix when those fields are empty literals.

Flags:
  --name   Seed git.name when empty in the flake.
  --email  Seed git.email when empty in the flake.
  --show   Print upload commands and public keys even when nothing changed.
  -h, --help  Show this help.

Env vars (overridden by flags):
  DOTFILES_GIT_NAME           Same as --name.
  DOTFILES_GIT_EMAIL          Same as --email.
  DOTFILES_BOOTSTRAP_KEYS_SHOW=1   Same as --show.

Conflicts (already-set field, different value provided) are warned and
skipped, never silently overwritten.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --show) show_keys=1; shift ;;
    --name)
      [ "$#" -ge 2 ] || { printf 'error: --name requires a value\n' >&2; exit 2; }
      name_arg="$2"; shift 2
      ;;
    --name=*) name_arg="${1#--name=}"; shift ;;
    --email)
      [ "$#" -ge 2 ] || { printf 'error: --email requires a value\n' >&2; exit 2; }
      email_arg="$2"; shift 2
      ;;
    --email=*) email_arg="${1#--email=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      printf 'error: unexpected positional argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "${DOTFILES_BOOTSTRAP_KEYS_SHOW:-}" = "1" ]; then
  show_keys=1
fi

private_ref="${DOTFILES_PRIVATE_REF:-$HOME/.config/dotfiles}"
if [ -d "$private_ref" ]; then
  private_ref=$(cd "$private_ref" && pwd -P)
fi
private_flake="$private_ref/flake.nix"
ssh_key="$HOME/.ssh/id_ed25519"
ssh_pub="$ssh_key.pub"
changed=0

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

print_file() {
  local file="$1"
  local line

  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line"
  done < "$file"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_nix() {
  command -v nix >/dev/null 2>&1 || die 'nix not found on PATH'
}

eval_private_attr() {
  local attr="$1"
  local stderr_file value attr_re attr_leaf attr_leaf_re

  stderr_file=$(mktemp -t dotfiles-key-bootstrap.XXXXXX)
  if value=$(nix \
    --extra-experimental-features 'nix-command flakes' \
    eval --raw --no-write-lock-file \
    "path:$private_ref#$attr" \
    2>"$stderr_file"); then
    rm -f "$stderr_file"
    printf '%s' "$value"
    return 0
  fi

  attr_re=$(printf '%s' "$attr" | sed -e 's/[][(){}.^$*+?|\\/]/\\&/g')
  attr_leaf="${attr##*.}"
  attr_leaf_re=$(printf '%s' "$attr_leaf" | sed -e 's/[][(){}.^$*+?|\\/]/\\&/g')
  if grep -qE "(does not provide attribute .*'${attr_re}'|attribute '?${attr_leaf_re}'? missing)" "$stderr_file"; then
    rm -f "$stderr_file"
    printf ''
    return 0
  fi

  printf 'error: failed to evaluate private flake attribute %s:\n' "$attr" >&2
  sed 's/^/  /' "$stderr_file" >&2
  rm -f "$stderr_file"
  exit 1
}

# Patch a `<field> = "";` literal in the private flake using the
# scripts/lib/patch-empty-string-field.sh helper. Returns 0 on success
# (patched, or already idempotent), non-zero with a warning otherwise.
patch_field() {
  local field="$1"
  local value="$2"
  local rc=0

  [ -x "$patch_helper" ] || die "patch helper missing or not executable: $patch_helper"

  if "$patch_helper" "$private_flake" "$field" "$value"; then
    return 0
  fi
  rc=$?
  case "$rc" in
    2) warn "$field already set to a different value in $private_flake; not overwriting" ;;
    3) warn "$field is not in the empty-literal form in $private_flake; set it manually to \"$value\"" ;;
    4) warn "private flake missing while trying to patch $field: $private_flake" ;;
    5) warn "$field is absent from $private_flake; add it manually as $field = \"$value\";" ;;
    *) warn "failed to patch $field in $private_flake (helper exit $rc)" ;;
  esac
  return "$rc"
}

patch_signing_key() {
  patch_field signingKey "$1" || return 1
  log "filled git.signingKey in $private_flake"
}

ensure_ssh_key() {
  local email="$1"
  local ssh_pub_tmp

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [ -f "$ssh_key" ]; then
    log "SSH key already present: $ssh_key"
    if [ ! -f "$ssh_pub" ]; then
      warn "SSH public key missing: $ssh_pub"
      if command -v ssh-keygen >/dev/null 2>&1; then
        log "recreating SSH public key from $ssh_key"
        ssh_pub_tmp=$(mktemp "$ssh_pub.tmp.XXXXXX")
        if ssh-keygen -y -f "$ssh_key" > "$ssh_pub_tmp" && [ -s "$ssh_pub_tmp" ]; then
          mv "$ssh_pub_tmp" "$ssh_pub"
          chmod 644 "$ssh_pub"
          changed=1
        else
          rm -f "$ssh_pub_tmp"
          warn "could not recreate $ssh_pub"
        fi
      else
        warn 'ssh-keygen not found; cannot recreate SSH public key'
      fi
    fi
    return 0
  fi

  command -v ssh-keygen >/dev/null 2>&1 || die 'ssh-keygen not found on PATH'

  log "generating SSH key: $ssh_key"
  ssh-keygen -t ed25519 -C "$email" -f "$ssh_key"
  chmod 600 "$ssh_key"
  [ -f "$ssh_pub" ] && chmod 644 "$ssh_pub"
  changed=1
}

print_upload_hints() {
  local host_title
  host_title=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'new-machine')

  printf '\n'
  log 'Public keys ready for upload'

  if [ -f "$ssh_pub" ]; then
    printf '\nSSH public key: %s\n\n' "$ssh_pub"
    print_file "$ssh_pub"
    printf '\nUpload commands:\n'
    printf '  glab auth status && glab ssh-key add "%s" --title "%s" --usage-type auth_and_signing\n' "$ssh_pub" "$host_title"
    printf '  gh auth status && gh ssh-key add "%s" --title "%s" --type authentication\n' "$ssh_pub" "$host_title"
    printf '  gh auth status && gh ssh-key add "%s" --title "%s" --type signing\n' "$ssh_pub" "$host_title"
  else
    printf '\nNo SSH public key is available at %s.\n' "$ssh_pub"
  fi

  printf '\n'
}

main() {
  local git_name git_email signing_key

  require_nix
  [ -f "$private_flake" ] || die "private flake missing: $private_flake"

  # Seed name/email from --name / --email or DOTFILES_GIT_{NAME,EMAIL}
  # before we read them back. The helper is a no-op when the field is
  # already set to the same value, and warns (but does not fail) on
  # conflicts so an idempotent re-run keeps working.
  if [ -n "$name_arg" ]; then
    patch_field name "$name_arg" || true
  fi
  if [ -n "$email_arg" ]; then
    patch_field email "$email_arg" || true
  fi

  git_name=$(eval_private_attr git.name) || exit 1
  git_email=$(eval_private_attr git.email) || exit 1
  signing_key=$(eval_private_attr git.signingKey) || exit 1

  [ -n "$git_name" ] || die "git.name is empty in $private_flake (seed it via --name or DOTFILES_GIT_NAME)"
  [ -n "$git_email" ] || die "git.email is empty in $private_flake (seed it via --email or DOTFILES_GIT_EMAIL)"

  ensure_ssh_key "$git_email"
  if [ -z "$signing_key" ]; then
    # shellcheck disable=SC2088 # Persist Git's portable home-relative path.
    patch_signing_key '~/.ssh/id_ed25519.pub' || true
    changed=1
  fi

  if [ "$changed" -eq 1 ] || [ "$show_keys" -eq 1 ]; then
    print_upload_hints
  else
    log 'SSH key already bootstrapped; pass --show to print upload commands'
  fi
}

main "$@"
