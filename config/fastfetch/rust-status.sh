#!/bin/sh

current_line="$(cargo --version 2>/dev/null || true)"
if [ -z "$current_line" ]; then
  printf '%s\n' 'cargo unavailable'
  exit 0
fi

current_version="$(printf '%s\n' "$current_line" | awk '{ print $2 }')"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
cache_file="$cache_dir/rust-stable-version-v2"
max_age=86400

cache_mtime=0
if [ -e "$cache_file" ]; then
  cache_mtime="$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || printf '0')"
fi

now="$(date +%s)"
if [ "$((now - cache_mtime))" -gt "$max_age" ] && command -v curl >/dev/null 2>&1; then
  (
    mkdir -p "$cache_dir" || exit 0
    tmp_file="$cache_file.tmp.$$"
    latest="$(curl --fail --silent --show-error --location --max-time 3 \
      https://static.rust-lang.org/dist/channel-rust-stable.toml \
      | awk -F '"' '
        $0 == "[pkg.rust]" { in_rust = 1; next }
        /^\[/ { in_rust = 0 }
        in_rust && /^version = / { split($2, parts, " "); print parts[1]; exit }
      ')"
    if [ -n "$latest" ]; then
      printf '%s\n' "$latest" > "$tmp_file" && mv "$tmp_file" "$cache_file"
    else
      rm -f "$tmp_file"
    fi
  ) >/dev/null 2>&1 &
fi

latest_version=""
if [ -r "$cache_file" ]; then
  latest_version="$(sed -n '1p' "$cache_file")"
fi

if [ -n "$latest_version" ] && [ -n "$current_version" ] && [ "$latest_version" != "$current_version" ]; then
  printf '%s (stable %s available)\n' "$current_line" "$latest_version"
else
  printf '%s\n' "$current_line"
fi
