# Biubiu小工具

基于 [AutoHotkey v2](https://www.autohotkey.com/) + [AutoHotInterception](https://github.com/evilC/AutoHotInterception) 的按键 / 鼠标连点工具。所有输入都通过 [Interception](https://github.com/oblitum/Interception) 驱动发送，模拟的是硬件输入。

## 功能

- 14 个按键行：每行一个按键（支持 `ctrl+a` 这类组合键），各自按自己的间隔循环触发
- 4 个鼠标行：左键 / 右键 / 中键，可指定坐标（留空 = 在当前位置点击）
- 每行可设置间隔和随机浮动，键盘和鼠标同时运行、互不等待
- 点击按键框后直接按下要用的键即可录入（Esc 取消）
- 开始 / 停止热键可自定义（默认 F7 / F8），鼠标坐标点「取点」后按 F9 记录
- 设置保存在程序旁边的 `Biubiu小工具.ini`

## 直接使用

1. 下载 `dist` 文件夹里的两个 exe
2. 运行 `驱动安装.exe` → 点「安装驱动」→ 重启电脑
   （也可以直接运行 `Biubiu小工具.exe`，检测不到驱动时会提示安装）
3. 运行 `Biubiu小工具.exe`

要求：64 位 Windows 10 / 11，需要管理员权限（启动时会弹出 UAC 确认）。

> 部分网络游戏的反作弊会检测 Interception 驱动，使用前请自行确认游戏规则。

## 文件说明

| 路径 | 说明 |
|---|---|
| `Biubiu小工具.ahk` | 主程序源码 |
| `驱动安装.ahk` | 驱动安装 / 卸载工具源码 |
| `Lib/` | AutoHotInterception 库、`interception.dll`、驱动安装程序 `install-interception.exe` |
| `icon.png` / `icon.ico` | 程序图标 |
| `dist/` | 编译好的 exe |

## 从源码运行 / 编译

1. 安装 [AutoHotkey v2](https://www.autohotkey.com/) 和 Interception 驱动（见上）
2. 直接双击 `.ahk` 即可运行
3. 编译成 exe（需要 [Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe)）：

```powershell
Ahk2Exe.exe /in "Biubiu小工具.ahk" /out "dist\Biubiu小工具.exe" /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
Ahk2Exe.exe /in "驱动安装.ahk" /out "dist\驱动安装.exe" /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
```

图标、版本信息、管理员权限等编译选项都写在脚本开头的 `;@Ahk2Exe-` 指令里。

## 第三方组件

- [AutoHotInterception](https://github.com/evilC/AutoHotInterception) — MIT License，见 `licenses/AutoHotInterception-MIT.txt`
- [Interception](https://github.com/oblitum/Interception) — 非商业用途使用 LGPL-3.0，见 `licenses/Interception-LGPL-3.0.txt`；商业用途需另行向作者取得授权
