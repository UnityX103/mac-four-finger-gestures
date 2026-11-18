# Mac 四指手势

| 手势 | 动作 | 默认快捷键 |
| --- | --- | --- |
| 四指实体压下触控板 | 按住配置的快捷键。触控板弹起后仍保持，最后一根手指离开时释放同一组键。 | 左 Option + 左 Shift + 反引号物理键 |
| 四指轻触后向下滑 | 按一次配置的快捷键。 | Return |

手势和按键处理都在本机进行。你可以绑定任意支持这些快捷键的应用，例如把按住手势交给「按住说话」工具，把下滑手势绑定为聊天应用的发送快捷键。

## 安装

需要带触控板的 Mac 和 Xcode 命令行工具。建议使用 macOS 13 或更新版本，以安装支持触控数据读取的 Karabiner-Elements 15.9 或更新版本。其他版本和设备请以实际测试为准。 [Karabiner-Elements 版本说明](https://karabiner-elements.pqrs.org/docs/releasenotes/)

打开终端。缺少 Xcode 命令行工具时，先运行 `xcode-select --install`。安装完成后运行：

```bash
git clone https://github.com/UnityX103/mac-four-finger-gestures.git
cd mac-four-finger-gestures
bash install.sh
```

也可以[下载 ZIP](https://github.com/UnityX103/mac-four-finger-gestures/archive/refs/heads/main.zip)，解压后在该目录运行 `bash install.sh`。

安装器用 [Homebrew](https://brew.sh/zh-cn/) 安装缺少的 Hammerspoon 和 Karabiner-Elements，在本机编译两个辅助程序，备份已有的 `~/.hammerspoon/init.lua` 并添加模块加载行。已装齐两个应用时可以使用 `bash install.sh --skip-deps`。

1. 打开 **Hammerspoon**，在「系统设置 → 隐私与安全性 → 辅助功能」允许 Hammerspoon。需要登录后自动生效时，在 Hammerspoon 设置中启用登录启动。 [Hammerspoon 官方安装说明](https://www.hammerspoon.org/go/)
2. 打开 **Karabiner-Elements**，按应用提示完成授权。在 Karabiner 菜单或设置的 **Misc** 中启用 **Multitouch Extension**。使用默认触控区域，或者确保四根手指都落在有效区域内。 [触控扩展设置](https://karabiner-elements.pqrs.org/docs/manual/misc/multitouch-extension/) · [Karabiner 官方权限说明](https://karabiner-elements.pqrs.org/docs/manual/misc/required-macos-settings/)
3. 完成快捷键设置后，在 Hammerspoon 菜单选择 **Reload Config**。如果下滑同时打开应用窗口，在「系统设置 → 触控板 → 更多手势」关闭 **App Exposé（应用程序窗口）**。 [Apple 触控板设置说明](https://support.apple.com/zh-cn/guide/mac-help/mchlp1226/mac)

## 自定义快捷键

新建 `~/.hammerspoon/four-finger-gestures.lua`，填入你的目标应用所用的快捷键，然后重载 Hammerspoon。下面的例子把四指压下设为 **F8**，把四指下滑设为 **Command + Return**：

```lua
return {
    hold = { key = "f8" },
    swipeDown = { key = "return", modifiers = {"cmd"} },
}
```

- `hold` 配置一组键。四指压下时按下它，所有手指离开时释放它。
- `swipeDown` 配置下滑时按一次的键。省略某项时使用表格中的默认快捷键。
- `key` 支持 `"space"`、`"return"`、`"f8"` 等 Hammerspoon 按键名或 macOS 物理键码。只用修饰键时可以省略 `key`，例如 `hold = { modifiers = {"rightOption"} }`。 [Hammerspoon 按键名和键码](https://www.hammerspoon.org/docs/hs.keycodes.html)
- `modifiers` 支持 `cmd`、`ctrl`、`alt`、`shift`，默认发送左侧键。可用 `leftCommand`、`leftControl`、`leftOption`、`leftShift` 或对应的 `right...` 名称指定左右侧。

已手动管理 Hammerspoon 配置时，可用 `bash install.sh --manual-config` 安装模块，再把以下内容加入 `init.lua`。显式传入的配置优先于独立配置文件。对于符号链接的 `init.lua` 也可使用此方式。自定义 Hammerspoon 配置目录时，安装命令加上 `--config-dir "/你的配置目录"`。

```lua
hs.loadSpoon("FourFingerGestures"):start({
    hold = { key = "space", modifiers = {"ctrl", "shift"} },
    swipeDown = { key = "return" },
})
```

### 微信输入法示例

如果选用微信输入法，把「按住说话」设为 **左 Option + 左 Shift + 反引号物理键**，即可使用默认配置。最后一键在数字 1 左边，某些键盘布局会显示为 **·**。按应用提示添加输入源和授予麦克风权限。 [微信输入法](https://z.weixin.qq.com/)

## 验证和排查

- 先用物理键盘测试目标应用的快捷键，再四指压下，逐根抬起直到只剩一指，观察应用是否在最后一指离开时停止。
- 下滑如果设为默认的 Return，可以先在文本编辑器里验证是否只换一行。要在聊天应用中发送，使用该应用实际配置的发送快捷键。
- 在 Hammerspoon Console 运行 `hs.inspect(spoon.FourFingerGestures:status())`。如果 `fingerReader` 为 `false`，检查 Karabiner 的触控扩展。如果 `swipeReader` 为 `false`，确认有可用的触控板。下滑监听使用 macOS 私有 MultitouchSupport 框架，系统升级可能影响兼容性。

## 更新和卸载

下载新版或运行 `git pull` 后，重新执行 `bash install.sh`，然后重载 Hammerspoon。

```bash
bash install.sh --uninstall
```

卸载会移除手势模块和安装器添加的加载行，保留独立快捷键配置文件。如果使用 `--manual-config` 安装，请同时删除自己添加的加载行。

## 开发验证

```bash
bash tests/check-install.sh
lua tests/controller.lua src/init.lua
```

安装测试在临时目录编译并运行。状态机回归需要 Lua。原生触控结构参考 [MiddleClick 的 MultitouchSupport 声明](https://github.com/artginzburg/MiddleClick/blob/main/MoreTouch/Sources/MultitouchSupport/MultitouchSupport.h)。
