#!/bin/bash
# @description Dump a MySQL database
# @category Database

show_help() {
    echo "Usage: ./dbtools.sh dump [OPTIONS]"
    echo ""
    echo "Dump a MySQL database with optional table filtering."
    echo ""
    echo "Options:"
    echo "  -u, --user <username>     Database username (required)"
    echo "  -p, --password <password> Database password (optional)"
    echo "  -h, --host <host>         Database host (default: localhost)"
    echo "  -P, --port <port>         Database port (default: 3306)"
    echo "  -d, --database <name>     Database name (required)"
    echo "  -o, --output <file>       Output SQL file (default: <database>.sql)"
    echo "  -l, --limit <number>      Max records per table (without this, dumps all records)"
    echo "  -t, --tables <list>       Comma-separated list of tables to dump fully (requires -l)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Example:"
    echo "  ./dbtools.sh dump -u root -d mydb                          # Full dump"
    echo "  ./dbtools.sh dump -u root -d mydb --limit=1000             # Limit all tables to 1000 records"
    echo "  ./dbtools.sh dump -u root -d mydb -l 500 -t users,orders   # Limit to 500, but full dump for users,orders"
}

DB_USER=""
DB_PASS=""
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME=""
DUMP_FILE=""
RECORD_LIMIT=""
FULL_TABLES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user)
            DB_USER="$2"
            shift 2
            ;;
        --user=*)
            DB_USER="${1#*=}"
            shift
            ;;
        -p|--password)
            if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                DB_PASS="$2"
                shift 2
            else
                shift
            fi
            ;;
        --password=*)
            DB_PASS="${1#*=}"
            shift
            ;;
        -h|--host)
            DB_HOST="$2"
            shift 2
            ;;
        --host=*)
            DB_HOST="${1#*=}"
            shift
            ;;
        -P|--port)
            DB_PORT="$2"
            shift 2
            ;;
        --port=*)
            DB_PORT="${1#*=}"
            shift
            ;;
        -d|--database)
            DB_NAME="$2"
            shift 2
            ;;
        --database=*)
            DB_NAME="${1#*=}"
            shift
            ;;
        -o|--output)
            DUMP_FILE="$2"
            shift 2
            ;;
        --output=*)
            DUMP_FILE="${1#*=}"
            shift
            ;;
        -l|--limit)
            RECORD_LIMIT="$2"
            shift 2
            ;;
        --limit=*)
            RECORD_LIMIT="${1#*=}"
            shift
            ;;
        -t|--tables)
            FULL_TABLES="$2"
            shift 2
            ;;
        --tables=*)
            FULL_TABLES="${1#*=}"
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

if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
    echo "Error: --user and --database are required"
    echo ""
    show_help
    exit 1
fi

if [ -n "$FULL_TABLES" ] && [ -z "$RECORD_LIMIT" ]; then
    echo "Error: --tables requires --limit to be set"
    echo "       (Use -l to limit other tables, -t to specify which tables get full dump)"
    echo ""
    show_help
    exit 1
fi

if [ -z "$DUMP_FILE" ]; then
    DUMP_FILE="${DB_NAME}.sql"
fi

PROGRESS_FILE="${DB_NAME}.progress"

IFS=',' read -ra SELECTED_TABLES <<< "$FULL_TABLES"

MYSQL_OPTS="-u $DB_USER -h $DB_HOST -P $DB_PORT"
if [ -n "$DB_PASS" ] && [ "$DB_PASS" != "" ]; then
    MYSQL_OPTS="$MYSQL_OPTS -p$DB_PASS"
fi

is_selected_table() {
    local table="$1"
    for selected in "${SELECTED_TABLES[@]}"; do
        if [[ "$selected" == "$table" ]]; then
            return 0
        fi
    done
    return 1
}

is_table_done() {
    local table="$1"
    if [ -f "$PROGRESS_FILE" ]; then
        grep -qx "$table" "$PROGRESS_FILE"
        return $?
    fi
    return 1
}

mark_table_done() {
    echo "$1" >> "$PROGRESS_FILE"
}

mkdir -p "$(dirname "$DUMP_FILE")"

if [ -f "$PROGRESS_FILE" ]; then
    DONE_COUNT=$(wc -l < "$PROGRESS_FILE")
    echo "Resuming previous dump. $DONE_COUNT tables already completed."
    echo ""
else
    > "$DUMP_FILE"
fi

# shellcheck disable=SC2086 # TODO: convert MYSQL_OPTS to array
TABLES=($(mysql $MYSQL_OPTS -N -e \
  "SELECT table_name FROM information_schema.tables WHERE table_schema='$DB_NAME' AND table_type='BASE TABLE';"))

TOTAL_TABLES=${#TABLES[@]}
CURRENT=0

echo "Found $TOTAL_TABLES tables to dump"
echo ""

for t in "${TABLES[@]}"; do
    ((CURRENT++))

    if is_table_done "$t"; then
        echo "[$CURRENT/$TOTAL_TABLES] Skipping (already done): $t"
        continue
    fi

    if [ -z "$RECORD_LIMIT" ] || is_selected_table "$t"; then
        echo "[$CURRENT/$TOTAL_TABLES] Dumping table (full): $t"
         # shellcheck disable=SC2086 # TODO: convert MYSQL_OPTS to array
         if mysqldump $MYSQL_OPTS $DB_NAME $t \
             --single-transaction \
             --quick \
             --routines \
             --triggers \
             --events \
             --no-tablespaces \
             --set-gtid-purged=OFF \
             2>/dev/null | pv -N "$t" >> "$DUMP_FILE"; then
            mark_table_done "$t"
        else
            echo "Error dumping $t. Restart script to resume."
            exit 1
        fi
    else
        echo "[$CURRENT/$TOTAL_TABLES] Dumping table (latest $RECORD_LIMIT): $t"
         # shellcheck disable=SC2086 # TODO: convert MYSQL_OPTS to array
         if ! mysqldump $MYSQL_OPTS $DB_NAME $t \
             --single-transaction \
             --no-data \
             --no-tablespaces \
             --set-gtid-purged=OFF \
             2>/dev/null >> "$DUMP_FILE"; then
            echo "Error dumping $t structure. Restart script to resume."
            exit 1
        fi
         # shellcheck disable=SC2086 # TODO: convert MYSQL_OPTS to array
         if mysqldump $MYSQL_OPTS $DB_NAME $t \
             --single-transaction \
             --no-create-info \
             --no-tablespaces \
             --set-gtid-purged=OFF \
             --where="1=1 ORDER BY 1 DESC LIMIT $RECORD_LIMIT" \
             2>/dev/null | pv -N "$t" >> "$DUMP_FILE"; then
            mark_table_done "$t"
        else
            echo "Error dumping $t data. Restart script to resume."
            exit 1
        fi
    fi

done

rm -f "$PROGRESS_FILE"

echo ""
echo "Dump complete! File: $DUMP_FILE"
echo "Total size: $(du -h "$DUMP_FILE" | cut -f1)"
