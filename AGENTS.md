# AGENTS.md - Guidelines for AI Coding Agents

This file provides instructions for AI agents (Claude, Copilot, Cursor, etc.) working on dbtools.

## Project Overview

dbtools is a modular MySQL database utility toolkit written in Bash. Commands are auto-discovered from the `scripts/` folder based on `# @description` comments.

## Project Structure

```
dbtools/
├── dbtools.sh           # Main entry point (auto-discovers scripts)
├── scripts/
│   ├── dump.sh          # Database dump command
│   ├── restore.sh       # Database restore command
│   ├── update.sh        # Self-update command
│   └── <new>.sh         # New tools go here
├── tests/
│   └── run-tests.sh     # No-DB test suite (run locally and in CI)
├── .githooks/           # Versioned git hooks (install with install-hooks.sh)
│   ├── pre-commit
│   ├── commit-msg
│   ├── pre-push
│   └── README.md
├── .github/
│   └── workflows/
│       └── ci.yml       # CI pipeline (ShellCheck, shfmt, tests, security)
├── install-hooks.sh     # One-command hook setup for contributors
├── install.sh           # Local system installer
├── get.sh               # Remote curl installer
├── CONTRIBUTING.md      # Contribution guidelines
├── TODO.md              # Planned features and improvements
├── .gitignore
├── LICENSE              # GPL-3.0
├── README.md
└── AGENTS.md            # This file
```

## Build/Test Commands

```bash
# Test main help
./dbtools.sh --help

# Test specific command help
./dbtools.sh dump --help
./dbtools.sh restore --help
./dbtools.sh update --help

# Test version output
./dbtools.sh --version

# Test unknown command handling
./dbtools.sh unknowncommand 2>&1 | grep -q "Unknown command"

# Test dump (requires MySQL connection)
./dbtools.sh dump -u root -d testdb

# Test restore (requires MySQL connection)
./dbtools.sh restore -u root -d testdb -f backup.sql

# Check script syntax without running
bash -n dbtools.sh
bash -n scripts/dump.sh
bash -n scripts/restore.sh
bash -n scripts/update.sh
bash -n install.sh
bash -n get.sh

# Run full no-DB test suite (no MySQL needed)
bash tests/run-tests.sh

# Make scripts executable after creation
chmod +x scripts/<new_script>.sh

# Set up git hooks (one-time, after cloning)
./install-hooks.sh
```

## Code Style Guidelines

### File Structure

Every script in `scripts/` MUST follow this structure:

```bash
#!/bin/bash
# @description Short description here (REQUIRED - line 2)

show_help() {
    # Help text
}

# Variable declarations with defaults
DB_USER=""
DB_HOST="localhost"
DB_PORT="3306"

# Argument parsing loop
while [[ $# -gt 0 ]]; do
    case $1 in
        # options
    esac
done

# Validation
# Main logic
```

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Script files | lowercase, `.sh` extension | `dump.sh`, `restore.sh` |
| Multi-word scripts | hyphens | `schema-diff.sh` |
| Variables | UPPER_SNAKE_CASE | `DB_USER`, `MYSQL_OPTS` |
| Functions | lower_snake_case | `show_help`, `is_table_done` |
| Local variables | lowercase with `local` | `local table="$1"` |

### Standard CLI Options

All database scripts MUST support these options:

| Short | Long | Description | Default |
|-------|------|-------------|---------|
| `-u` | `--user` | Database username | (required) |
| `-p` | `--password` | Database password | (optional) |
| `-h` | `--host` | Database host | localhost |
| `-P` | `--port` | Database port | 3306 |
| `-d` | `--database` | Database name | (required) |
| | `--help` | Show help message | |

Support both formats: `-u root` and `--user=root`

### Argument Parsing Pattern

```bash
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
        # ... more options
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
```

### Password Handling (IMPORTANT)

Handle empty passwords to avoid MySQL "using password: NO" errors:

```bash
# Parsing - skip if next arg is another flag or empty
-p|--password)
    if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
        DB_PASS="$2"
        shift 2
    else
        shift
    fi
    ;;

# Building MySQL options - only add -p if password exists
MYSQL_OPTS="-u $DB_USER -h $DB_HOST -P $DB_PORT"
if [ -n "$DB_PASS" ] && [ "$DB_PASS" != "" ]; then
    MYSQL_OPTS="$MYSQL_OPTS -p$DB_PASS"
fi
```

### Error Handling

- Exit with `exit 1` on errors
- Exit with `exit 0` on success
- Always show help on validation errors
- Use descriptive error messages

```bash
if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
    echo "Error: --user and --database are required"
    echo ""
    show_help
    exit 1
fi
```

### Progress Display

Use `pv` for large file operations:

```bash
pv -s $FILE_SIZE "$SQL_FILE" | mysql $MYSQL_OPTS "$DB_NAME"
```

### Output Messages

- Use `echo` for user feedback
- Progress format: `[$CURRENT/$TOTAL] Action: item`
- Final success: `echo "Action complete! Details"`

## Adding New Tools

1. Create `scripts/<name>.sh`
2. Add `# @description ...` on line 2
3. Run `chmod +x scripts/<name>.sh`
4. Test with `./dbtools.sh <name> --help`
5. Update README.md

## Git Hooks

Hooks are version-controlled in `.githooks/`. Set them up once after cloning:

```bash
./install-hooks.sh
```

| Hook | When | What it checks |
|---|---|---|
| `pre-commit` | On `git commit` | ShellCheck, syntax, shfmt, @description annotation on staged `.sh` files |
| `commit-msg` | On `git commit` | Conventional Commits format (feat/fix/docs/chore/etc.) |
| `pre-push` | On `git push` | Full no-DB test suite (`tests/run-tests.sh`) |

Commit message format: `<type>[scope]: <description>`
Valid types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`, `perf`, `build`, `revert`

To check hook status: `./install-hooks.sh --check`
To uninstall hooks: `./install-hooks.sh --uninstall`

## Files to Ignore

These are generated and should not be committed:
- `*.sql` - Database dump files
- `*.progress` - Resume tracking files

## Dependencies

Required system tools:
- `mysql` / `mysqldump` - MySQL client
- `pv` - Progress display
- `sed` - Text processing
- `bash` 4.0+ - For associative arrays

## Common Pitfalls

1. **Don't use `-p ""` for no password** - Omit `-p` entirely
2. **Always quote variables** - `"$DB_NAME"` not `$DB_NAME`
3. **Use `local` in functions** - Prevent variable leakage
4. **Test with special characters** - Database names with spaces/special chars
5. **Handle missing dependencies** - Check if `pv` exists before using
