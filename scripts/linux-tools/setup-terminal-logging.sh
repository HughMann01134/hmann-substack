#!/bin/bash
set -e

echo "[*] Setting up terminal session logging..."

# Enable timestamps in bash history
export HISTTIMEFORMAT="%F %T "

# Automatically log every command to a dedicated file
export PROMPT_COMMAND='history 1 >> ~/install_commands.txt'

echo "[*] HISTTIMEFORMAT and PROMPT_COMMAND set."

# Start recording the full terminal session including output
echo "[*] Starting terminal session recording..."
echo "[*] When you are done, type 'exit' to stop recording."
echo "[*] Your logs will be saved to:"
echo "      ~/install_commands.txt  — clean command list"
echo "      ~/install_output.txt    — full terminal session output"
echo ""

script -a ~/install_output.txt

echo "[*] Session recording stopped."
echo "[*] Logs saved to ~/install_commands.txt and ~/install_output.txt"
