#!/bin/bash
set -e

# Install mpv using Homebrew if it is not already available.
if ! command -v mpv >/dev/null 2>&1; then
    brew install mpv
fi

# Accept a directory argument, or use the default photo collection.
directory="${1:-$HOME/Pictures/2019-2026-fotoksiazka-plus-4-and-more-stars}"

options=(
    --fs                        # Start in fullscreen mode.
    --loop-playlist=inf          # Repeat the entire playlist indefinitely.
    --image-display-duration=5  # Display each still picture for five seconds.
    --directory-mode=recursive  # Include media from subdirectories recursively.
    --osd-level=1                # Enable basic on-screen status messages.
    '--osd-msg1=${filename}'     # Show the current filename in the on-screen display.
)

exec mpv "${options[@]}" "$directory"
