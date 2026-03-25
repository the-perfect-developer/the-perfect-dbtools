# .githooks/

Git hooks for dbtools development. These are **version-controlled** and shared
across all contributors via `git config core.hooksPath .githooks`.

## Setup

```bash
./install-hooks.sh
```

One command. No Node.js. No Python. No dependencies beyond bash.

## Hooks

| Hook | Triggers on | What it checks |
|---|---|---|
| `pre-commit` | `git commit` | ShellCheck (error severity), bash -n syntax, shfmt format, @description annotation |
| `commit-msg` | `git commit` | Conventional Commits format enforcement |
| `pre-push` | `git push` | Full no-DB test suite (`tests/run-tests.sh`) |

## Bypassing Hooks (Emergency Only)

```bash
git commit --no-verify   # Skip pre-commit + commit-msg
git push --no-verify     # Skip pre-push
```

Do not make bypassing a habit. If a check is wrong, fix the check.

## Optional Tools

Hooks degrade gracefully when optional tools are missing:

| Tool | If absent |
|---|---|
| `shellcheck` | ShellCheck check is **skipped with a warning** (not blocked) |
| `shfmt` | Format check is **skipped with a warning** (not blocked) |
| `bash` | Always required |

```bash
# Install shellcheck
sudo apt install shellcheck      # Debian/Ubuntu
brew install shellcheck          # macOS

# Install shfmt
brew install shfmt               # macOS
go install mvdan.cc/sh/v3/cmd/shfmt@latest  # via Go
```

## Check Status

```bash
./install-hooks.sh --check
```