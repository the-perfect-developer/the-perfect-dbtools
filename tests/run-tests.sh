#!/bin/bash
set -uo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

PASS=0
FAIL=0
ERRORS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'  # No Color

pass() { printf "  ${GREEN}✓${NC} %s\n" "$1"; ((PASS++)); }
fail() { printf "  ${RED}✗${NC} %s\n" "$1"; ERRORS+=("$1"); ((FAIL++)); }
section() { printf "\n${CYAN}── %s ──${NC}\n" "$1"; }

assert_exit() {
    local expected_exit=$1
    local desc=$2
    shift 2
    local output
    output=$("$@" 2>&1)
    local actual_exit=$?
    if [ $actual_exit -eq $expected_exit ]; then
        pass "$desc"
    else
        fail "$desc (expected exit $expected_exit, got $actual_exit)"
    fi
}

assert_output_contains() {
    local pattern=$1
    local desc=$2
    shift 2
    local output
    output=$("$@" 2>&1)
    if echo "$output" | grep -F -q -- "$pattern"; then
        pass "$desc"
    else
        fail "$desc (pattern '$pattern' not found in output)"
    fi
}

assert_exit_and_output() {
    local expected_exit=$1
    local pattern=$2
    local desc=$3
    shift 3
    local output
    output=$("$@" 2>&1)
    local actual_exit=$?
    if [ $actual_exit -eq $expected_exit ] && echo "$output" | grep -F -q -- "$pattern"; then
        pass "$desc"
    else
        fail "$desc (expected exit $expected_exit with pattern '$pattern', got exit $actual_exit)"
    fi
}

DBTOOLS="$REPO_ROOT/dbtools.sh"
DUMP="$REPO_ROOT/scripts/dump.sh"
RESTORE="$REPO_ROOT/scripts/restore.sh"
UPDATE="$REPO_ROOT/scripts/update.sh"
INSTALL="$REPO_ROOT/install.sh"
GET="$REPO_ROOT/get.sh"

section "Bash syntax"
for script in "$DBTOOLS" "$DUMP" "$RESTORE" "$UPDATE" "$INSTALL" "$GET"; do
    if bash -n "$script"; then
        pass "Syntax check: $(basename "$script")"
    else
        fail "Syntax check: $(basename "$script")"
    fi
done

section "Executable permissions"
for script in "$DBTOOLS" "$DUMP" "$RESTORE" "$UPDATE"; do
    if [ -x "$script" ]; then
        pass "Executable: $(basename "$script")"
    else
        fail "Executable: $(basename "$script")"
    fi
done

section "@description annotations"
for script in "$DUMP" "$RESTORE" "$UPDATE"; do
    if grep -q "^# @description" "$script"; then
        pass "@description: $(basename "$script")"
    else
        fail "@description: $(basename "$script") (script will not appear in help)"
    fi
done

section "dbtools dispatcher"
assert_exit 0 "--help exits 0" "$DBTOOLS" --help
assert_exit 0 "-h exits 0" "$DBTOOLS" -h
assert_exit 0 "help exits 0" "$DBTOOLS" help
assert_exit 0 "--version exits 0" "$DBTOOLS" --version
assert_exit 0 "-v exits 0" "$DBTOOLS" -v
assert_exit 1 "no args exits 1" "$DBTOOLS"
assert_exit 1 "unknown command exits 1" "$DBTOOLS" __no_such_cmd__

assert_output_contains "dbtools v" "--version format" "$DBTOOLS" --version
assert_output_contains "dump" "--help lists dump" "$DBTOOLS" --help
assert_output_contains "restore" "--help lists restore" "$DBTOOLS" --help
assert_output_contains "update" "--help lists update" "$DBTOOLS" --help
assert_output_contains "Unknown command" "unknown cmd error text" "$DBTOOLS" __no_such_cmd__

section "dump.sh help"
assert_exit 0 "--help exits 0" "$DUMP" --help
assert_output_contains "Usage" "help: Usage" "$DUMP" --help
assert_output_contains "--user" "help: --user" "$DUMP" --help
assert_output_contains "--limit" "help: --limit" "$DUMP" --help
assert_output_contains "--tables" "help: --tables" "$DUMP" --help
assert_output_contains "requires" "help: --tables requires note" "$DUMP" --help

section "dump.sh required arg validation"
assert_exit_and_output 1 "--user and --database are required" "no args" "$DUMP"
assert_exit_and_output 1 "--user and --database are required" "-u only (no -d)" "$DUMP" -u root
assert_exit_and_output 1 "--user and --database are required" "-d only (no -u)" "$DUMP" -d testdb
assert_exit_and_output 1 "--user and --database are required" "--user= only" "$DUMP" --user=root
assert_exit_and_output 1 "--user and --database are required" "--database= only" "$DUMP" --database=testdb

section "dump.sh --tables/--limit constraint"
assert_exit_and_output 1 "--tables requires --limit" "-t without -l (short)" "$DUMP" -u root -d testdb -t users
assert_exit_and_output 1 "--tables requires --limit" "--tables without --limit (long)" "$DUMP" -u root -d testdb --tables=users
assert_exit_and_output 1 "--tables requires --limit" "--tables= without --limit= (=format)" "$DUMP" --user=root --database=testdb --tables=users
assert_exit_and_output 1 "--tables requires --limit" "multiple tables without limit" "$DUMP" -u root -d testdb -t users,orders,products

section "dump.sh unknown flags"
assert_exit_and_output 1 "Unknown option" "unknown long flag" "$DUMP" --nonexistent
assert_exit_and_output 1 "Unknown option" "unknown short flag" "$DUMP" -Z

section "restore.sh help"
assert_exit 0 "--help exits 0" "$RESTORE" --help
assert_output_contains "Usage" "help: Usage" "$RESTORE" --help
assert_output_contains "--file" "help: --file" "$RESTORE" --help
assert_output_contains "--user" "help: --user" "$RESTORE" --help

section "restore.sh required arg validation"
assert_exit_and_output 1 "--user, --database, and --file are required" "no args" "$RESTORE"
assert_exit_and_output 1 "--user, --database, and --file are required" "-u -d only (no -f)" "$RESTORE" -u root -d testdb
assert_exit_and_output 1 "--user, --database, and --file are required" "-u -f only (no -d)" "$RESTORE" -u root -f backup.sql
assert_exit_and_output 1 "--user, --database, and --file are required" "-d -f only (no -u)" "$RESTORE" -d testdb -f backup.sql
assert_exit_and_output 1 "--user, --database, and --file are required" "--user= --database= only" "$RESTORE" --user=root --database=testdb

section "restore.sh file-not-found"
assert_exit_and_output 1 "not found" "absolute path does not exist" "$RESTORE" -u root -d testdb -f /tmp/dbtools_no_such_file_xyz_abc.sql
assert_exit_and_output 1 "not found" "relative path does not exist" "$RESTORE" -u root -d testdb -f ./no_such_file_xyz_abc.sql
assert_exit_and_output 1 "not found" "=format file not found" "$RESTORE" --user=root --database=testdb --file=/tmp/dbtools_no_such_file.sql

section "restore.sh validation order (arg check before file check)"
assert_exit_and_output 1 "--user, --database, and --file are required" "arg check precedes file check" "$RESTORE" -u root -f /tmp/dbtools_no_such_file.sql

section "restore.sh unknown flags"
assert_exit_and_output 1 "Unknown option" "unknown long flag" "$RESTORE" --nonexistent
assert_exit_and_output 1 "Unknown option" "unknown short flag" "$RESTORE" -Z

section "update.sh help and unknown flags"
assert_exit 0 "--help exits 0" "$UPDATE" --help
assert_output_contains "Usage" "help: Usage" "$UPDATE" --help
assert_exit_and_output 1 "Unknown option" "unknown flag" "$UPDATE" --nonexistent

printf "\nSummary: %d passed, %d failed\n" "$PASS" "$FAIL"
if [ ${#ERRORS[@]} -gt 0 ]; then
    printf "Failures:\n"
    for error in "${ERRORS[@]}"; do
        printf "  - %s\n" "$error"
    done
    exit 1
else
    exit 0
fi