#!/bin/bash

set -u

if ! command -v dialog >/dev/null 2>&1; then
  echo "dialog not found in PATH" >&2
  exit 1
fi

message="Green samples (dialog --colors):\n"
message="${message}\\Z2green (\\Z2)\\Z0\n"
message="${message}\\Zb\\Z2bold green (\\Zb\\Z2)\\Z0\n"
message="${message}\\Zu\\Z2underline green (\\Zu\\Z2)\\Z0\n"
message="${message}\\Zr\\Z2reverse green (\\Zr\\Z2)\\Z0\n"
message="${message}\\Zb\\Zu\\Z2bold+underline green (\\Zb\\Zu\\Z2)\\Z0\n"
message="${message}\\Zb\\Zr\\Z2bold+reverse green (\\Zb\\Zr\\Z2)\\Z0\n"

dialog --colors --title "Dialog Green Samples" --msgbox "$message" 14 60
