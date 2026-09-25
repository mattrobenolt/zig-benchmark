#!/usr/bin/env bash
# Run from the repository root, inside either supported Nix dev shell.
set -euo pipefail
output=$(mktemp)
trap 'rm -f "$output"' EXIT

# Both children inherit the SAME open descriptor and must retain its seek position.
{
    printf 'before benchmark output\n'
    timeout 60s zig build run-benchmark -- --help
    timeout 60s zig build run-benchmark -- --count=1 --benchtime=1x --filter='^BenchmarkFilter/Glob$' --no-env
    printf 'after benchmark output\n'
} > "$output"

cat "$output"
grep -Fxq 'before benchmark output' "$output"
grep -Fxq 'Usage: benchmark [options]' "$output"
grep -q '^BenchmarkFilter/Glob[[:space:]]' "$output"
grep -Fxq 'after benchmark output' "$output"
