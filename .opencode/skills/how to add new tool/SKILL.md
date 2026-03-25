# dbtools Development Skill

## Overview

dbtools is a modular MySQL database utility toolkit. New commands are auto-discovered from the `scripts/` folder.

## Project Structure

```
dbtools/
├── dbtools.sh           # Main entry point (auto-discovers scripts)
├── scripts/
│   ├── dump.sh          # Dump command
│   ├── restore.sh       # Restore command
│   └── <new_tool>.sh    # Add new tools here
├── .gitignore
├── LICENSE
├── README.md
└── SKILL.md
```

## Adding a New Tool

### Step 1: Create the Script

Create a new file in `scripts/` folder with `.sh` extension:

```bash
#!/bin/bash
# @description Short description of what this tool does

show_help() {
    echo "Usage: ./dbtools.sh <command_name> [OPTIONS]"
    echo ""
    echo "Description of what this command does."
    echo ""
    echo "Options:"
    echo "  -u, --user <username>     Database username (required)"
    echo "  -p, --password <password> Database password (optional)"
    echo "  -h, --host <host>         Database host (default: localhost)"
    echo "  -P, --port <port>         Database port (default: 3306)"
    echo "  -d, --database <name>     Database name (required)"
    # Add more options as needed
    echo "  --help                    Show this help message"
    echo ""
    echo "Example:"
    echo "  ./dbtools.sh <command_name> -u root -d mydb"
}

# Default values
DB_USER=""
DB_PASS=""
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME=""

# Parse arguments
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

# Validate required arguments
if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
    echo "Error: --user and --database are required"
    echo ""
    show_help
    exit 1
fi

# Build MySQL options
MYSQL_OPTS="-u $DB_USER -h $DB_HOST -P $DB_PORT"
if [ -n "$DB_PASS" ] && [ "$DB_PASS" != "" ]; then
    MYSQL_OPTS="$MYSQL_OPTS -p$DB_PASS"
fi

# ============================================
# YOUR TOOL LOGIC GOES HERE
# ============================================

echo "Tool executed successfully!"
```

### Step 2: Make it Executable

```bash
chmod +x scripts/<new_tool>.sh
```

### Step 3: Test

```bash
# Should appear in help
./dbtools.sh --help

# Should show tool-specific help
./dbtools.sh <new_tool> --help

# Test the tool
./dbtools.sh <new_tool> -u root -d mydb
```

### Step 4: Update README.md

Add documentation for the new command in the `## Commands` section.

## Key Conventions

### @description Comment

The second line MUST contain the description comment:

```bash
#!/bin/bash
# @description Your tool description here
```

This is read by `dbtools.sh` to display in the help output.

### Naming

- Script filename becomes the command name: `scripts/migrate.sh` → `./dbtools.sh migrate`
- Use lowercase, single-word names when possible
- Use hyphens for multi-word names: `schema-diff.sh` → `./dbtools.sh schema-diff`

### Standard Options

Always include these common database options for consistency:

| Short | Long | Description |
|-------|------|-------------|
| `-u` | `--user` | Database username |
| `-p` | `--password` | Database password |
| `-h` | `--host` | Database host |
| `-P` | `--port` | Database port |
| `-d` | `--database` | Database name |
| | `--help` | Show help message |

### Password Handling

Handle empty password correctly to avoid MySQL "using password: NO" errors:

```bash
-p|--password)
    if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
        DB_PASS="$2"
        shift 2
    else
        shift
    fi
    ;;
```

### Error Handling

- Exit with `exit 1` on errors
- Exit with `exit 0` on success
- Show help on validation errors

### Progress Display

Use `pv` for progress display when processing large files:

```bash
pv -s $FILE_SIZE "$SQL_FILE" | mysql $MYSQL_OPTS "$DB_NAME"
```

## Example: Adding a "tables" Command

To add a command that lists all tables in a database:

**scripts/tables.sh:**
```bash
#!/bin/bash
# @description List all tables in a database

show_help() {
    echo "Usage: ./dbtools.sh tables [OPTIONS]"
    echo ""
    echo "List all tables in a MySQL database."
    echo ""
    echo "Options:"
    echo "  -u, --user <username>     Database username (required)"
    echo "  -p, --password <password> Database password (optional)"
    echo "  -h, --host <host>         Database host (default: localhost)"
    echo "  -P, --port <port>         Database port (default: 3306)"
    echo "  -d, --database <name>     Database name (required)"
    echo "  --help                    Show this help message"
}

DB_USER=""
DB_PASS=""
DB_HOST="localhost"
DB_PORT="3306"
DB_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--user) DB_USER="$2"; shift 2 ;;
        --user=*) DB_USER="${1#*=}"; shift ;;
        -p|--password)
            if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                DB_PASS="$2"; shift 2
            else
                shift
            fi
            ;;
        --password=*) DB_PASS="${1#*=}"; shift ;;
        -h|--host) DB_HOST="$2"; shift 2 ;;
        --host=*) DB_HOST="${1#*=}"; shift ;;
        -P|--port) DB_PORT="$2"; shift 2 ;;
        --port=*) DB_PORT="${1#*=}"; shift ;;
        -d|--database) DB_NAME="$2"; shift 2 ;;
        --database=*) DB_NAME="${1#*=}"; shift ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
    echo "Error: --user and --database are required"
    show_help
    exit 1
fi

MYSQL_OPTS="-u $DB_USER -h $DB_HOST -P $DB_PORT"
if [ -n "$DB_PASS" ]; then
    MYSQL_OPTS="$MYSQL_OPTS -p$DB_PASS"
fi

mysql $MYSQL_OPTS -e "SHOW TABLES FROM \`$DB_NAME\`;"
```

Then:
```bash
chmod +x scripts/tables.sh
./dbtools.sh tables -u root -d mydb
```

## Checklist for New Tools

- [ ] Created script in `scripts/` folder
- [ ] Added `# @description` on line 2
- [ ] Made script executable (`chmod +x`)
- [ ] Included standard database options (-u, -p, -h, -P, -d)
- [ ] Included `--help` option
- [ ] Validated required arguments
- [ ] Handled password correctly (empty password case)
- [ ] Tested with `./dbtools.sh --help`
- [ ] Tested with `./dbtools.sh <command> --help`
- [ ] Updated README.md with new command documentation
