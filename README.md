# Xcode Claude Updater

A small installer script that swaps Xcode's built-in Claude Code assistant binary with a specific Anthropic Claude Code CLI release.

It downloads the chosen version from the official CDN, verifies it, backs up the current `claude` binary and `Info.plist`, installs the requested version, and writes matching agent metadata so Xcode uses it.

## Requirements

- macOS
- Xcode installed
- Xcode launched at least once so the `CodingAssistant` agent directory exists
- `bash`, `curl`, `shasum`, and `plutil` available

## Install

Clone or download this repository and make the script executable:

```bash
git clone https://github.com/MonteLuck/Claude-for-Xcode-Updater.git
cd Claude-for-Xcode-Updater
chmod +x update-xcode-claude.sh
```

## Usage

```bash
./update-xcode-claude.sh <version>
```

Example:

```bash
./update-xcode-claude.sh 2.1.195
```

To install the latest Claude Code release published on GitHub:

```bash
./update-xcode-claude.sh latest
```

### Optional shell shortcut

To run the updater from anywhere without typing the full script path, add a small function to `~/.zshrc`.
From inside the cloned repository, run:

```bash
printf '\nupdate-xcode-claude() {\n  "%s/update-xcode-claude.sh" "$@"\n}\n' "$(pwd)" >> ~/.zshrc
```

Reload your shell config:

```bash
source ~/.zshrc
```

Then run:

```bash
update-xcode-claude 2.1.195
update-xcode-claude latest
update-xcode-claude --current
```

Use the official Claude CLI changelog to find the latest available version:

https://code.claude.com/docs/en/changelog

### Other commands

- Show the currently installed / running version:

```bash
./update-xcode-claude.sh --current
```

- Restore the most recent backup:

```bash
./update-xcode-claude.sh --restore
```

## How it works

1. Detects your machine architecture (`darwin-arm64` or `darwin-x64`)
2. Finds the active Xcode Claude agent directory under `~/Library/Developer/Xcode/CodingAssistant/Agents/XcodeVersions`
3. If `latest` is requested, resolves the latest Claude Code release from GitHub
4. Downloads the requested version from the Anthropic Claude Code releases CDN
5. Verifies the binary reports the requested version
6. Computes a SHA-512 checksum and writes `Info.plist`
7. Backs up the existing `claude` binary and `Info.plist`
8. Installs the requested version into the Xcode agent directory

## Notes

- Quit Xcode before installing or restoring. The script will refuse to run while Xcode is active.
- If Xcode shows a "newer version is available" popup after relaunching, close it with the close button (`✕`). Clicking "Update" may revert you to Apple's bundled version.
- The script caches downloaded binaries under `~/Library/Developer/Xcode/CodingAssistant/Agents/claude/<version>/claude`.

## Troubleshooting

- If the script cannot find the Xcode agent directory, launch Xcode at least once and then rerun the script.
- If a version is not found, verify the version number is correct and that the release exists for your platform.
- If `latest` cannot be resolved, check your internet connection or install a specific version manually.
- Use `./update-xcode-claude.sh --current` to inspect installed and running versions.

## License

This repository contains a helper script for Xcode Claude binary management.

> Use at your own risk. Backups are created automatically, but modifying Xcode internals can affect your environment.
