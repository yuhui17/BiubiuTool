# Biubiu小工具

基于 [AutoHotkey v2](https://www.autohotkey.com/) + [AutoHotInterception](https://github.com/evilC/AutoHotInterception) 的游戏辅助小工具。所有输入都通过 [Interception](https://github.com/oblitum/Interception) 驱动发送，模拟的是硬件输入。

包含两个工具：

## Biubiu小工具（按键 / 鼠标连点）

- 14 个按键行：每行一个按键（支持 `ctrl+a` 这类组合键），各自按自己的间隔循环触发
- 4 个鼠标行：左键 / 右键 / 中键，可指定坐标（留空 = 在当前位置点击）
- 每行可设置间隔和随机浮动，键盘和鼠标同时运行、互不等待
- 点击按键框后直接按下要用的键即可录入（Esc 取消）
- 开始 / 停止热键可自定义（默认 F7 / F8），鼠标坐标点「取点」后按 F9 记录
- 设置保存在程序旁边的 `Biubiu小工具.ini`

## Biubiu强化小工具（自动强化 / 自动贩卖背包装备）

背包 8×8 共 64 格，只需取第 1 格和第 64 格的坐标，其余格子自动按等距算出。强化和贩卖各有一组格子坐标和页面按钮（ITEM 1 / ITEM 2）坐标，「检查」可在屏幕上标出所有坐标确认。

**自动强化（默认 F7）**

- 水晶、红宝石放在哪一格可以设置（默认第 63、64 格），其余格子是要强化的装备
- 逐格检查第 1～64 格：「空格子」（没有道具）直接跳过；有道具就
  右键装备 → 右键水晶 → 确认强化 → 右键红宝 → 确认强化 → OK → 确认强化，
  然后在侦测位置等待「GEM」或「空」图片出现：GEM 会从图片中心往上拖走，空则直接换下一格

**自动贩卖（默认 F6）**

- 逐格检查第 1～64 格：本来就是「空格子」的跳过；有东西就右键 → 确认贩卖，等格子变成空格子再换下一格

**共用设置**

- 依次处理 ITEM 1、ITEM 2 页（可勾选），水晶 / 红宝所在的两格不强化也不贩卖
- 可设置从第几格开始、每步间隔、水晶 / 红宝位置、拖拽距离、找图容差
- 「GEM」「空」「空格子」三张侦测图片需要自己在游戏里用「截图」按钮框选，保存在程序旁边的 `images/`
- 开始强化 / 开始贩卖 / 停止 热键可自定义（默认 F7 / F6 / F8）
- 设置保存在程序旁边的 `Biubiu强化小工具.ini`

## 直接使用

1. 下载 `dist` 文件夹里的 exe
2. 运行 `驱动安装.exe` → 点「安装驱动」→ 重启电脑
   （也可以直接运行工具，检测不到驱动时会提示安装）
3. 运行 `Biubiu小工具.exe` 或 `Biubiu强化小工具.exe`

要求：64 位 Windows 10 / 11，需要管理员权限（启动时会弹出 UAC 确认）。

> 部分网络游戏的反作弊会检测 Interception 驱动，使用前请自行确认游戏规则。

## 文件说明

| 路径 | 说明 |
|---|---|
| `Biubiu小工具.ahk` | 按键 / 鼠标连点工具源码 |
| `Biubiu强化小工具.ahk` | 自动强化工具源码 |
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
Ahk2Exe.exe /in "Biubiu强化小工具.ahk" /out "dist\Biubiu强化小工具.exe" /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
Ahk2Exe.exe /in "驱动安装.ahk" /out "dist\驱动安装.exe" /base "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
```

图标、版本信息、管理员权限等编译选项都写在脚本开头的 `;@Ahk2Exe-` 指令里。

## 第三方组件

- [AutoHotInterception](https://github.com/evilC/AutoHotInterception) — MIT License，见 `licenses/AutoHotInterception-MIT.txt`
- [Interception](https://github.com/oblitum/Interception) — 非商业用途使用 LGPL-3.0，见 `licenses/Interception-LGPL-3.0.txt`；商业用途需另行向作者取得授权
