#!/bin/bash
# ensure-kit.sh — make sure llm-kit is available at the configured install path
# usage: ensure-kit.sh <command> [args...]
#
# commands:
#   install [source] [method] [path] [local_path]
#       — install kit if missing; idempotent
#       — source default: $KIT_SOURCE env var or https://github.com/g-agent-lab/llm-kit.git
#       — method default: $KIT_INSTALL_METHOD or submodule (submodule | copy | local)
#       — path default:   $KIT_INSTALL_PATH or external/llm-kit
#       — local_path:     used only when method=local; absolute path to local clone
#       — outputs the resolved kit path on stdout (one line)
#
#   check-only
#       — exit 0 if kit present, exit 1 otherwise; no install attempted
#       — outputs the resolved kit path on stdout
#
#   kit-path
#       — print resolved kit path and exit 0; does not check presence
#
# the skill calls this script in the user's project working directory.

set -e

cmd="${1:-install}"
shift || true

# resolve defaults
src="${1:-${KIT_SOURCE:-https://github.com/g-agent-lab/llm-kit.git}}"
method="${2:-${KIT_INSTALL_METHOD:-submodule}}"
path="${3:-${KIT_INSTALL_PATH:-external/llm-kit}}"
local_path="${4:-${KIT_LOCAL_PATH:-}}"

is_present() {
    [ -d "$path" ] && [ -f "$path/UNIVERSAL_CORE.md" ] && [ -d "$path/bootstrap" ] && [ -d "$path/overlays" ]
}

case "$cmd" in
    kit-path)
        echo "$path"
        exit 0
        ;;
    check-only)
        echo "$path"
        if is_present; then exit 0; fi
        exit 1
        ;;
    install)
        echo "$path"
        if is_present; then
            echo "kit already present at $path" >&2
            exit 0
        fi
        echo "installing llm-kit via method=$method into $path" >&2
        mkdir -p "$(dirname "$path")"
        case "$method" in
            submodule)
                if [ ! -d .git ]; then
                    echo "error: submodule method requires a git repo; run 'git init' first or use method=copy" >&2
                    exit 2
                fi
                git submodule add "$src" "$path"
                ;;
            copy)
                tmp="$(mktemp -d)"
                git clone --depth 1 "$src" "$tmp/llm-kit"
                rm -rf "$tmp/llm-kit/.git"
                mkdir -p "$path"
                cp -R "$tmp/llm-kit/." "$path/"
                rm -rf "$tmp"
                ;;
            local)
                if [ -z "$local_path" ]; then
                    echo "error: install_method=local requires kit_local_path userConfig (or KIT_LOCAL_PATH env)" >&2
                    exit 2
                fi
                if [ ! -d "$local_path" ]; then
                    echo "error: local kit path not found: $local_path" >&2
                    exit 2
                fi
                mkdir -p "$path"
                cp -R "$local_path/." "$path/"
                ;;
            *)
                echo "error: unknown install method: $method (expected submodule | copy | local)" >&2
                exit 2
                ;;
        esac
        if ! is_present; then
            echo "error: install completed but kit layout looks wrong at $path" >&2
            exit 3
        fi
        echo "kit installed at $path" >&2
        ;;
    *)
        echo "error: unknown ensure-kit.sh command: $cmd" >&2
        exit 2
        ;;
esac
