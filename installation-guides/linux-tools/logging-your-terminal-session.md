# Logging Your Terminal Session for Reproducible Install Scripts

When installing complex software like network capture tools, SIEMs, or forensic utilities, it's easy to forget exactly what you did — especially when troubleshooting leads you down unexpected paths. This guide covers a simple but powerful bash technique to automatically log every command you run so you can reproduce or script the process later.

---

## The Problem

You sit down, follow a guide, run a dozen commands, hit a few errors, fix them, and eventually get things working. An hour later you ask yourself:

> *"What exactly did I run to get that working?"*

Your bash history is there, but it's mixed with typos, failed attempts, and unrelated commands. There's a better way.

---

## The Solution: Two-Layer Logging

We'll use two complementary tools running side by side:

| Tool | What It Captures |
|---|---|
| `PROMPT_COMMAND` | A clean, timestamped list of every command you typed |
| `script` | The full terminal session including all output |

Together they give you a **clean commands file** to turn into a script, and a **full output file** to reference if something goes wrong during a reinstall.

---

## Setting It Up

Run these commands before you start your installation:

```bash
# Enable timestamps in bash history
export HISTTIMEFORMAT="%F %T "

# Automatically log every command to a dedicated file
export PROMPT_COMMAND='history 1 >> ~/install_commands.txt'

# Start recording the full terminal session including output
script -a ~/install_output.txt
```

That's it. From this point forward, every command you run is captured.

---

## Verifying It Works

Run a quick test:

```bash
echo "logging test"
cat ~/install_commands.txt
```

You should see the `echo` command was captured with a timestamp:

```
  42  2026-03-25 14:32:01 echo "logging test"
```

---

## When You're Done

Stop the `script` session:

```bash
exit
```

You'll have two files in your home directory:

- `~/install_commands.txt` — your clean command list
- `~/install_output.txt` — the full terminal session with all output

---

## Understanding the Commands

### `export`

`export` is a bash built-in that promotes a variable from the current shell into the **environment**, making it available to the current session and any child processes spawned from it.

```bash
# Without export — only visible in current shell
MY_VAR="hello"
bash -c 'echo $MY_VAR'   # prints nothing

# With export — visible to child processes too
export MY_VAR="hello"
bash -c 'echo $MY_VAR'   # prints "hello"
```

Variables set with `export` only last for the current terminal session. If you close the terminal, they're gone. To make a variable permanent, add it to `~/.bashrc`.

There are three scopes to understand:

| Scope | Description |
|---|---|
| **Local** | Exists only in the current shell |
| **Exported (Environment)** | Available to the current shell and all child processes |
| **Persistent** | Written to `~/.bashrc`, survives reboots |

---

### `HISTTIMEFORMAT`

A built-in bash variable that tells bash to record a timestamp alongside each history entry.

```bash
export HISTTIMEFORMAT="%F %T "
```

- `%F` — date formatted as `YYYY-MM-DD`
- `%T` — time formatted as `HH:MM:SS`
- The trailing space is for readability between the timestamp and the command

Without it:
```
42  apt install curl
```

With it:
```
42  2026-03-25 14:32:01 apt install curl
```

---

### `PROMPT_COMMAND`

`PROMPT_COMMAND` is a special bash variable. If it contains a string, bash automatically executes that string as a command **after every command you run**, just before drawing the next prompt.

```
You type a command → Bash runs it → Bash runs PROMPT_COMMAND → Bash draws prompt → repeat
```

In our setup:

```bash
export PROMPT_COMMAND='history 1 >> ~/install_commands.txt'
```

- `history 1` — prints the single most recent history entry
- `>>` — appends to the file without overwriting it
- `~/install_commands.txt` — the destination log file

So after every command you type, bash silently appends it to your log file automatically — no extra effort required.

You can chain multiple commands in `PROMPT_COMMAND` using a semicolon:

```bash
export PROMPT_COMMAND='history 1 >> ~/install_commands.txt; echo "logged"'
```

Or point it at a function for more complex logic:

```bash
log_command() {
    history 1 >> ~/install_commands.txt
}
export PROMPT_COMMAND='log_command'
```

> **Note:** `PROMPT_COMMAND` is related to but distinct from `PS1`, which controls what your prompt *looks like* (the `user@hostname:~$` part). `PROMPT_COMMAND` runs first, then `PS1` is drawn.

---

### `script -a`

The `script` command records everything that appears in your terminal — your commands and all their output — to a file.

```bash
script -a ~/install_output.txt
```

- `-a` — appends to the file rather than overwriting it, useful if you need to stop and resume
- Stop recording with `exit`

If you also want a machine-readable timing file (useful for replaying the session):

```bash
script -a ~/install_output.txt --timing=~/install_timing.txt
```

Replay it later with:

```bash
scriptreplay --timing=~/install_timing.txt ~/install_output.txt
```

---

## Turning the Log Into a Script

Once your installation is complete, open `~/install_commands.txt`, remove any failed attempts or unrelated commands, and wrap it in a bash script:

```bash
#!/bin/bash
set -e  # exit immediately if any command fails

echo "[*] Starting installation..."

# paste your cleaned-up commands here

echo "[*] Installation complete."
```

The `set -e` directive is important — it ensures the script stops immediately if any command fails, rather than continuing and potentially making things worse.

---

## Summary

| Command | Purpose |
|---|---|
| `export HISTTIMEFORMAT="%F %T "` | Adds timestamps to bash history entries |
| `export PROMPT_COMMAND='history 1 >> ~/install_commands.txt'` | Logs every command automatically |
| `script -a ~/install_output.txt` | Records full terminal session with output |
| `exit` | Stops the `script` recording |

This two-layer approach gives you everything you need to reproduce an installation reliably — a clean command list to script from, and a full output log to troubleshoot against.

---

## Script

A ready-to-run script for this guide is available in the scripts directory:

- [`setup-terminal-logging.sh`](../../scripts/linux-tools/setup-terminal-logging.sh)
