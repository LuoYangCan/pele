#!/usr/bin/env bash
# Shared resolver for Xcode-provided agent tooling (`agent`, `mcpbridge`, `mcp-server`).
#
# Sourced by sync-xcode-skills.sh and xcode-mcp-bridge.sh. Never writes to stdout
# except the resolved path a caller asked for.

# Print every candidate Xcode.app: /Applications/Xcode*.app plus the xcode-select target.
xcode_candidate_apps() {
  local app selected
  {
    for app in /Applications/Xcode*.app; do
      [ -d "$app" ] && printf '%s\n' "$app"
    done
    selected="$(xcode-select -p 2>/dev/null || true)"
    case "$selected" in
      */Contents/Developer) printf '%s\n' "${selected%/Contents/Developer}" ;;
    esac
  } | sort -u
}

xcode_short_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || printf '0'
}

# xcode_app_with <binary> [binary...]
# Print the highest-versioned Xcode.app whose Developer/usr/bin holds ALL named binaries.
xcode_app_with() {
  local app binary version best_app="" best_version="" ok
  while IFS= read -r app; do
    ok=1
    for binary in "$@"; do
      [ -x "$app/Contents/Developer/usr/bin/$binary" ] || { ok=0; break; }
    done
    [ "$ok" -eq 1 ] || continue
    version="$(xcode_short_version "$app")"
    if [ -z "$best_version" ] ||
       [ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -n 1)" = "$version" ]; then
      best_version="$version"
      best_app="$app"
    fi
  done < <(xcode_candidate_apps)
  [ -n "$best_app" ] || return 1
  printf '%s\n' "$best_app"
}
