#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
config="$scratch/Hammerspoon config"
spoon="$config/Spoons/FourFingerGestures.spoon"
mkdir -p -- "$config"

# Include a return and an unterminated last line to catch unsafe append or rewrite.
printf '%s\n%s' 'local existing = 42' 'return existing' > "$scratch/original.lua"
cp -- "$scratch/original.lua" "$config/init.lua"
chmod 640 "$config/init.lua"
bash "$repo/install.sh" --skip-deps --config-dir "$config"
test -x "$spoon/keyboard"
test -x "$spoon/trackpad-swipe"
"$spoon/keyboard" --check 49 leftControl rightShift
"$spoon/keyboard" --check - rightOption
if "$spoon/keyboard" --check 49 invalidModifier 2>/dev/null; then exit 1; fi
if "$spoon/keyboard" --check - 2>/dev/null; then exit 1; fi
printf '%s\n' 'return {hold = {key = "f8"}}' > "$config/four-finger-gestures.lua"
test "$(stat -f %Lp "$config/init.lua")" = 640
tail -n +2 "$config/init.lua" | cmp -s - "$scratch/original.lua"
cp -- "$config/init.lua" "$scratch/installed.lua"
bash "$repo/install.sh" --skip-deps --config-dir "$config"
cmp -s "$config/init.lua" "$scratch/installed.lua"

bash "$repo/install.sh" --uninstall --config-dir "$config"
cmp -s "$config/init.lua" "$scratch/original.lua"
test ! -e "$spoon"
test "$(cat "$config/four-finger-gestures.lua")" = 'return {hold = {key = "f8"}}'
test "$(stat -f %Lp "$config/init.lua")" = 640

# Unmanaged destinations and symlinked init files should be preserved.
mkdir -p -- "$spoon"
touch "$spoon/user-file"
if bash "$repo/install.sh" --skip-deps --config-dir "$config"; then exit 1; fi
if bash "$repo/install.sh" --uninstall --config-dir "$config"; then exit 1; fi
test -f "$spoon/user-file"

symlink_config="$scratch/Dotfiles"
mkdir -- "$symlink_config"
ln -s "$scratch/original.lua" "$symlink_config/init.lua"
if bash "$repo/install.sh" --skip-deps --config-dir "$symlink_config"; then exit 1; fi
bash "$repo/install.sh" --skip-deps --manual-config --config-dir "$symlink_config"
test -L "$symlink_config/init.lua"
cmp -s "$symlink_config/init.lua" "$scratch/original.lua"
bash "$repo/install.sh" --uninstall --manual-config --config-dir "$symlink_config"

echo 'PASS: clean build, idempotent install, exact config restoration and unmanaged path protection.'
