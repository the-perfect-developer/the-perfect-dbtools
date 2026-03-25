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

# Helper: apply the restore.sh GTID-stripping awk|sed pipeline directly
# This must be kept in sync with the pipeline in scripts/restore.sh
_gtid_strip() {
    printf '%s' "$1" | \
        awk '
            /^SET @@GLOBAL\.GTID_PURGED/ { skip=1 }
            skip && /;/                  { skip=0; next }
            skip                         { next }
            /^SET @@SESSION\.SQL_LOG_BIN/         { next }
            /^SET @MYSQLDUMP_TEMP_LOG_BIN/        { next }
            /^SET @@SESSION\.GTID_NEXT/           { next }
            /^\/\*!80000 SET @@GLOBAL\.GTID_PURGED/ { next }
            { print }
        ' | \
        sed \
            -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g' \
            -e 's/utf8mb4_0900_as_cs/utf8mb4_bin/g'
}

# assert_gtid_stripped: fail if pattern is still present after pipeline
assert_gtid_stripped() {
    local pattern=$1
    local desc=$2
    local input=$3
    local result
    result=$(_gtid_strip "$input")
    if echo "$result" | grep -qF -- "$pattern"; then
        fail "$desc (GTID line '$pattern' still present — not stripped)"
    else
        pass "$desc"
    fi
}

# assert_gtid_preserved: fail if pattern is missing after pipeline (corruption check)
assert_gtid_preserved() {
    local pattern=$1
    local desc=$2
    local input=$3
    local result
    result=$(_gtid_strip "$input")
    if echo "$result" | grep -qF -- "$pattern"; then
        pass "$desc"
    else
        fail "$desc (line '$pattern' missing after pipeline — adjacent SQL was corrupted)"
    fi
}

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

section "restore.sh GTID stripping - MySQL 5.7 single-line"

GTID_57_SINGLE="SET @@GLOBAL.GTID_PURGED='3E11FA47-71CA-11E1-9E33-C80AA9429562:1-5';
CREATE TABLE \`users\` (\`id\` int NOT NULL, PRIMARY KEY (\`id\`));
INSERT INTO \`users\` VALUES (1),(2);"

assert_gtid_stripped "GTID_PURGED" \
    "MySQL 5.7 single-line GTID_PURGED is stripped" \
    "$GTID_57_SINGLE"
assert_gtid_preserved "CREATE TABLE" \
    "CREATE TABLE after GTID_PURGED is preserved" \
    "$GTID_57_SINGLE"
assert_gtid_preserved "INSERT INTO" \
    "INSERT after GTID_PURGED is preserved" \
    "$GTID_57_SINGLE"

section "restore.sh GTID stripping - MySQL 8 versioned comment format"

GTID_80="SET @MYSQLDUMP_TEMP_LOG_BIN = @@SESSION.SQL_LOG_BIN;
SET @@SESSION.SQL_LOG_BIN= 0;
/*!80000 SET @@GLOBAL.GTID_PURGED=/*!*/;
SET @@SESSION.SQL_LOG_BIN = @MYSQLDUMP_TEMP_LOG_BIN;
CREATE TABLE \`products\` (\`id\` int NOT NULL);"

assert_gtid_stripped "GTID_PURGED" \
    "MySQL 8 versioned comment GTID_PURGED line is stripped" \
    "$GTID_80"
assert_gtid_stripped "MYSQLDUMP_TEMP_LOG_BIN" \
    "MYSQLDUMP_TEMP_LOG_BIN temp variable lines are stripped" \
    "$GTID_80"
assert_gtid_stripped "SQL_LOG_BIN= 0" \
    "SET @@SESSION.SQL_LOG_BIN=0 is stripped" \
    "$GTID_80"
assert_gtid_preserved "CREATE TABLE" \
    "CREATE TABLE after MySQL 8 GTID block is preserved" \
    "$GTID_80"

section "restore.sh GTID stripping - GTID_NEXT per-statement"

GTID_NEXT="SET @@SESSION.GTID_NEXT= 'AUTOMATIC';
INSERT INTO \`log\` VALUES (42, 'event');"

assert_gtid_stripped "GTID_NEXT" \
    "SET @@SESSION.GTID_NEXT is stripped" \
    "$GTID_NEXT"
assert_gtid_preserved "INSERT INTO" \
    "INSERT after GTID_NEXT is preserved" \
    "$GTID_NEXT"

section "restore.sh GTID stripping - clean dump passthrough (no GTID)"

CLEAN_DUMP="-- MySQL dump 10.13
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
CREATE TABLE \`events\` (\`id\` int NOT NULL, \`name\` varchar(255));
INSERT INTO \`events\` VALUES (1,'deploy'),(2,'rollback');
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;"

assert_gtid_preserved "CREATE TABLE" \
    "Clean dump: CREATE TABLE is preserved unchanged" \
    "$CLEAN_DUMP"
assert_gtid_preserved "INSERT INTO" \
    "Clean dump: INSERT is preserved unchanged" \
    "$CLEAN_DUMP"
assert_gtid_preserved "CHARACTER_SET_CLIENT" \
    "Clean dump: other SET statements are preserved unchanged" \
    "$CLEAN_DUMP"

section "restore.sh GTID stripping - Google Cloud SQL multi-line format"

# Google Cloud SQL / MySQL 8 produces a three-line GTID block:
#   Line 1: /*!80000 SET @@GLOBAL.GTID_PURGED=/*!*/;   (versioned comment sentinel)
#   Line 2: SET @@GLOBAL.GTID_PURGED= '+               (assignment with continuation)
#   Line 3: 'UUID:1-N';                                (bare quoted UUID range)
# Rules 1 and 2 strip lines 1 and 2. Line 3 leaked through before this fix.
GCS_SINGLE="/*!80000 SET @@GLOBAL.GTID_PURGED=/*!*/;
SET @@GLOBAL.GTID_PURGED= '+
'a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641484';

--
-- Table structure for table \`account\`
--
CREATE TABLE \`account\` (\`id\` int NOT NULL, PRIMARY KEY (\`id\`));
INSERT INTO \`account\` VALUES (1),(2);"

assert_gtid_stripped "GTID_PURGED" \
    "GCS multi-line: versioned comment GTID_PURGED line is stripped" \
    "$GCS_SINGLE"
assert_gtid_stripped "GTID_PURGED= '+" \
    "GCS multi-line: SET GTID_PURGED continuation line is stripped" \
    "$GCS_SINGLE"
assert_gtid_stripped "a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641484" \
    "GCS multi-line: bare UUID continuation line is stripped" \
    "$GCS_SINGLE"
assert_gtid_preserved "-- Table structure for table" \
    "GCS multi-line: SQL comment header after GTID block is preserved" \
    "$GCS_SINGLE"
assert_gtid_preserved "CREATE TABLE" \
    "GCS multi-line: CREATE TABLE after GTID block is preserved" \
    "$GCS_SINGLE"
assert_gtid_preserved "INSERT INTO" \
    "GCS multi-line: INSERT after GTID block is preserved" \
    "$GCS_SINGLE"

section "restore.sh GTID stripping - Google Cloud SQL concatenated two-dump format"

# When two GCS dumps are concatenated, two three-line GTID blocks appear —
# one per dump header. Both UUID continuation lines must be stripped, and
# the SQL between them (and after the second block) must be fully intact.
GCS_TWO_DUMP="/*!80000 SET @@GLOBAL.GTID_PURGED=/*!*/;
SET @@GLOBAL.GTID_PURGED= '+
'a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641484';

--
-- Table structure for table \`account\`
--
CREATE TABLE \`account\` (\`id\` int NOT NULL, PRIMARY KEY (\`id\`));
INSERT INTO \`account\` VALUES (1),(2);

/*!80000 SET @@GLOBAL.GTID_PURGED=/*!*/;
SET @@GLOBAL.GTID_PURGED= '+
'a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641486';

--
-- Table structure for table \`order\`
--
CREATE TABLE \`order\` (\`id\` int NOT NULL, PRIMARY KEY (\`id\`));
INSERT INTO \`order\` VALUES (10),(20);"

assert_gtid_stripped "a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641484" \
    "GCS concat: first dump UUID continuation line is stripped" \
    "$GCS_TWO_DUMP"
assert_gtid_stripped "a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641486" \
    "GCS concat: second dump UUID continuation line is stripped" \
    "$GCS_TWO_DUMP"
assert_gtid_preserved "CREATE TABLE \`account\`" \
    "GCS concat: CREATE TABLE from first dump is preserved" \
    "$GCS_TWO_DUMP"
assert_gtid_preserved "INSERT INTO \`account\`" \
    "GCS concat: INSERT from first dump is preserved" \
    "$GCS_TWO_DUMP"
assert_gtid_preserved "CREATE TABLE \`order\`" \
    "GCS concat: CREATE TABLE from second dump is preserved" \
    "$GCS_TWO_DUMP"
assert_gtid_preserved "INSERT INTO \`order\`" \
    "GCS concat: INSERT from second dump is preserved" \
    "$GCS_TWO_DUMP"

section "restore.sh GTID stripping - MySQL 8.0.45 bare-UUID continuation"

# mysqldump 8.0.45 emits multi-line GTID_PURGED where the continuation line
# starts directly with the UUID character (no leading single quote).
# This was the root bug: the old sed regex required a leading ' and missed it.
GTID_845_BARE="SET @MYSQLDUMP_TEMP_LOG_BIN = @@SESSION.SQL_LOG_BIN;
SET @@SESSION.SQL_LOG_BIN= 0;
SET @@GLOBAL.GTID_PURGED=/*!80000 '+'*/ '151cadb2-8bc8-11ee-b411-42010a0201e4:1-36361440,
a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641484';
CREATE TABLE \`account\` (\`id\` int NOT NULL, PRIMARY KEY (\`id\`));
INSERT INTO \`account\` VALUES (1),(2);
SET @@SESSION.SQL_LOG_BIN = @MYSQLDUMP_TEMP_LOG_BIN;"

assert_gtid_stripped "MYSQLDUMP_TEMP_LOG_BIN" \
    "8.0.45 bare-UUID: MYSQLDUMP_TEMP_LOG_BIN lines are stripped" \
    "$GTID_845_BARE"
assert_gtid_stripped "SQL_LOG_BIN= 0" \
    "8.0.45 bare-UUID: SET @@SESSION.SQL_LOG_BIN=0 is stripped" \
    "$GTID_845_BARE"
assert_gtid_stripped "GTID_PURGED" \
    "8.0.45 bare-UUID: SET @@GLOBAL.GTID_PURGED line is stripped" \
    "$GTID_845_BARE"
assert_gtid_stripped "a83c8264-a7e2-11ef-86dd-42010a02013f:1-99641484" \
    "8.0.45 bare-UUID: bare UUID continuation line is stripped (root bug fix)" \
    "$GTID_845_BARE"
assert_gtid_preserved "CREATE TABLE" \
    "8.0.45 bare-UUID: CREATE TABLE after GTID block is preserved" \
    "$GTID_845_BARE"
assert_gtid_preserved "INSERT INTO" \
    "8.0.45 bare-UUID: INSERT after GTID block is preserved" \
    "$GTID_845_BARE"

section "restore.sh GTID stripping - 3+ UUID continuation lines"

# When three or more GTID source UUIDs are present, mysqldump emits 3+ continuation
# lines. The awk loop must consume all of them until the closing ';'.
GTID_THREE_UUID="SET @@GLOBAL.GTID_PURGED=/*!80000 '+'*/ 'uuid1-1111-1111-1111-111111111111:1-10,
uuid2-2222-2222-2222-222222222222:1-20,
uuid3-3333-3333-3333-333333333333:1-30';
CREATE TABLE \`t\` (\`id\` int NOT NULL);
INSERT INTO \`t\` VALUES (99);"

assert_gtid_stripped "uuid1-1111-1111-1111-111111111111:1-10" \
    "3+ UUID: first continuation line is stripped" \
    "$GTID_THREE_UUID"
assert_gtid_stripped "uuid2-2222-2222-2222-222222222222:1-20" \
    "3+ UUID: second continuation line is stripped" \
    "$GTID_THREE_UUID"
assert_gtid_stripped "uuid3-3333-3333-3333-333333333333:1-30" \
    "3+ UUID: third continuation line is stripped" \
    "$GTID_THREE_UUID"
assert_gtid_preserved "CREATE TABLE" \
    "3+ UUID: CREATE TABLE after multi-UUID block is preserved" \
    "$GTID_THREE_UUID"
assert_gtid_preserved "INSERT INTO" \
    "3+ UUID: INSERT after multi-UUID block is preserved" \
    "$GTID_THREE_UUID"

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