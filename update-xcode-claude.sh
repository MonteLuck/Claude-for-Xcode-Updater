#!/usr/bin/env bash
#
# update-xcode-claude.sh
# ----------------------
# Installs a specific version of the Claude Code CLI into Xcode's
# CodingAssistant agent directory, so Xcode's built-in Claude agent
# runs the version you choose instead of the one Apple bundles.
#
# It downloads the official Anthropic build, verifies it, backs up the
# current binary, swaps it in, and writes a matching Info.plist.
#
# Usage:
#   update-xcode-claude.sh <version>       e.g. update-xcode-claude.sh 2.1.195
#   update-xcode-claude.sh latest          install the latest GitHub release
#   update-xcode-claude.sh --current       show what's installed/running now
#   update-xcode-claude.sh --restore       roll back to the most recent backup
#
# Notes:
#   * Quit Xcode (Cmd+Q) before running an install — the binary is in use otherwise.
#   * Ignore Xcode's "A newer version is available" popup afterwards (close with ✕);
#     clicking "Update" may revert you to Apple's bundled (older) version.
#
set -euo pipefail

# --- Configuration ----------------------------------------------------------
CDN_BASE="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
LATEST_RELEASE_API="https://api.github.com/repos/anthropics/claude-code/releases/latest"
AGENTS_ROOT="$HOME/Library/Developer/Xcode/CodingAssistant/Agents"
XCODE_VERSIONS_DIR="$AGENTS_ROOT/XcodeVersions"
CACHE_DIR="$AGENTS_ROOT/claude"   # versioned download cache: claude/<version>/

# --- Helpers ----------------------------------------------------------------
err()  { printf '\033[31mError:\033[0m %s\n' "$*" >&2; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }

INSTALL_TMP=""
cleanup_install_tmp() {
    if [ -n "${INSTALL_TMP:-}" ]; then
        rm -f "$INSTALL_TMP"
    fi
}

detect_platform() {
    case "$(uname -m)" in
        arm64)  echo "darwin-arm64" ;;
        x86_64) echo "darwin-x64" ;;
        *) err "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac
}

# Locate the active Xcode agent dir, e.g. .../XcodeVersions/17F42/claude
# Picks the most recently modified one if several Xcode builds are present.
find_xcode_claude_dir() {
    local newest=""
    if [ ! -d "$XCODE_VERSIONS_DIR" ]; then
        err "Xcode agent directory not found: $XCODE_VERSIONS_DIR"
        err "Has Xcode's Claude assistant ever been launched on this machine?"
        exit 1
    fi
    # shellcheck disable=SC2012
    newest=$(ls -dt "$XCODE_VERSIONS_DIR"/*/claude 2>/dev/null | head -1 || true)
    if [ -z "$newest" ]; then
        err "No '<build>/claude' directory under $XCODE_VERSIONS_DIR"
        exit 1
    fi
    echo "$newest"
}

xcode_is_running() {
    pgrep -x Xcode >/dev/null 2>&1
}

binary_version() {
    # Prints the version a binary reports, or nothing on failure.
    "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

resolve_latest_version() {
    local tmp tag version
    tmp="$(mktemp -t claude-latest-release)"

    if ! curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: xcode-claude-updater" \
        -o "$tmp" \
        "$LATEST_RELEASE_API"; then
        rm -f "$tmp"
        err "Could not fetch the latest Claude Code release from GitHub."
        err "Check your internet connection or install a specific version manually."
        return 1
    fi

    tag=""
    if command -v plutil >/dev/null 2>&1; then
        tag=$(plutil -extract tag_name raw -o - "$tmp" 2>/dev/null || true)
    fi
    if [ -z "$tag" ]; then
        tag=$(sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$tmp" | head -1 || true)
    fi
    rm -f "$tmp"

    version="${tag#v}"
    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        err "Could not parse a semantic version from the latest GitHub release tag: ${tag:-unknown}"
        return 1
    fi

    printf '%s\n' "$version"
}

# --- Subcommand: --current --------------------------------------------------
show_current() {
    local dir bin ver
    dir=$(find_xcode_claude_dir)
    bin="$dir/claude"
    info "Xcode agent dir: $dir"
    if [ -x "$bin" ]; then
        ver=$(binary_version "$bin")
        ok "Installed binary version: ${ver:-unknown}"
    else
        err "No claude binary at $bin"
    fi
    if [ -f "$dir/Info.plist" ]; then
        local pver
        pver=$(/usr/libexec/PlistBuddy -c "Print :version" "$dir/Info.plist" 2>/dev/null || true)
        info "Info.plist version: ${pver:-unknown}"
    fi
    # What's actually running right now (if anything)
    local running
    running=$(pgrep -fl "CodingAssistant/Agents.*/claude " 2>/dev/null | grep -oE '/Users[^ ]*/claude/claude' | head -1 || true)
    if [ -n "$running" ]; then
        info "Running process binary: $running -> $(binary_version "$running")"
    else
        info "No Claude agent process currently running."
    fi
}

# --- Subcommand: --restore --------------------------------------------------
restore_backup() {
    local dir bin_bak plist_bak
    dir=$(find_xcode_claude_dir)
    # shellcheck disable=SC2012
    bin_bak=$(ls -t "$dir"/claude.*.bak 2>/dev/null | head -1 || true)
    if [ -z "$bin_bak" ]; then
        err "No backup (claude.*.bak) found in $dir"
        exit 1
    fi
    plist_bak="${bin_bak%/*}/Info.plist.${bin_bak##*claude.}"   # mirror naming
    plist_bak="$dir/Info.plist.$(basename "$bin_bak" | sed -E 's/^claude\.(.*)\.bak$/\1/').bak"

    if xcode_is_running; then
        err "Xcode is running. Quit it (Cmd+Q) before restoring."
        exit 1
    fi
    info "Restoring binary from: $(basename "$bin_bak")"
    cp -f "$bin_bak" "$dir/claude"
    chmod +x "$dir/claude"
    if [ -f "$plist_bak" ]; then
        cp -f "$plist_bak" "$dir/Info.plist"
        ok "Restored Info.plist from $(basename "$plist_bak")"
    fi
    ok "Restored. Version now: $(binary_version "$dir/claude")"
}

# --- Subcommand: latest -----------------------------------------------------
install_latest() {
    local version

    info "Looking up latest Claude Code release on GitHub..."
    if ! version=$(resolve_latest_version); then
        exit 1
    fi
    ok "Latest Claude Code release: $version"

    install_version "$version"
}

# --- Subcommand: install <version> -----------------------------------------
install_version() {
    local version="$1"
    local platform url dir bin tmp sum

    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        err "Version must look like X.Y.Z (got: '$version')"
        exit 1
    fi

    platform=$(detect_platform)
    url="$CDN_BASE/$version/$platform/claude"
    dir=$(find_xcode_claude_dir)
    bin="$dir/claude"

    info "Target version : $version"
    info "Platform       : $platform"
    info "Xcode agent dir: $dir"

    if xcode_is_running; then
        err "Xcode is currently running — the agent binary is locked."
        err "Quit Xcode (Cmd+Q) and run this script again."
        exit 1
    fi

    # If already installed, short-circuit.
    if [ -x "$bin" ] && [ "$(binary_version "$bin")" = "$version" ]; then
        ok "Version $version is already installed. Nothing to do."
        exit 0
    fi

    # 1. Verify the URL exists before touching anything.
    info "Checking availability: $url"
    if ! curl -fsI "$url" >/dev/null; then
        err "Version $version not found at CDN for $platform."
        err "Double-check the version number."
        exit 1
    fi

    # 2. Download to a temp file.
    tmp="$(mktemp -t claude-"$version")"
    INSTALL_TMP="$tmp"
    trap cleanup_install_tmp EXIT
    info "Downloading…"
    curl -fL --progress-bar -o "$tmp" "$url"
    chmod +x "$tmp"

    # 3. Sanity-check the downloaded binary reports the expected version.
    local got
    got=$(binary_version "$tmp")
    if [ "$got" != "$version" ]; then
        err "Downloaded binary reports version '$got', expected '$version'. Aborting."
        exit 1
    fi
    ok "Downloaded and verified binary reports $version"

    # 4. Compute SHA-512 for the Info.plist.
    sum=$(shasum -a 512 "$tmp" | awk '{print $1}')

    # 5. Cache a copy under Agents/claude/<version>/ for reference.
    mkdir -p "$CACHE_DIR/$version"
    cp -f "$tmp" "$CACHE_DIR/$version/claude"
    chmod +x "$CACHE_DIR/$version/claude"

    # 6. Back up the current binary + plist (timestamp-free, version-tagged).
    if [ -x "$bin" ]; then
        local oldver
        oldver=$(binary_version "$bin")
        oldver=${oldver:-unknown}
        cp -f "$bin" "$dir/claude.${oldver}.bak"
        [ -f "$dir/Info.plist" ] && cp -f "$dir/Info.plist" "$dir/Info.plist.${oldver}.bak"
        info "Backed up current version $oldver"
    fi

    # 7. Swap in the new binary.
    cp -f "$tmp" "$bin"
    chmod +x "$bin"

    # 8. Write the matching Info.plist.
    cat > "$dir/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>checksum</key>
	<string>$sum</string>
	<key>name</key>
	<string>claude</string>
	<key>url</key>
	<string>$url</string>
	<key>version</key>
	<string>$version</string>
</dict>
</plist>
PLIST

    if ! plutil -lint "$dir/Info.plist" >/dev/null; then
        err "Generated Info.plist failed validation!"
        exit 1
    fi
    cleanup_install_tmp
    INSTALL_TMP=""
    trap - EXIT

    ok "Installed Claude $version into Xcode."
    ok "Verify with: '$bin' --version  ->  $(binary_version "$bin")"
    echo
    info "Next: relaunch Xcode. If a 'newer version available' popup appears,"
    info "close it with ✕ — clicking Update may revert to Apple's bundled version."
}

# --- Main -------------------------------------------------------------------
main() {
    if [ $# -lt 1 ]; then
        cat <<USAGE
Usage:
  $(basename "$0") <version>     Install a specific version (e.g. 2.1.195)
  $(basename "$0") latest        Install the latest GitHub release
  $(basename "$0") --current     Show installed / running version
  $(basename "$0") --restore     Roll back to the most recent backup

Quit Xcode before installing or restoring.
USAGE
        exit 1
    fi

    case "$1" in
        --current|-c) show_current ;;
        --restore|-r) restore_backup ;;
        latest|--latest|-l) install_latest ;;
        --help|-h)    main ;;
        *)            install_version "$1" ;;
    esac
}

main "$@"
