#!/usr/bin/env bash
# Print the repository root from the real location of this script, not $PWD.
set -euo pipefail

source_path="${BASH_SOURCE[0]}"
while [ -L "$source_path" ]; do
  parent="$(cd -P "$(dirname "$source_path")" && pwd)"
  source_path="$(readlink "$source_path")"
  case "$source_path" in
    /*) ;;
    *) source_path="$parent/$source_path" ;;
  esac
done

script_dir="$(cd -P "$(dirname "$source_path")" && pwd)"
printf '%s\n' "$(cd "$script_dir/.." && pwd -P)"
