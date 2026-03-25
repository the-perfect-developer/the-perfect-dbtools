#!/bin/bash
# @description Restore a MySQL database from a SQL file
# @category Database

show_help() {
    echo "Usage: ./dbtools.sh restore [OPTIONS]"
    echo ""
    echo "Restore a MySQL database from a SQL file."
    echo ""
    echo "Options:"
    echo "  -u, --user <username>     Database username (required)"
    echo "  -p, --password <password> Database password (optional)"
    echo "  -h, --host <host>         Database host (default: localhost)"
    echo "  -P, --port <port>         Database port (default: 3306)"
    echo "  -d, --database <name>     Database name (required)"
    echo "  -f, --file <file>         SQL file to restore (required)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Example:"
    echo "  ./dbtools.sh restore -u root -p secret -h localhost -P 3306 -d mydb -f backup.sql"
    echo "  ./dbtools.sh restore --user=root --password=secret --database=mydb --file=backup.sql"
}

DB_USER=""
DB_PASS=""
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME=""
SQL_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -u | --user)
            DB_USER="$2"
            shift 2
            ;;
        --user=*)
            DB_USER="${1#*=}"
            shift
            ;;
        -p | --password)
            DB_PASS="$2"
            shift 2
            ;;
        --password=*)
            DB_PASS="${1#*=}"
            shift
            ;;
        -h | --host)
            DB_HOST="$2"
            shift 2
            ;;
        --host=*)
            DB_HOST="${1#*=}"
            shift
            ;;
        -P | --port)
            DB_PORT="$2"
            shift 2
            ;;
        --port=*)
            DB_PORT="${1#*=}"
            shift
            ;;
        -d | --database)
            DB_NAME="$2"
            shift 2
            ;;
        --database=*)
            DB_NAME="${1#*=}"
            shift
            ;;
        -f | --file)
            SQL_FILE="$2"
            shift 2
            ;;
        --file=*)
            SQL_FILE="${1#*=}"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ] || [ -z "$SQL_FILE" ]; then
    echo "Error: --user, --database, and --file are required"
    echo ""
    show_help
    exit 1
fi

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: File '$SQL_FILE' not found"
    exit 1
fi

MYSQL_OPTS="-u $DB_USER -h $DB_HOST -P $DB_PORT"
if [ -n "$DB_PASS" ] && [ "$DB_PASS" != "" ]; then
    MYSQL_OPTS="$MYSQL_OPTS -p$DB_PASS"
fi

echo "Restoring database: $DB_NAME"
echo "From file: $SQL_FILE"
echo ""

mysql $MYSQL_OPTS -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "Error: Failed to create database"
    exit 1
fi

FILE_SIZE=$(stat -c%s "$SQL_FILE" 2>/dev/null || stat -f%z "$SQL_FILE" 2>/dev/null)

# Check for GTID statements and warn if present
if grep -qE '^SET @@(GLOBAL\.GTID_PURGED|SESSION\.GTID_NEXT|SESSION\.SQL_LOG_BIN)|^SET @MYSQLDUMP_TEMP_LOG_BIN' "$SQL_FILE"; then
    echo "⚠  Warning: Dump contains GTID/binary-log control statements."
    echo "   These require SUPER or SYSTEM_VARIABLES_ADMIN privileges and"
    echo "   are incompatible with servers that have GTID_MODE=OFF."
    echo "   Stripping automatically for local restore compatibility."
    echo ""
fi

# Check for DEFINER statements and warn if present
if grep -qE 'DEFINER=' "$SQL_FILE"; then
    echo "⚠  Warning: Dump contains DEFINER clauses."
    echo "   Stripping automatically for restore compatibility."
    echo ""
fi

echo "Importing data..."
pv -s "$FILE_SIZE" "$SQL_FILE" \
    | awk '
    /^SET @@GLOBAL\.GTID_PURGED/ { skip=1 }
    skip && /;/                  { skip=0; next }
    skip                         { next }
    /^SET @@SESSION\.SQL_LOG_BIN/         { next }
    /^SET @MYSQLDUMP_TEMP_LOG_BIN/        { next }
    /^SET @@SESSION\.GTID_NEXT/           { next }
    /^\/\*!80000 SET @@GLOBAL\.GTID_PURGED/ { next }
    { print }
  ' \
    | sed \
        -e 's/utf8mb4_0900_ai_ci/utf8mb4_general_ci/g' \
        -e 's/utf8mb4_0900_as_cs/utf8mb4_bin/g' \
        -e 's/CREATE DEFINER=`[^`]*`@`[^`]*` PROCEDURE/CREATE PROCEDURE/g' \
        -e 's/CREATE DEFINER=`[^`]*`@`[^`]*` FUNCTION/CREATE FUNCTION/g' \
        -e 's/\/\*!5[0-9][0-9][0-9][0-9] DEFINER=`[^`]*`@`[^`]*`\*\/ //g' \
        -e 's/\/\*!50013 DEFINER=`[^`]*`@`[^`]*` SQL SECURITY DEFINER \*\//\/\*!50013 SQL SECURITY INVOKER \*\//g' \
    | mysql $MYSQL_OPTS "$DB_NAME"

if [ $? -eq 0 ]; then
    echo ""
    echo "Restore complete! Database: $DB_NAME"
else
    echo ""
    echo "Error: Restore failed"
    exit 1
fi
