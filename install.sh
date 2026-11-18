#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")" && pwd -P)"
config_dir="$HOME/.hammerspoon"
install_deps=1
manage_config=1
action=install

die() { printf '错误：%s\n' "$*" >&2; exit 1; }

while (( $# )); do
    case "$1" in
        --skip-deps) install_deps=0 ;;
        --manual-config) manage_config=0 ;;
        --config-dir)
            (( $# >= 2 )) && [[ -n "$2" ]] || die "--config-dir 需要一个目录"
            config_dir="$2"
            shift ;;
        --uninstall) action=uninstall ;;
        -h|--help)
            echo '用法：bash install.sh [--skip-deps] [--manual-config] [--config-dir DIR] [--uninstall]'
            exit 0 ;;
        *) die "未知选项 $1" ;;
    esac
    shift
done

[[ "$(uname -s)" == Darwin ]] || die "此项目需要 macOS。"
(( EUID != 0 )) || die "请以当前 Mac 用户运行，使用 Homebrew 安装依赖时按系统提示确认。"

mkdir -p -- "$config_dir"
config_dir="$(cd "$config_dir" && pwd -P)"
init="$config_dir/init.lua"
spoon="$config_dir/Spoons/FourFingerGestures.spoon"
lock="$config_dir/.four-finger-gestures-install.lock"
loader='do local ok, err = pcall(function() hs.loadSpoon("FourFingerGestures"):start() end); if not ok then hs.printf("FourFingerGestures: %s", err) end end -- mac-four-finger-gestures'

if [[ -e "$spoon" || -L "$spoon" ]]; then
    [[ ! -L "$spoon" && -d "$spoon" && -f "$spoon/.mac-four-finger-gestures" ]] ||
        die "已有未由此脚本安装的模块 ${spoon}。"
fi
if (( manage_config )); then
    [[ ! -L "$init" && ( ! -e "$init" || -f "$init" ) ]] ||
        die "init.lua 是符号链接或特殊文件。请使用 --manual-config。"
    if [[ "$action" == install && -f "$init" ]]; then
        if grep -Fq 'trackpad-voice.lua' "$init"; then
            die "检测到旧版 trackpad-voice.lua 加载项。请先停用旧加载项并重新运行，避免手势执行两次。"
        fi
        IFS= read -r first < "$init" || true
        if [[ "$first" == '#!'* || "$first" == $'\xef\xbb\xbf'* ]]; then
            die "init.lua 有需要保留的首行。请使用 --manual-config。"
        fi
    fi
fi

mkdir -- "$lock" || die "安装目录正被占用：$lock"
swapped=0
completed=0
cleanup() {
    if (( ! completed )); then
        if (( swapped )); then rm -rf -- "$spoon"; fi
        if [[ -d "$lock/previous" ]]; then
            mv -- "$lock/previous" "$spoon" || return
        fi
    fi
    rm -rf -- "$lock"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

config_changed=0
if (( manage_config )); then
    if [[ -f "$init" ]]; then
        cp -p -- "$init" "$lock/original"
        cp -p -- "$lock/original" "$lock/init.lua"
    fi
    if [[ "$action" == install ]]; then
        if [[ ! -f "$lock/original" ]] || ! grep -Fxq -- "$loader" "$lock/original"; then
            {
                printf '%s\n' "$loader"
                if [[ -f "$lock/original" ]]; then cat -- "$lock/original"; fi
            } > "$lock/init.lua"
            config_changed=1
        fi
    elif [[ -f "$lock/original" ]] && grep -Fxq -- "$loader" "$lock/original"; then
        {
            while IFS= read -r line; do
                if [[ "$line" != "$loader" ]]; then printf '%s\n' "$line"; fi
            done
            if [[ -n "$line" && "$line" != "$loader" ]]; then printf '%s' "$line"; fi
        } < "$lock/original" > "$lock/init.lua"
        config_changed=1
    fi
fi

if [[ "$action" == install ]]; then
    xcrun --find clang >/dev/null 2>&1 || die "请先运行 xcode-select --install，安装命令行工具后重试。"
    if (( install_deps )); then
        missing=()
        if [[ ! -d /Applications/Hammerspoon.app && ! -d "$HOME/Applications/Hammerspoon.app" ]]; then
            missing+=(hammerspoon)
        fi
        if [[ ! -x '/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli' ]]; then
            missing+=(karabiner-elements)
        fi
        # Bash 3.2 with nounset treats expansion of an empty array as unbound.
        if (( ${#missing[@]} )); then
            command -v brew >/dev/null || die "请先安装 Homebrew（https://brew.sh/zh-cn/），或手动安装依赖后用 --skip-deps。"
            brew install --cask "${missing[@]}"
        fi
    fi

    mkdir -- "$lock/new"
    install -m 0644 "$repo/src/init.lua" "$lock/new/init.lua"
    xcrun clang -O2 -Wall -Wextra "$repo/src/trackpad-swipe.c" -framework CoreFoundation -o "$lock/new/trackpad-swipe"
    xcrun clang -O2 -Wall -Wextra "$repo/src/keyboard.c" -framework ApplicationServices -o "$lock/new/keyboard"
    "$lock/new/trackpad-swipe" --self-test
    touch "$lock/new/.mac-four-finger-gestures"
    mkdir -p -- "$config_dir/Spoons"
fi

if (( config_changed )); then
    if [[ -f "$lock/original" ]]; then
        cmp -s -- "$init" "$lock/original" || die "安装过程中 init.lua 已修改，请重试。"
        backup="$(mktemp "$config_dir/init.lua.before-four-finger.XXXXXX")"
        cp -p -- "$lock/original" "$backup"
        printf '已备份 init.lua：%s\n' "$backup"
    elif [[ -e "$init" || -L "$init" ]]; then
        die "安装过程中出现了新的 init.lua，请重试。"
    fi
fi
if [[ -d "$spoon" ]]; then mv -- "$spoon" "$lock/previous"; fi
if [[ "$action" == install ]]; then
    mv -- "$lock/new" "$spoon"
    swapped=1
fi
if (( config_changed )); then mv -f -- "$lock/init.lua" "$init"; fi
completed=1

if [[ "$action" == install ]]; then
    printf '已安装到 %s。\n' "$spoon"
    if (( ! manage_config )); then
        printf '请手动添加到 init.lua：\n%s\n' 'hs.loadSpoon("FourFingerGestures"):start()'
    fi
    printf '可在 %s/four-finger-gestures.lua 自定义快捷键。\n' "$config_dir"
    printf '按 README 完成首次授权，然后从 Hammerspoon 菜单选择 Reload Config。\n'
else
    printf '已卸载手势模块。请从 Hammerspoon 菜单选择 Reload Config。\n'
    if (( ! manage_config )); then echo '请同时移除手动添加的 FourFingerGestures 加载行。'; fi
fi
