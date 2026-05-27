#!/usr/bin/env bash
# Benchmark per-agent Cargo target directories with either sccache or kache
# fallback-to-sccache. The script keeps all generated targets and caches under
# its output directory and never changes repo-local target directories.
set -euo pipefail

usage() {
  printf 'usage: %s [--out DIR] [--agent-count N] --repo LABEL=PATH [--repo LABEL=PATH ...] -- COMMAND [ARGS...]\n' "$(basename "$0")" >&2
  printf '\n' >&2
  printf 'example:\n' >&2
  printf '  %s --repo wallet=/path/to/wallet --repo dummy=/path/to/dummy --agent-count 4 -- cargo check --workspace\n' "$(basename "$0")" >&2
}

out=""
agent_count=4
repo_specs=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --out)
      if [ "$#" -lt 2 ]; then
        printf 'error: --out requires a directory\n' >&2
        exit 64
      fi
      out=$2
      shift 2
      ;;
    --agent-count)
      if [ "$#" -lt 2 ]; then
        printf 'error: --agent-count requires a number\n' >&2
        exit 64
      fi
      agent_count=$2
      shift 2
      ;;
    --repo)
      if [ "$#" -lt 2 ]; then
        printf 'error: --repo requires LABEL=PATH\n' >&2
        exit 64
      fi
      repo_specs+=("$2")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage
      exit 64
      ;;
  esac
done

if [ "${#repo_specs[@]}" -eq 0 ]; then
  printf 'error: provide at least one --repo LABEL=PATH\n' >&2
  exit 64
fi

if [ "$#" -eq 0 ]; then
  printf 'error: provide the Cargo command after --\n' >&2
  exit 64
fi

case "$agent_count" in
  ''|*[!0-9]*)
    printf 'error: --agent-count must be a positive integer\n' >&2
    exit 64
    ;;
esac

if [ "$agent_count" -lt 1 ]; then
  printf 'error: --agent-count must be at least 1\n' >&2
  exit 64
fi

command=("$@")
sccache_port=$((32000 + ($$ % 20000)))

if ! sccache_bin=$(command -v sccache); then
  printf 'error: sccache is required on PATH\n' >&2
  exit 69
fi
kache_bin=$(command -v kache || true)

if [ -z "$out" ]; then
  out=$(mktemp -d "${TMPDIR:-/tmp}/cargo-cache-benchmark.XXXXXX")
else
  mkdir -p "$out"
  out=$(cd "$out" && pwd -P)
fi

results="$out/results.tsv"
printf 'repo\tmode\tphase\tagent\tcommand\texit_code\telapsed_seconds\tcompile_lines\tfile_lock_waits\ttarget_size\tsccache_cache_size\tkache_cache_size\tsccache_compile_requests\tsccache_rust_hits\tsccache_rust_misses\tsccache_non_cacheable\tlog_path\tsccache_stats_path\n' > "$results"

sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

human_size() {
  local path=$1
  if [ -e "$path" ]; then
    du -sh "$path" 2>/dev/null | cut -f1
  else
    printf '0'
  fi
}

stat_value() {
  local label=$1
  local file=$2
  if [ ! -f "$file" ]; then
    printf '0'
    return
  fi
  awk -v label="$label" 'index($0, label) == 1 { print $NF; found = 1; exit } END { if (!found) print "0" }' "$file"
}

zero_sccache_stats() {
  local dir=$1
  SCCACHE_DIR="$dir" SCCACHE_SERVER_PORT="$sccache_port" "$sccache_bin" --zero-stats >/dev/null 2>&1 || true
}

write_sccache_stats() {
  local dir=$1
  local path=$2
  SCCACHE_DIR="$dir" SCCACHE_SERVER_PORT="$sccache_port" "$sccache_bin" --show-stats > "$path" 2>&1 || true
}

stop_sccache_server() {
  local dir=$1
  SCCACHE_DIR="$dir" SCCACHE_SERVER_PORT="$sccache_port" "$sccache_bin" --stop-server >/dev/null 2>&1 || true
}

workspace_manifest() {
  local path=$1
  (
    cd "$path" || exit 1
    cargo locate-project --workspace --message-format plain
  ) 2>/dev/null
}

run_agent() {
  local repo_label=$1
  local repo_path=$2
  local mode=$3
  local phase=$4
  local agent=$5
  local target_dir=$6
  local sccache_dir=$7
  local kache_dir=$8
  local log=$9
  local result_part=${10}

  local start end exit_code elapsed compile_lines file_lock_waits target_size sccache_size kache_size

  start=$(date +%s)
  set +e
  (
    cd "$repo_path" || exit 1
    case "$mode" in
      sccache)
        CARGO_TARGET_DIR="$target_dir" \
        RUSTC_WRAPPER="$sccache_bin" \
        SCCACHE_DIR="$sccache_dir" \
        SCCACHE_SERVER_PORT="$sccache_port" \
        SCCACHE_CACHE_SIZE=100G \
        CARGO_INCREMENTAL=0 \
        "${command[@]}"
        ;;
      kache-fallback-sccache)
        CARGO_TARGET_DIR="$target_dir" \
        RUSTC_WRAPPER="$kache_bin" \
        KACHE_CACHE_DIR="$kache_dir" \
        KACHE_FALLBACK="$sccache_bin" \
        SCCACHE_DIR="$sccache_dir" \
        SCCACHE_SERVER_PORT="$sccache_port" \
        SCCACHE_CACHE_SIZE=100G \
        CARGO_INCREMENTAL=0 \
        "${command[@]}"
        ;;
      *)
        printf 'error: unknown mode %s\n' "$mode" >&2
        exit 64
        ;;
    esac
  ) > "$log" 2>&1
  exit_code=$?
  set -e
  end=$(date +%s)
  elapsed=$((end - start))
  compile_lines=$(grep -c '^   Compiling ' "$log" || true)
  file_lock_waits=$(grep -c 'Blocking waiting for file lock' "$log" || true)
  target_size=$(human_size "$target_dir")
  sccache_size=$(human_size "$sccache_dir")
  kache_size=$(human_size "$kache_dir")

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$repo_label" \
    "$mode" \
    "$phase" \
    "$agent" \
    "${command[*]}" \
    "$exit_code" \
    "$elapsed" \
    "$compile_lines" \
    "$file_lock_waits" \
    "$target_size" \
    "$sccache_size" \
    "$kache_size" \
    "0" \
    "0" \
    "0" \
    "0" \
    "$log" \
    "" > "$result_part"
}

append_phase_stats() {
  local stats=$1
  local tmp=$2
  local requests rust_hits rust_misses non_cacheable

  requests=$(stat_value 'Compile requests' "$stats")
  rust_hits=$(stat_value 'Cache hits (Rust)' "$stats")
  rust_misses=$(stat_value 'Cache misses (Rust)' "$stats")
  non_cacheable=$(stat_value 'Non-cacheable calls' "$stats")

  while IFS= read -r line; do
    awk -v line="$line" \
      -v requests="$requests" \
      -v rust_hits="$rust_hits" \
      -v rust_misses="$rust_misses" \
      -v non_cacheable="$non_cacheable" \
      -v stats="$stats" \
      'BEGIN {
        n = split(line, fields, "\t");
        fields[13] = requests;
        fields[14] = rust_hits;
        fields[15] = rust_misses;
        fields[16] = non_cacheable;
        fields[18] = stats;
        for (i = 1; i <= n; i++) {
          printf "%s%s", fields[i], (i == n ? "\n" : "\t");
        }
      }'
  done < "$tmp" >> "$results"
}

run_phase() {
  local repo_label=$1
  local repo_path=$2
  local mode=$3
  local phase=$4
  local mode_root=$5
  local target_root=$mode_root/targets
  local log_root=$mode_root/logs/$phase
  local part_root=$mode_root/results/$phase
  local sccache_dir=$mode_root/sccache
  local kache_dir=$mode_root/kache
  local stats=$mode_root/sccache-$phase.txt
  local pids=()
  local parts=()

  case "$phase" in
    cold)
      stop_sccache_server "$sccache_dir"
      rm -rf "$mode_root"
      ;;
    warm-fresh-target)
      rm -rf "$target_root"
      ;;
    target-reuse)
      ;;
    *)
      printf 'error: unknown phase %s\n' "$phase" >&2
      exit 64
      ;;
  esac

  mkdir -p "$target_root" "$log_root" "$part_root" "$sccache_dir" "$kache_dir"
  zero_sccache_stats "$sccache_dir"

  printf 'running repo=%s mode=%s phase=%s agents=%s\n' "$repo_label" "$mode" "$phase" "$agent_count" >&2

  for agent in $(seq 1 "$agent_count"); do
    local target_dir=$target_root/agent-$agent
    local log=$log_root/agent-$agent.log
    local part=$part_root/agent-$agent.tsv
    parts+=("$part")
    run_agent "$repo_label" "$repo_path" "$mode" "$phase" "$agent" "$target_dir" "$sccache_dir" "$kache_dir" "$log" "$part" &
    pids+=("$!")
  done

  local failed=0
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failed=1
    fi
  done

  write_sccache_stats "$sccache_dir" "$stats"
  local phase_tmp=$part_root/phase.tsv
  : > "$phase_tmp"
  for part in "${parts[@]}"; do
    if [ -f "$part" ]; then
      cat "$part" >> "$phase_tmp"
    else
      failed=1
    fi
  done
  append_phase_stats "$stats" "$phase_tmp"

  if awk -F '\t' '$6 != "0" { found = 1 } END { exit found ? 0 : 1 }' "$phase_tmp"; then
    printf 'warning: repo=%s mode=%s phase=%s had non-zero command exit codes; inspect results.tsv logs\n' "$repo_label" "$mode" "$phase" >&2
    failed=1
  fi

  return "$failed"
}

overall_failed=0
for spec in "${repo_specs[@]}"; do
  case "$spec" in
    *=*) ;;
    *)
      printf 'error: --repo must be LABEL=PATH, got %s\n' "$spec" >&2
      exit 64
      ;;
  esac

  label=${spec%%=*}
  path=${spec#*=}
  if [ -z "$label" ] || [ -z "$path" ]; then
    printf 'error: --repo must be LABEL=PATH, got %s\n' "$spec" >&2
    exit 64
  fi
  if [ ! -d "$path" ]; then
    printf 'error: repo path does not exist: %s\n' "$path" >&2
    exit 66
  fi

  manifest=$(workspace_manifest "$path") || {
    printf 'error: %s is not inside a Cargo workspace or package\n' "$path" >&2
    printf '       pass the directory containing Cargo.toml, or any child inside that workspace\n' >&2
    exit 66
  }
  printf 'repo=%s workspace=%s\n' "$label" "$manifest" >&2

  label_safe=$(sanitize "$label")
  repo_root=$out/repos/$label_safe

  for mode in sccache kache-fallback-sccache; do
    if [ "$mode" = kache-fallback-sccache ] && [ -z "$kache_bin" ]; then
      printf 'warning: kache is not on PATH; skipping mode=%s repo=%s\n' "$mode" "$label" >&2
      continue
    fi

    mode_root=$repo_root/$mode
    for phase in cold warm-fresh-target target-reuse; do
      if ! run_phase "$label" "$path" "$mode" "$phase" "$mode_root"; then
        overall_failed=1
      fi
    done
    stop_sccache_server "$mode_root/sccache"
  done
done

printf 'wrote results: %s\n' "$results" >&2
exit "$overall_failed"
