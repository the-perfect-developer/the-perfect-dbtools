#!/bin/bash
# install-hooks.sh
#
# Sets up git hooks for dbtools development.
# Run once after cloning the repository.
#
# Usage:
#   ./install-hooks.sh            # Install hooks
#   ./install-hooks.sh --uninstall  # Restore default hook path
#   ./install-hooks.sh --check      # Show current status
#   ./install-hooks.sh --help       # Show help

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/.githooks"

print_usage() {
    echo ""
    echo "Usage: ./install-hooks.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (none)        Install hooks (configure git to use .githooks/)"
    echo "  --uninstall   Restore git default hook path"
    echo "  --check       Show current hook installation status"
    echo "  --help        Show this message"
    echo ""
}

check_git_repo() {
    if ! git rev-parse --git-dir &>/dev/null; then
        echo -e "${RED}✗ Not inside a git repository${NC}"
        exit 1
    fi
}

install_hooks() {
    check_git_repo

    echo ""
    echo -e "${CYAN}Installing dbtools git hooks...${NC}"
    echo ""

    if [ ! -d "$HOOKS_DIR" ]; then
        echo -e "${RED}✗ .githooks/ directory not found at: ${HOOKS_DIR}${NC}"
        echo -e "${DIM}  Check your git clone is complete${NC}"
        exit 1
    fi

    # Make all hooks executable
    hooks_made_executable=0
    for hook in "$HOOKS_DIR"/*; do
        [ -f "$hook" ] || continue
        [[ "$(basename "$hook")" == *.md ]] && continue
        if [ ! -x "$hook" ]; then
            chmod +x "$hook"
            ((hooks_made_executable++))
        fi
    done

    if [ "$hooks_made_executable" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Made ${hooks_made_executable} hook(s) executable"
    fi

    git config core.hooksPath .githooks
    echo -e "  ${GREEN}✓${NC} git config core.hooksPath → .githooks"

    echo ""
    echo -e "${DIM}Active hooks:${NC}"
    for hook in "$HOOKS_DIR"/*; do
        [ -f "$hook" ] || continue
        hook_name="$(basename "$hook")"
        [[ "$hook_name" == *.md ]] && continue
        echo -e "  ${GREEN}•${NC} ${hook_name}"
    done

    echo ""
    echo -e "${DIM}Optional tool availability:${NC}"
    if command -v shellcheck &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} shellcheck $(shellcheck --version | grep 'version:' | awk '{print $2}')"
    else
        echo -e "  ${YELLOW}⚠${NC} shellcheck ${DIM}not found — pre-commit will warn but not block${NC}"
        echo -e "    ${DIM}Install: sudo apt install shellcheck  OR  brew install shellcheck${NC}"
    fi

    if command -v shfmt &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} shfmt $(shfmt --version)"
    else
        echo -e "  ${YELLOW}⚠${NC} shfmt ${DIM}not found — format check will be skipped${NC}"
        echo -e "    ${DIM}Install: brew install shfmt  OR  go install mvdan.cc/sh/v3/cmd/shfmt@latest${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ Git hooks installed successfully${NC}"
    echo ""
    echo -e "${DIM}To check status: ./install-hooks.sh --check${NC}"
    echo -e "${DIM}To uninstall:    ./install-hooks.sh --uninstall${NC}"
    echo ""
}

uninstall_hooks() {
    check_git_repo

    echo ""
    echo -e "${CYAN}Uninstalling dbtools git hooks...${NC}"
    echo ""

    current_path=$(git config core.hooksPath 2>/dev/null || echo "")

    if [ -z "$current_path" ]; then
        echo -e "${YELLOW}⚠ No custom hooksPath configured — hooks not installed${NC}"
        exit 0
    fi

    git config --unset core.hooksPath
    echo -e "  ${GREEN}✓${NC} Removed core.hooksPath (restored to .git/hooks/)"
    echo ""
    echo -e "${GREEN}✓ Hooks uninstalled${NC}"
    echo ""
}

check_status() {
    check_git_repo

    echo ""
    echo -e "${CYAN}Git hook status:${NC}"
    echo ""

    hooks_path=$(git config core.hooksPath 2>/dev/null || echo "")

    if [ -z "$hooks_path" ]; then
        echo -e "  ${YELLOW}⚠${NC} core.hooksPath: ${DIM}not set (using .git/hooks/)${NC}"
        echo -e "  ${DIM}Run ./install-hooks.sh to install${NC}"
    elif [ "$hooks_path" = ".githooks" ]; then
        echo -e "  ${GREEN}✓${NC} core.hooksPath: ${hooks_path}"
        echo ""
        echo -e "${DIM}Active hooks:${NC}"
        for hook in "$HOOKS_DIR"/*; do
            [ -f "$hook" ] || continue
            hook_name="$(basename "$hook")"
            [[ "$hook_name" == *.md ]] && continue
            if [ -x "$hook" ]; then
                echo -e "  ${GREEN}✓${NC} ${hook_name} ${DIM}(executable)${NC}"
            else
                echo -e "  ${RED}✗${NC} ${hook_name} ${DIM}(not executable — run chmod +x)${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}⚠${NC} core.hooksPath: ${hooks_path} ${DIM}(unexpected value)${NC}"
    fi

    echo ""
}

case "${1:-}" in
    --uninstall)
        uninstall_hooks
        ;;
    --check)
        check_status
        ;;
    --help)
        print_usage
        ;;
    "")
        install_hooks
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        print_usage
        exit 1
        ;;
esac