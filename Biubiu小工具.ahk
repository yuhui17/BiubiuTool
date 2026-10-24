/*
Biubiu小工具 (基于 AutoHotInterception)
- 每一行是一个独立的按键/鼠标点击, 按自己的间隔循环触发
- 勾选 "浮动间隔" 后, 每次间隔会额外随机加 0~浮动 ms
- 鼠标行 X/Y 留空 = 在当前位置点击; 点 "取点" 后把鼠标移到目标按 F9 记录坐标
- 所有输入都通过 Interception 驱动发送 (模拟硬件输入)
*/
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; 编译成 exe 时的设置 (Ahk2Exe)
;@Ahk2Exe-SetMainIcon icon.ico
;@Ahk2Exe-SetName Biubiu小工具
;@Ahk2Exe-SetDescription Biubiu小工具
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-UpdateManifest 1

; 以管理员身份运行, 否则在以管理员运行的游戏窗口里热键可能无效
if !A_IsAdmin {
	try {
		if A_IsCompiled
			Run('*RunAs "' A_ScriptFullPath '" /restart')
		else
			Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
		ExitApp
	}
}

#include Lib\AutoHotInterception.ahk

SetWorkingDir A_ScriptDir
IconFile := A_ScriptDir "\icon.png"
if A_IsCompiled {
	; exe 运行时把图标释放到 Lib 文件夹 (AHI 也会把它需要的 dll 释放到这里)
	DirCreate("Lib")
	FileInstall("icon.png", "Lib\icon.png", 1)
	IconFile := A_ScriptDir "\Lib\icon.png"
}
if FileExist(IconFile)
	TraySetIcon(IconFile) ; 托盘图标, 之后创建的窗口也会用它
CoordMode "Mouse", "Screen"
DllCall("winmm\timeBeginPeriod", "UInt", 1) ; 让间隔精确到 1ms 左右

AHI := AutoHotInterception()
CfgFile := A_ScriptDir "\Biubiu小工具.ini"
KEY_ROWS := 14
MOUSE_ROWS := 4
HOLD_MS := 30 ; 每次按下到松开的时间
BtnNames := ["左键", "右键", "中键"] ; AHI 鼠标按键代码 0 / 1 / 2
DefaultKeys := ["1", "2", "3", "4", "5", "6", "7", "F1", "F2", "F3", "F4", "F5", "F6", "F7"]

Running := false
MouseBusy := false ; 鼠标正在移动/按下中, 其他鼠标动作要等它完成
Jobs := []
PickRow := 0
StartKey := ""
StopKey := ""

; 使用第一个键盘 / 鼠标设备发送输入
KbId := 0
MouseId := 0
for id, dev in AHI.GetDeviceList() {
	if (dev.IsMouse && !MouseId)
		MouseId := id
	else if (!dev.IsMouse && !KbId)
		KbId := id
}
if (!KbId || !MouseId) {
	CheckDriver()
	ExitApp
}

; ---------------- 界面 ----------------
g := Gui(, "Biubiu小工具")
g.SetFont("s10", "Microsoft YaHei UI")
g.OnEvent("Close", (*) => ExitApp())

; 标题栏: 图标 + 名称
TOP := 58 ; 标题栏高度, 下面所有控件整体下移这么多
if FileExist(IconFile)
	g.Add("Picture", "x15 y8 w42 h42", IconFile)
g.SetFont("s16 Bold c303030")
g.Add("Text", "x66 y12", "Biubiu小工具")
g.SetFont("s10 Norm cDefault")
g.Add("Text", "x15 y" TOP - 4 " w590 h1 0x10") ; 分隔线

; 按钮先创建, 让窗口打开时焦点落在按钮上, 而不是按键框 (按键框一获得焦点就会开始录键)
btnSave := g.Add("Button", "x232 y" TOP + 11 " w80 h30", "保存设置")
btnSave.OnEvent("Click", SaveConfig)
g.Add("Button", "x322 y" TOP + 11 " w80 h30", "读取配置").OnEvent("Click", LoadConfig)
chkJitter := g.Add("CheckBox", "x420 y" TOP + 16 " Checked", "浮动间隔")
g.Add("Text", "x20 y" TOP + 17, "开始")
edStart := g.Add("Edit", "x56 y" TOP + 13 " w60 Center ReadOnly", "F7")
g.Add("Text", "x126 y" TOP + 17, "停止")
edStop := g.Add("Edit", "x162 y" TOP + 13 " w60 Center ReadOnly", "F8")
edStart.OnEvent("Focus", CaptureKey.Bind(edStart, btnSave))
edStop.OnEvent("Focus", CaptureKey.Bind(edStop, btnSave))

; 按键 (两列, 每列 7 行)
for col in [0, 300] {
	g.Add("Text", Format("x{} y{} w80 Center", 95 + col, TOP + 52), "按键")
	g.Add("Text", Format("x{} y{} w55 Center", 183 + col, TOP + 52), "间隔")
	g.Add("Text", Format("x{} y{} w55 Center", 246 + col, TOP + 52), "浮动")
}
KeyRows := []
Loop KEY_ROWS {
	col := A_Index <= 7 ? 0 : 300
	y := TOP + 76 + Mod(A_Index - 1, 7) * 32
	KeyRows.Push(r := {
		chk: g.Add("CheckBox", Format("x{} y{} w80", 15 + col, y + 3), "_按键" A_Index),
		key: g.Add("Edit", Format("x{} y{} w80 Center ReadOnly", 95 + col, y), DefaultKeys[A_Index]),
		int: g.Add("Edit", Format("x{} y{} w55 Center Number cBlue", 183 + col, y), 300),
		jit: g.Add("Edit", Format("x{} y{} w55 Center Number cBlue", 246 + col, y), 15)
	})
	r.key.OnEvent("Focus", CaptureKey.Bind(r.key, r.chk))
}

; 鼠标点击
g.Add("Text", "x15 y" TOP + 308 " w590 h1 0x10") ; 分隔线
g.Add("Text", "x95 y" TOP + 318 " w80 Center", "鼠标")
g.Add("Text", "x183 y" TOP + 318 " w55 Center", "X")
g.Add("Text", "x246 y" TOP + 318 " w55 Center", "Y")
g.Add("Text", "x309 y" TOP + 318 " w55 Center", "间隔")
g.Add("Text", "x372 y" TOP + 318 " w55 Center", "浮动")
MouseRows := []
Loop MOUSE_ROWS {
	y := TOP + 342 + (A_Index - 1) * 32
	MouseRows.Push({
		chk: g.Add("CheckBox", Format("x15 y{} w80", y + 3), "_鼠标" A_Index),
		btn: g.Add("DropDownList", Format("x95 y{} w80 Choose1", y), BtnNames),
		x: g.Add("Edit", Format("x183 y{} w55 Center", y)),
		y: g.Add("Edit", Format("x246 y{} w55 Center", y)),
		int: g.Add("Edit", Format("x309 y{} w55 Center Number cBlue", y), 1000),
		jit: g.Add("Edit", Format("x372 y{} w55 Center Number cBlue", y), 15)
	})
	g.Add("Button", Format("x435 y{} w60 h27", y), "取点").OnEvent("Click", StartPick.Bind(A_Index))
}

txtStatus := g.Add("Text", "x15 y" TOP + 478 " w590 cGray")

LoadConfig()
ApplyHotkeys()
SetStatus("")
g.Show("w615 h" TOP + 505)
return

; ---------------- 运行 ----------------
StartMacro(*) {
	global Running, Jobs
	if Running
		return
	errs := ""
	newJobs := []
	for i, r in KeyRows {
		if !r.chk.Value
			continue
		try codes := ParseKeys(r.key.Value)
		catch as e {
			errs .= "_按键" i ": " e.Message "`n"
			continue
		}
		newJobs.Push({mouse: false, codes: codes, int: Max(ToInt(r.int.Value), 10), jit: ToInt(r.jit.Value)})
	}
	for i, r in MouseRows {
		if !r.chk.Value
			continue
		xs := Trim(r.x.Value), ys := Trim(r.y.Value)
		hasPos := (xs != "" || ys != "")
		if (hasPos && !(IsInteger(xs) && IsInteger(ys))) {
			errs .= "_鼠标" i ": X / Y 要么都填整数, 要么都留空`n"
			continue
		}
		newJobs.Push({mouse: true, btn: r.btn.Value - 1, hasPos: hasPos, x: ToInt(xs), y: ToInt(ys)
			, int: Max(ToInt(r.int.Value), 10), jit: ToInt(r.jit.Value)})
	}
	if (errs != "") {
		MsgBox(errs, "Biubiu小工具", "Icon!")
		return
	}
	if !newJobs.Length {
		MsgBox("请至少勾选一个按键或鼠标", "Biubiu小工具")
		return
	}
	Jobs := newJobs
	Running := true
	for job in Jobs {
		job.fn := RunJob.Bind(job)
		SetTimer(job.fn, -1) ; 立即执行第一次
	}
	SetStatus("运行中…   按 " StopKey " 停止")
}

StopMacro(*) {
	global Running
	if !Running
		return
	Running := false
	for job in Jobs
		SetTimer(job.fn, 0)
	SetStatus("已停止")
}

ToggleMacro(*) {
	if Running
		StopMacro()
	else
		StartMacro()
}

; 按下后不在这里等待, 松开交给一次性定时器, 这样键盘和鼠标动作可以同时进行
RunJob(job) {
	global MouseBusy
	if !Running
		return
	hold := Min(HOLD_MS, job.int // 2) ; 间隔很短时缩短按住时间, 避免还没松开就又按下
	if job.mouse {
		; 光标只有一个: 上一个鼠标动作还没松开时稍后再试
		if MouseBusy {
			SetTimer(job.fn, -5)
			return
		}
		MouseBusy := true
		if job.hasPos
			MoveTo(job.x, job.y)
		AHI.SendMouseButtonEvent(MouseId, job.btn, 1)
		SetTimer(MouseRelease.Bind(job.btn), -hold)
	} else {
		for sc in job.codes
			AHI.SendKeyEvent(KbId, sc, 1)
		SetTimer(KeyRelease.Bind(job.codes), -hold)
	}
	if Running
		SetTimer(job.fn, -(job.int + (chkJitter.Value && job.jit > 0 ? Random(0, job.jit) : 0)))
}

MouseRelease(btn) {
	global MouseBusy
	AHI.SendMouseButtonEvent(MouseId, btn, 0)
	MouseBusy := false
}

; 松开顺序与按下相反 (先松 a 再松 ctrl)
KeyRelease(codes) {
	Loop codes.Length
		AHI.SendKeyEvent(KbId, codes[codes.Length - A_Index + 1], 0)
}

; 用 Interception 相对移动把鼠标移到屏幕坐标 (x, y)
; 远距离每次走剩余距离的一半, 避免系统鼠标加速造成来回过冲; 最后逐像素修正
MoveTo(x, y) {
	Loop 60 {
		MouseGetPos(&cx, &cy)
		dx := x - cx, dy := y - cy
		if (dx = 0 && dy = 0)
			return
		mx := Abs(dx) > 2 ? Round(dx / 2) : (dx > 0) - (dx < 0)
		my := Abs(dy) > 2 ? Round(dy / 2) : (dy > 0) - (dy < 0)
		AHI.SendMouseMove(MouseId, mx, my)
		Sleep 2
	}
	Sleep 20
}

; "ctrl+a" -> [ctrl 扫描码, a 扫描码]; 扩展键 (方向键等) GetKeySC 已带 0x100, 正好是 AHI 的格式
ParseKeys(str) {
	codes := []
	for name in StrSplit(str, "+", " `t") {
		if (name = "")
			continue
		if (name = "win")
			name := "LWin"
		sc := GetKeySC(name)
		if !sc
			throw ValueError("无法识别的按键 " name)
		codes.Push(sc)
	}
	if !codes.Length
		throw ValueError("按键为空")
	return codes
}

ToInt(v) => IsInteger(Trim(v)) ? Integer(Trim(v)) : 0

; ---------------- 录键 ----------------
; 按键框获得焦点后, 读取下一次按下的键 (支持 ctrl/alt/shift/win 组合); Esc 取消, 10 秒无操作自动取消
CaptureKey(ctrl, nextFocus, *) {
	static busy := false
	if busy
		return
	busy := true
	old := ctrl.Value
	ctrl.Value := "请按键…"
	held := Map()
	st := {lone: ""}
	mods := "{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}"
	ih := InputHook("L0 T10")
	ih.KeyOpt("{All}", "E")
	ih.KeyOpt(mods, "-E")
	ih.KeyOpt(mods, "N")
	ih.OnKeyDown := (ih, vk, sc) => held[ModName(vk, sc)] := true
	ih.OnKeyUp := ModUp
	Suspend true ; 录键期间暂停开始/停止热键
	ih.Start()
	ih.Wait()
	Suspend false

	result := old
	if (ih.EndReason = "EndKey" && ih.EndKey != "Escape") {
		key := ih.EndKey
		if (StrLen(key) = 1)
			key := StrUpper(key)
		result := ""
		for m in ["ctrl", "alt", "shift", "win"]
			if held.Has(m)
				result .= m "+"
		result .= key
	} else if (st.lone != "") {
		result := st.lone ; 只按了一个修饰键
	}
	ctrl.Value := result
	nextFocus.Focus() ; 移走焦点, 下次点击才能再次录键
	busy := false
	ApplyHotkeys()

	ModUp(ih, vk, sc) {
		st.lone := ModName(vk, sc)
		ih.Stop()
	}
}

ModName(vk, sc) {
	n := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
	return InStr(n, "Control") ? "ctrl" : InStr(n, "Alt") ? "alt" : InStr(n, "Shift") ? "shift" : "win"
}

; "ctrl+F7" -> "^F7" (AHK 热键写法)
ToHotkey(str) {
	static prefix := Map("ctrl", "^", "alt", "!", "shift", "+", "win", "#")
	parts := StrSplit(str, "+")
	if (parts.Length = 1)
		return str = "win" ? "LWin" : str
	key := parts.Pop()
	out := ""
	for m in parts
		out .= prefix.Has(m) ? prefix[m] : ""
	return out key
}

; ---------------- 热键 / 取点 ----------------
ApplyHotkeys() {
	global StartKey, StopKey
	s := Trim(edStart.Value), t := Trim(edStop.Value)
	if (s = StartKey && t = StopKey)
		return
	for k in [StartKey, StopKey]
		if (k != "")
			try Hotkey(ToHotkey(k), "Off")
	try {
		if (s = t) {
			Hotkey(ToHotkey(s), ToggleMacro, "On")
		} else {
			Hotkey(ToHotkey(s), StartMacro, "On")
			Hotkey(ToHotkey(t), StopMacro, "On")
		}
	} catch as e {
		MsgBox("热键设置无效: " e.Message, "Biubiu小工具", "Icon!")
	}
	StartKey := s, StopKey := t
	if !Running
		SetStatus("")
}

StartPick(i, *) {
	global PickRow := i
	Hotkey("F9", DoPick, "On")
	SetStatus("把鼠标移到目标位置, 按 F9 记录 _鼠标" i " 的坐标")
}

DoPick(*) {
	global PickRow
	Hotkey("F9", "Off")
	if !PickRow
		return
	MouseGetPos(&x, &y)
	MouseRows[PickRow].x.Value := x
	MouseRows[PickRow].y.Value := y
	SetStatus("_鼠标" PickRow " 坐标已设为 " x ", " y)
	PickRow := 0
}

SetStatus(text) {
	if (text = "")
		text := "点击按键框后按下要用的键。按 " StartKey " 开始 / " StopKey " 停止。鼠标 X/Y 留空 = 原地点击"
	txtStatus.Value := text
}

; ---------------- 配置 ----------------
SaveConfig(*) {
	ApplyHotkeys()
	IniWrite(edStart.Value, CfgFile, "Main", "Start")
	IniWrite(edStop.Value, CfgFile, "Main", "Stop")
	IniWrite(chkJitter.Value, CfgFile, "Main", "Jitter")
	for i, r in KeyRows
		IniWrite(Format("{}|{}|{}|{}", r.chk.Value, r.key.Value, r.int.Value, r.jit.Value), CfgFile, "Keys", i)
	for i, r in MouseRows
		IniWrite(Format("{}|{}|{}|{}|{}|{}", r.chk.Value, r.btn.Value, r.x.Value, r.y.Value, r.int.Value, r.jit.Value), CfgFile, "Mouse", i)
	SetStatus("设置已保存")
}

LoadConfig(ctrl := 0, *) {
	if !FileExist(CfgFile) {
		if ctrl
			MsgBox("还没有保存过设置", "Biubiu小工具")
		return
	}
	edStart.Value := IniRead(CfgFile, "Main", "Start", "F7")
	edStop.Value := IniRead(CfgFile, "Main", "Stop", "F8")
	chkJitter.Value := ToInt(IniRead(CfgFile, "Main", "Jitter", 1))
	for i, r in KeyRows {
		f := StrSplit(IniRead(CfgFile, "Keys", i, ""), "|")
		if (f.Length = 4)
			r.chk.Value := ToInt(f[1]), r.key.Value := f[2], r.int.Value := f[3], r.jit.Value := f[4]
	}
	for i, r in MouseRows {
		f := StrSplit(IniRead(CfgFile, "Mouse", i, ""), "|")
		if (f.Length = 6)
			r.chk.Value := ToInt(f[1]), r.btn.Value := Max(ToInt(f[2]), 1), r.x.Value := f[3], r.y.Value := f[4], r.int.Value := f[5], r.jit.Value := f[6]
	}
	if ctrl {
		ApplyHotkeys()
		SetStatus("已读取配置")
	}
}

; ---------------- 驱动 ----------------
; 检测不到设备时调用: 驱动没装 -> 询问安装; 装了但没生效 -> 提示重启
CheckDriver() {
	title := "Biubiu小工具"
	if DriverInstalled() {
		if (MsgBox("Interception 驱动已经安装, 但还没有生效。`n需要重启电脑后才能使用, 现在重启吗?", title, "YesNo Icon!") = "Yes")
			Shutdown 2
		return
	}
	if (MsgBox("没有检测到 Interception 驱动 (本工具需要它来模拟键盘鼠标)。`n`n现在安装吗? 安装后需要重启电脑。", title, "YesNo Icon?") != "Yes")
		return

	installer := A_ScriptDir "\Lib\install-interception.exe"
	if A_IsCompiled {
		DirCreate("Lib")
		FileInstall("Lib\install-interception.exe", "Lib\install-interception.exe", 1)
	}
	if !FileExist(installer) {
		MsgBox("找不到驱动安装程序: " installer, title, "Icon!")
		return
	}
	try RunWait('"' installer '" /install', A_ScriptDir "\Lib", "Hide")
	catch as e {
		MsgBox("驱动安装失败: " e.Message, title, "Icon!")
		return
	}
	if !DriverInstalled() {
		MsgBox("驱动安装失败。`n请右键以管理员身份运行本程序后再试。", title, "Icon!")
		return
	}
	if (MsgBox("驱动安装完成! 需要重启电脑后才能使用。`n现在重启吗?", title, "YesNo Iconi") = "Yes")
		Shutdown 2
}

; Interception 安装后会在键盘/鼠标设备类的 UpperFilters 里注册 keyboard / mouse 过滤驱动
DriverInstalled() {
	static cls := "HKLM\SYSTEM\CurrentControlSet\Control\Class\"
	kb := RegRead(cls "{4D36E96B-E325-11CE-BFC1-08002BE10318}", "UpperFilters", "")
	ms := RegRead(cls "{4D36E96F-E325-11CE-BFC1-08002BE10318}", "UpperFilters", "")
	return InStr("`n" kb "`n", "`nkeyboard`n") && InStr("`n" ms "`n", "`nmouse`n")
}
