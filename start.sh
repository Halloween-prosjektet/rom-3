#!/bin/sh
# Starts the game on the Pi (fullscreen). Started at login from ~/.config/labwc/autostart.
# Pi paths override the Mac paths in .env (environment variables win over .env).
cd "$(dirname "$0")"
export WHISPER_SERVER="$HOME/whisper.cpp/build/bin/whisper-server"
export WHISPER_MODEL="$PWD/models/nb-whisper-base-q5_0.bin"
export PIPER_PYTHON="$PWD/.venv/bin/python"
exec "$HOME/godot/Godot_v4.7.2-stable_linux.arm64" --path . --fullscreen
