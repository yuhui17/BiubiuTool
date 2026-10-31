/*
Biubiu按键小工具 (基于 AutoHotInterception)
- 每一行是一个独立的按键/鼠标点击, 按自己的间隔循环触发
- 勾选 "浮动间隔" 后, 每次间隔会额外随机加 0~浮动 ms
- 鼠标行 X/Y 留空 = 在当前位置点击; 点 "取点" 后把鼠标移到目标按 F9 记录坐标
- 自动贩卖 (另一个分页): 依次点 ITEM 1 / ITEM 2 页面, 逐格检查第 1~64 格,
  空格子跳过, 有东西就 右键 -> Enter 确认, 等格子变成空格子再换下一格
- F7 开始连点 / F12 开始贩卖 / F8 停止 (可修改)
- 所有输入都通过 Interception 驱动发送 (模拟硬件输入)
*/
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; 编译成 exe 时的设置 (Ahk2Exe)
;@Ahk2Exe-SetMainIcon icon.ico
;@Ahk2Exe-SetName Biubiu按键小工具
;@Ahk2Exe-SetDescription Biubiu按键小工具
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
; 图标: exe 直接用自己内嵌的图标 (Icon1), 不释放成文件; 直接运行 .ahk 时用 icon.png
IconFile := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir "\icon.png"
IconOpt := A_IsCompiled ? "Icon1" : ""
if (!A_IsCompiled && FileExist(IconFile))
	TraySetIcon(IconFile) ; 托盘图标, 之后创建的窗口也会用它 (exe 本身已经带这个图标)
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
InstallKeybdHook
InstallMouseHook
DllCall("winmm\timeBeginPeriod", "UInt", 1) ; 让间隔精确到 1ms 左右

AHI := AutoHotInterception()
CfgFile := A_ScriptDir "\Biubiu按键小工具.ini"
KEY_ROWS := 14
MOUSE_ROWS := 4
HOLD_MS := 30 ; 每次按下到松开的时间
BtnNames := ["左键", "右键", "中键"] ; AHI 鼠标按键代码 0 / 1 / 2
DefaultKeys := ["1", "2", "3", "4", "5", "6", "7", "F1", "F2", "F3", "F4", "F5", "F6", "F7"]

; 自动贩卖
SellCoordNames := ["sellGrid1", "sellGrid64", "sell1", "sell2"]
SellLabels := Map("sellGrid1", "贩卖 第 1 格", "sellGrid64", "贩卖 第 64 格"
	, "sell1", "ITEM 1 页面", "sell2", "ITEM 2 页面")
PageNames := ["ITEM 1", "ITEM 2"]
SlotEmptyFile := A_ScriptDir "\images\slot_empty.bmp" ; 和 Biubiu强化小工具 共用同一张
TOTAL_SLOTS := 64
SLOT_MARGIN := 8 ; 判断格子是否为空时, 只在格子中心 ± (图片一半 + 这么多像素) 内找, 避免找到隔壁格子
CLICK_GAP := 80 ; "每次点击 N 下" 时, 每下之间间隔的毫秒
SC_ENTER := GetKeySC("Enter") ; 贩卖的确认 = 按 Enter
BTN_LEFT := 0
BTN_RIGHT := 1

Running := false ; 连点运行中
Selling := false ; 自动贩卖运行中 (两者不能同时运行, 都要用鼠标)
MouseBusy := false ; 鼠标正在移动/按下中, 其他鼠标动作要等它完成
Jobs := []
PickTarget := 0 ; 正在取点的坐标框 {x, y, label}
StartKey := ""
SellKey := ""
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
g := Gui(, "Biubiu按键小工具")
g.SetFont("s10", "Microsoft YaHei UI")
g.OnEvent("Close", (*) => ExitApp())

; 标题栏: 图标 + 名称
TOP := 58 ; 标题栏高度, 下面所有控件整体下移这么多
if FileExist(IconFile)
	g.Add("Picture", "x15 y8 w42 h42 " IconOpt, IconFile)
g.SetFont("s16 Bold c303030")
g.Add("Text", "x66 y12", "Biubiu按键小工具")
g.SetFont("s10 Norm cDefault")
g.Add("Text", "x15 y" TOP - 4 " w590 h1 0x10") ; 分隔线

; 按钮先创建, 让窗口打开时焦点落在按钮上, 而不是按键框 (按键框一获得焦点就会开始录键)
btnSave := g.Add("Button", "x346 y" TOP + 11 " w80 h30", "保存设置")
btnSave.OnEvent("Click", SaveConfig)
g.Add("Button", "x434 y" TOP + 11 " w80 h30", "读取配置").OnEvent("Click", LoadConfig)
; 热键: 开始连点 / 开始贩卖 / 停止 (停止对两者都有效)
g.Add("Text", "x20 y" TOP + 17, "连点")
edStart := g.Add("Edit", "x56 y" TOP + 13 " w60 Center ReadOnly", "F7")
g.Add("Text", "x126 y" TOP + 17, "贩卖")
edSell := g.Add("Edit", "x162 y" TOP + 13 " w60 Center ReadOnly", "F12")
g.Add("Text", "x232 y" TOP + 17, "停止")
edStop := g.Add("Edit", "x268 y" TOP + 13 " w60 Center ReadOnly", "F8")
for ed in [edStart, edSell, edStop]
	ed.OnEvent("Focus", CaptureKey.Bind(ed, btnSave))

; 分页: 连点 / 自动贩卖
BODY := TOP + 30 ; 分页标签的高度, 分页里的控件整体再下移这么多
tabs := g.Add("Tab3", "x10 y" TOP + 50 " w600 h455", ["连点", "自动贩卖"])

; ===== 分页 1: 连点 =====
tabs.UseTab(1)
chkJitter := g.Add("CheckBox", "x18 y" BODY + 52 " Checked", "浮动间隔")

; 按键 (两列, 每列 7 行)
for col in [0, 300] {
	g.Add("Text", Format("x{} y{} w80 Center", 95 + col, BODY + 52), "按键")
	g.Add("Text", Format("x{} y{} w55 Center", 183 + col, BODY + 52), "间隔")
	g.Add("Text", Format("x{} y{} w55 Center", 246 + col, BODY + 52), "浮动")
}
KeyRows := []
Loop KEY_ROWS {
	col := A_Index <= 7 ? 0 : 300
	y := BODY + 76 + Mod(A_Index - 1, 7) * 32
	KeyRows.Push(r := {
		chk: g.Add("CheckBox", Format("x{} y{} w80", 15 + col, y + 3), "_按键" A_Index),
		key: g.Add("Edit", Format("x{} y{} w80 Center ReadOnly", 95 + col, y), DefaultKeys[A_Index]),
		int: g.Add("Edit", Format("x{} y{} w55 Center Number cBlue", 183 + col, y), 300),
		jit: g.Add("Edit", Format("x{} y{} w55 Center Number cBlue", 246 + col, y), 15)
	})
	r.key.OnEvent("Focus", CaptureKey.Bind(r.key, r.chk))
}

; 鼠标点击
g.Add("Text", "x15 y" BODY + 308 " w590 h1 0x10") ; 分隔线
g.Add("Text", "x95 y" BODY + 318 " w80 Center", "鼠标")
g.Add("Text", "x183 y" BODY + 318 " w55 Center", "X")
g.Add("Text", "x246 y" BODY + 318 " w55 Center", "Y")
g.Add("Text", "x309 y" BODY + 318 " w55 Center", "间隔")
g.Add("Text", "x372 y" BODY + 318 " w55 Center", "浮动")
MouseRows := []
Loop MOUSE_ROWS {
	y := BODY + 342 + (A_Index - 1) * 32
	MouseRows.Push(r := {
		chk: g.Add("CheckBox", Format("x15 y{} w80", y + 3), "_鼠标" A_Index),
		btn: g.Add("DropDownList", Format("x95 y{} w80 Choose1", y), BtnNames),
		x: g.Add("Edit", Format("x183 y{} w55 Center", y)),
		y: g.Add("Edit", Format("x246 y{} w55 Center", y)),
		int: g.Add("Edit", Format("x309 y{} w55 Center Number cBlue", y), 1000),
		jit: g.Add("Edit", Format("x372 y{} w55 Center Number cBlue", y), 15)
	})
	btnPick := g.Add("Button", Format("x435 y{} w60 h27", y), "取点")
	btnPick.OnEvent("Click", StartPick.Bind({x: r.x, y: r.y, label: "_鼠标" A_Index}))
}

; ===== 分页 2: 自动贩卖 =====
tabs.UseTab(2)
; 坐标
g.Add("GroupBox", "x20 y" BODY + 52 " w300 h184", "贩卖坐标   (点「取点」后按 F9)")
SellCoords := Map()
for i, name in SellCoordNames {
	y := BODY + 78 + (i - 1) * 30
	g.Add("Text", Format("x30 y{} w100", y + 4), SellLabels[name])
	SellCoords[name] := {
		x: g.Add("Edit", Format("x134 y{} w54 Center", y)),
		y: g.Add("Edit", Format("x192 y{} w54 Center", y))
	}
	btnPick := g.Add("Button", Format("x252 y{} w56 h26", y), "取点")
	btnPick.OnEvent("Click", StartPick.Bind({x: SellCoords[name].x, y: SellCoords[name].y, label: SellLabels[name]}))
}
g.Add("Button", "x30 y" BODY + 198 " w70 h26", "检查").OnEvent("Click", ShowSellCoords)
g.Add("Text", "x108 y" BODY + 202 " cGray", "在屏幕上标出格子和坐标 4 秒")

; 空格子截图
g.Add("GroupBox", "x330 y" BODY + 52 " w270 h70", "空格子截图   (格子没东西的样子)")
g.Add("Button", "x344 y" BODY + 78 " w90 h30", "框选截图").OnEvent("Click", ShotSlotEmpty)
picSlotEmpty := g.Add("Picture", "x444 y" BODY + 76 " w34 h34 Border")
txtSlotEmpty := g.Add("Text", "x486 y" BODY + 84 " w110", "未截图")

; 贩卖设置
g.Add("GroupBox", "x330 y" BODY + 130 " w270 h136", "贩卖设置")
g.Add("Text", "x344 y" BODY + 158, "每步间隔ms:")
edSellStep := g.Add("Edit", "x430 y" BODY + 154 " w56 Center Number", 300)
g.Add("Text", "x344 y" BODY + 188, "从第几格开始:")
edSellStart := g.Add("Edit", "x440 y" BODY + 184 " w44 Center Number", 1)
g.Add("Text", "x490 y" BODY + 188 " cGray", "(1-64)")
g.Add("Text", "x344 y" BODY + 218, "不卖第")
edSkip1 := g.Add("Edit", "x390 y" BODY + 214 " w40 Center Number", 63)
g.Add("Text", "x434 y" BODY + 218, "格和第")
edSkip2 := g.Add("Edit", "x478 y" BODY + 214 " w40 Center Number", 64)
g.Add("Text", "x522 y" BODY + 218, "格")
g.Add("Text", "x344 y" BODY + 246, "页面:")
chkSellP1 := g.Add("CheckBox", "x392 y" BODY + 244 " Checked", "ITEM 1")
chkSellP2 := g.Add("CheckBox", "x470 y" BODY + 244 " Checked", "ITEM 2")

; 其他
g.Add("GroupBox", "x20 y" BODY + 276 " w580 h64", "其他")
g.Add("Text", "x34 y" BODY + 304, "找图容差:")
edSellTol := g.Add("Edit", "x102 y" BODY + 300 " w44 Center Number", 30)
g.Add("Text", "x176 y" BODY + 304, "每次点击")
edSellClicks := g.Add("Edit", "x236 y" BODY + 300 " w44 Center Number", 1)
g.Add("Text", "x284 y" BODY + 304, "下")
g.Add("Text", "x310 y" BODY + 304 " cGray", "(含 Enter 确认; 虚拟机漏点可设 2~3)")

g.Add("Text", "x24 y" BODY + 354 " w570 cGray"
	, "流程: 依次点 ITEM 1 / ITEM 2 页面, 逐格检查第 1~64 格 (跳过「不卖」的两格):`n"
	. "空格子直接跳过; 有东西就 右键 → Enter 确认, 等格子变成空格子再换下一格。")

tabs.UseTab()
txtStatus := g.Add("Text", "x15 y" TOP + 515 " w590 cGray")

LoadConfig()
ApplyHotkeys()
UpdateSlotEmptyPreview()
SetStatus("")
g.Show("w620 h" TOP + 540)
return

; ---------------- 运行 ----------------
StartMacro(*) {
	global Running, Jobs
	if (Running || Selling)
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
		MsgBox(errs, "Biubiu按键小工具", "Icon!")
		return
	}
	if !newJobs.Length {
		MsgBox("请至少勾选一个按键或鼠标", "Biubiu按键小工具")
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

; 停止键: 连点和贩卖都停
StopAll(*) {
	global Selling
	StopMacro()
	Selling := false
}

; 开始键的热键回调 (mode: "macro" 连点 / "sell" 贩卖);
; 开始键和停止键设成同一个键时 (toggles), 运行中再按一次就停止
HotkeyStart(mode, toggles, *) {
	if (Running || Selling) {
		if toggles
			StopAll()
		return
	}
	if (mode = "sell")
		StartSell()
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

; ---------------- 自动贩卖 ----------------
StartSell(*) {
	global Selling
	if (Running || Selling)
		return
	if (err := ValidateSell()) != "" {
		MsgBox(err, "Biubiu按键小工具", "Icon!")
		return
	}
	Selling := true
	SetTimer(RunSell, -1)
}

ValidateSell() {
	if (!chkSellP1.Value && !chkSellP2.Value)
		return "请至少勾选一个贩卖页面"
	need := ["sellGrid1", "sellGrid64"]
	if chkSellP1.Value
		need.Push("sell1")
	if chkSellP2.Value
		need.Push("sell2")
	for name in need
		if !HasSellCoord(name)
			return "请先设置贩卖坐标: " SellLabels[name]
	if !FileExist(SlotEmptyFile)
		return "请先截图「空格子」"
	s := ToInt(edSellStart.Value)
	if (s < 1 || s > TOTAL_SLOTS)
		return "从第几格开始 要填 1 到 " TOTAL_SLOTS
	return ""
}

; 依次处理勾选的页面, 每页第 1~64 格 (跳过「不卖」的两格):
; 空格子跳过; 有东西就 右键 -> Enter 确认, 等格子变成空格子再换下一格
RunSell() {
	global Selling
	step := ToInt(edSellStep.Value)
	pages := []
	if chkSellP1.Value
		pages.Push(1)
	if chkSellP2.Value
		pages.Push(2)
	sold := 0
	where := ""
	try {
		for pi, pg in pages {
			SetStatus("切换到 " PageNames[pg] " 页…")
			ClickPos(GetSellCoord("sell" pg))
			SleepSell(step)
			slot := (pi = 1) ? ToInt(edSellStart.Value) : 1 ; "从第几格开始" 只对第一页有效
			while (Selling && slot <= TOTAL_SLOTS) {
				where := PageNames[pg] " 页 第 " slot " 格"
				p := SlotPos(slot)
				if (!IsSkipSlot(slot) && !SlotIsEmpty(p)) {
					SetStatus(where " / " TOTAL_SLOTS ":  贩卖中…   (按 " StopKey " 停止)")
					ClickPos(p, BTN_RIGHT)
					SleepSell(step)
					PressEnter()
					SleepSell(step)
					SetStatus(where " / " TOTAL_SLOTS ":  等待格子变空…   (按 " StopKey " 停止)")
					while (Selling && !SlotIsEmpty(p))
						SleepSell(100)
					if !Selling
						break
					sold++
				}
				slot++
			}
			if !Selling
				break
		}
	} catch as e {
		MsgBox("运行出错: " e.Message, "Biubiu按键小工具", "Icon!")
		Selling := false
	}
	if Selling
		SetStatus("贩卖完成! 共卖出 " sold " 格")
	else
		SetStatus("已停止在 " where "  (本次卖出 " sold " 格)")
	Selling := false
}

; 确认 = 按 Enter, 次数同 "每次点击" 的设定
PressEnter() {
	Loop Max(ToInt(edSellClicks.Value), 1) {
		if (A_Index > 1)
			Sleep CLICK_GAP
		AHI.SendKeyEvent(KbId, SC_ENTER, 1)
		Sleep HOLD_MS
		AHI.SendKeyEvent(KbId, SC_ENTER, 0)
	}
}

; 在 p 点击 "每次点击" 设定的次数 (虚拟机卡顿时单次点击可能没被游戏收到)
ClickPos(p, btn := 0) { ; btn: BTN_LEFT / BTN_RIGHT
	MoveTo(p.x, p.y)
	Sleep 20 ; 光标到位后等一下再按, 让游戏反应过来
	Loop Max(ToInt(edSellClicks.Value), 1) {
		if (A_Index > 1)
			Sleep CLICK_GAP
		AHI.SendMouseButtonEvent(MouseId, btn, 1)
		Sleep HOLD_MS
		AHI.SendMouseButtonEvent(MouseId, btn, 0)
	}
}

; 贩卖用的等待, 按停止键会立刻中断
SleepSell(ms) {
	end := A_TickCount + ms
	while (Selling && A_TickCount < end)
		Sleep Min(10, end - A_TickCount)
}

; 「不卖」的两格 (填 0 表示不跳过)
IsSkipSlot(slot) => slot = ToInt(edSkip1.Value) || slot = ToInt(edSkip2.Value)

SlotIsEmpty(p) => FindImageAround(SlotEmptyFile, p.x, p.y, SLOT_MARGIN, &cx, &cy)

HasSellCoord(name) => IsInteger(Trim(SellCoords[name].x.Value)) && IsInteger(Trim(SellCoords[name].y.Value))

GetSellCoord(name) {
	return {x: ToInt(SellCoords[name].x.Value), y: ToInt(SellCoords[name].y.Value)}
}

; 由贩卖第 1 格 (左上) 和第 64 格 (右下) 按等距算出第 i 格的中心
SlotPos(i) {
	a := GetSellCoord("sellGrid1"), b := GetSellCoord("sellGrid64")
	col := Mod(i - 1, 8), row := (i - 1) // 8
	return {x: Round(a.x + (b.x - a.x) * col / 7), y: Round(a.y + (b.y - a.y) * row / 7)}
}

; 在屏幕上把贩卖坐标标出来 4 秒: 橙 = 格子 (灰 = 不卖的格子), 绿 = 其他坐标
ShowSellCoords(*) {
	static ov := 0
	if ov
		try ov.Destroy()
	vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
	ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20")
	ov.BackColor := "010101"
	ov.SetFont("s8 Bold", "Microsoft YaHei UI")
	marks := 0
	if (HasSellCoord("sellGrid1") && HasSellCoord("sellGrid64")) {
		Loop TOTAL_SLOTS {
			p := SlotPos(A_Index)
			Mark(ov, p.x - vx, p.y - vy, IsSkipSlot(A_Index) ? "A0A0A0" : "FFA000", A_Index)
		}
		marks += TOTAL_SLOTS
	}
	for name in ["sell1", "sell2"] {
		if HasSellCoord(name) {
			p := GetSellCoord(name)
			Mark(ov, p.x - vx, p.y - vy, "30D030", SellLabels[name])
			marks++
		}
	}
	if !marks {
		ov.Destroy()
		ov := 0
		SetStatus("还没有设置任何贩卖坐标")
		return
	}
	ov.Show(Format("x{} y{} w{} h{} NA", vx, vy, vw, vh))
	WinSetTransColor("010101", ov)
	SetTimer(DestroyQuiet.Bind(ov), -4000)
	SetStatus("已在屏幕上标出贩卖坐标 (4 秒)")
}

DestroyQuiet(gui) {
	try gui.Destroy() ; 可能已经被再次点「检查」时关掉了
}

Mark(gui, x, y, color, label) {
	gui.Add("Text", Format("x{} y{} w10 h10 Background{}", x - 5, y - 5, color))
	gui.Add("Text", Format("x{} y{} c{} BackgroundTrans", x + 7, y - 9, color), label)
}

; ---------------- 找图 / 截图 ----------------
; 在 (x, y) 附近找图: 范围 = 以 (x, y) 为中心, 图片大小再往外扩 margin 像素; 找到时 cx, cy 返回图片中心
FindImageAround(file, x, y, margin, &cx, &cy) {
	size := ImageSize(file)
	mx := size.w // 2 + margin, my := size.h // 2 + margin
	if !ImageSearch(&fx, &fy, x - mx, y - my, x + mx, y + my, "*" ToInt(edSellTol.Value) " " file)
		return false
	cx := fx + size.w // 2
	cy := fy + size.h // 2
	return true
}

; 带缓存的图片大小, 重新截图 (文件时间 / 大小变了) 后自动更新
ImageSize(file) {
	static sizes := Map()
	stamp := FileGetTime(file) FileGetSize(file)
	if (!sizes.Has(file) || sizes[file].stamp != stamp)
		sizes[file] := {stamp: stamp, size: GetImageSize(file)}
	return sizes[file].size
}

GetImageSize(path) {
	hbm := LoadPicture(path)
	if !hbm
		throw Error("无法读取图片: " path)
	bm := Buffer(32, 0)
	DllCall("GetObject", "Ptr", hbm, "Int", bm.Size, "Ptr", bm)
	DllCall("DeleteObject", "Ptr", hbm)
	return {w: NumGet(bm, 4, "Int"), h: NumGet(bm, 8, "Int")}
}

ShotSlotEmpty(*) {
	g.Hide()
	Sleep 200
	try r := CaptureRegion(SlotEmptyFile, "框选一个空格子")
	catch as e {
		r := ""
		MsgBox("截图失败: " e.Message, "Biubiu按键小工具", "Icon!")
	}
	g.Show()
	if !r
		return
	UpdateSlotEmptyPreview()
	SetStatus("空格子图片已保存")
}

UpdateSlotEmptyPreview() {
	if FileExist(SlotEmptyFile) {
		sz := GetImageSize(SlotEmptyFile)
		picSlotEmpty.Value := "*w34 *h34 " SlotEmptyFile
		txtSlotEmpty.Value := "已截图 (" sz.w " x " sz.h ")"
	} else {
		txtSlotEmpty.Value := "未截图"
	}
}

; 全屏半透明遮罩, 按住左键拖动框选, 松开后保存为 BMP; Esc 取消
CaptureRegion(file, hint := "框选图片") {
	vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
	ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
	ov.BackColor := "000000"
	ov.Show(Format("x{} y{} w{} h{}", vx, vy, vw, vh))
	WinSetTransparent(70, ov)
	sel := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +Owner" ov.Hwnd)
	sel.BackColor := "FF3030"
	ToolTip("按住左键拖动, " hint "   (Esc 取消)")

	Loop {
		if GetKeyState("Esc", "P") {
			ToolTip()
			ov.Destroy()
			return ""
		}
		if GetKeyState("LButton", "P")
			break
		Sleep 10
	}
	MouseGetPos(&x1, &y1)
	shown := false
	while GetKeyState("LButton", "P") {
		MouseGetPos(&x2, &y2)
		sel.Show(Format("x{} y{} w{} h{} NA", Min(x1, x2), Min(y1, y2), Abs(x2 - x1) + 1, Abs(y2 - y1) + 1))
		if !shown {
			WinSetTransparent(90, sel)
			shown := true
		}
		Sleep 15
	}
	MouseGetPos(&x2, &y2)
	ToolTip()
	sel.Destroy()
	ov.Destroy()

	r := {x: Min(x1, x2), y: Min(y1, y2), w: Abs(x2 - x1) + 1, h: Abs(y2 - y1) + 1}
	if (r.w < 4 || r.h < 4)
		return ""
	Sleep 150 ; 等遮罩完全消失再截图
	SplitPath(file, , &dir)
	DirCreate(dir)
	SaveScreenBmp(r.x, r.y, r.w, r.h, file)
	return r
}

SaveScreenBmp(x, y, w, h, file) {
	hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
	mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
	bi := Buffer(40, 0) ; BITMAPINFOHEADER, 24 位
	NumPut("UInt", 40, "Int", w, "Int", h, "UShort", 1, "UShort", 24, bi)
	hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
	obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
	DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdc, "Int", x, "Int", y, "UInt", 0x00CC0020) ; SRCCOPY

	size := ((w * 3 + 3) & ~3) * h
	hdr := Buffer(14, 0) ; BITMAPFILEHEADER
	NumPut("UShort", 0x4D42, "UInt", 54 + size, "UInt", 0, "UInt", 54, hdr)
	f := FileOpen(file, "w", "UTF-8-RAW")
	f.RawWrite(hdr)
	f.RawWrite(bi)
	f.RawWrite(bits, size)
	f.Close()

	DllCall("SelectObject", "Ptr", mdc, "Ptr", obm)
	DllCall("DeleteObject", "Ptr", hbm)
	DllCall("DeleteDC", "Ptr", mdc)
	DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
}

; ---------------- 鼠标移动 ----------------
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
	global StartKey, SellKey, StopKey
	s := Trim(edStart.Value), b := Trim(edSell.Value), t := Trim(edStop.Value)
	if (s = StartKey && b = SellKey && t = StopKey)
		return
	if (s = b) {
		MsgBox("连点和贩卖的开始键不能设成同一个键", "Biubiu按键小工具", "Icon!")
		edStart.Value := StartKey, edSell.Value := SellKey, edStop.Value := StopKey
		return
	}
	for k in [StartKey, SellKey, StopKey]
		if (k != "")
			try Hotkey(ToHotkey(k), "Off")
	try {
		Hotkey(ToHotkey(s), HotkeyStart.Bind("macro", s = t), "On")
		Hotkey(ToHotkey(b), HotkeyStart.Bind("sell", b = t), "On")
		if (t != s && t != b)
			Hotkey(ToHotkey(t), StopAll, "On")
	} catch as e {
		MsgBox("热键设置无效: " e.Message, "Biubiu按键小工具", "Icon!")
	}
	StartKey := s, SellKey := b, StopKey := t
	if (!Running && !Selling)
		SetStatus("")
}

; target: {x: X 坐标框, y: Y 坐标框, label: 显示名称}
StartPick(target, *) {
	global PickTarget := target
	Hotkey("F9", DoPick, "On")
	SetStatus("把鼠标移到「" target.label "」的位置, 按 F9 记录坐标")
}

DoPick(*) {
	global PickTarget
	Hotkey("F9", "Off")
	if !PickTarget
		return
	MouseGetPos(&x, &y)
	PickTarget.x.Value := x
	PickTarget.y.Value := y
	SetStatus(PickTarget.label " 坐标已设为 " x ", " y)
	PickTarget := 0
}

SetStatus(text) {
	if (text = "")
		text := "点击按键框后按下要用的键。按 " StartKey " 开始连点 / " SellKey " 开始贩卖 / " StopKey " 停止"
	txtStatus.Value := text
}

; ---------------- 配置 ----------------
SaveConfig(*) {
	ApplyHotkeys()
	IniWrite(edStart.Value, CfgFile, "Main", "Start")
	IniWrite(edSell.Value, CfgFile, "Main", "Sell")
	IniWrite(edStop.Value, CfgFile, "Main", "Stop")
	IniWrite(chkJitter.Value, CfgFile, "Main", "Jitter")
	for i, r in KeyRows
		IniWrite(Format("{}|{}|{}|{}", r.chk.Value, r.key.Value, r.int.Value, r.jit.Value), CfgFile, "Keys", i)
	for i, r in MouseRows
		IniWrite(Format("{}|{}|{}|{}|{}|{}", r.chk.Value, r.btn.Value, r.x.Value, r.y.Value, r.int.Value, r.jit.Value), CfgFile, "Mouse", i)
	; 自动贩卖
	for name in SellCoordNames
		IniWrite(Trim(SellCoords[name].x.Value) "," Trim(SellCoords[name].y.Value), CfgFile, "SellCoords", name)
	IniWrite(ToInt(edSellStep.Value), CfgFile, "Sell", "Step")
	IniWrite(ToInt(edSellStart.Value), CfgFile, "Sell", "StartSlot")
	IniWrite(ToInt(edSkip1.Value), CfgFile, "Sell", "Skip1")
	IniWrite(ToInt(edSkip2.Value), CfgFile, "Sell", "Skip2")
	IniWrite(chkSellP1.Value, CfgFile, "Sell", "Page1")
	IniWrite(chkSellP2.Value, CfgFile, "Sell", "Page2")
	IniWrite(ToInt(edSellTol.Value), CfgFile, "Sell", "Tolerance")
	IniWrite(Max(ToInt(edSellClicks.Value), 1), CfgFile, "Sell", "Clicks")
	SetStatus("设置已保存")
}

; 贩卖坐标: 自己的配置里没有时, 沿用同文件夹 Biubiu强化小工具 的贩卖坐标 (同名)
LoadSellCoords() {
	enhIni := A_ScriptDir "\Biubiu强化小工具.ini"
	for name in SellCoordNames {
		v := FileExist(CfgFile) ? IniRead(CfgFile, "SellCoords", name, "") : ""
		if (v = "" && FileExist(enhIni))
			v := IniRead(enhIni, "Coords", name, "")
		f := StrSplit(v, ",")
		if (f.Length = 2)
			SellCoords[name].x.Value := f[1], SellCoords[name].y.Value := f[2]
	}
}

LoadConfig(ctrl := 0, *) {
	LoadSellCoords()
	if !FileExist(CfgFile) {
		if ctrl
			MsgBox("还没有保存过设置", "Biubiu按键小工具")
		return
	}
	edStart.Value := IniRead(CfgFile, "Main", "Start", "F7")
	edSell.Value := IniRead(CfgFile, "Main", "Sell", "F12")
	edStop.Value := IniRead(CfgFile, "Main", "Stop", "F8")
	edSellStep.Value := IniRead(CfgFile, "Sell", "Step", 300)
	edSellStart.Value := IniRead(CfgFile, "Sell", "StartSlot", 1)
	edSkip1.Value := IniRead(CfgFile, "Sell", "Skip1", 63)
	edSkip2.Value := IniRead(CfgFile, "Sell", "Skip2", 64)
	chkSellP1.Value := ToInt(IniRead(CfgFile, "Sell", "Page1", 1))
	chkSellP2.Value := ToInt(IniRead(CfgFile, "Sell", "Page2", 1))
	edSellTol.Value := IniRead(CfgFile, "Sell", "Tolerance", 30)
	edSellClicks.Value := IniRead(CfgFile, "Sell", "Clicks", 1)
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
		UpdateSlotEmptyPreview()
		SetStatus("已读取配置")
	}
}

; ---------------- 驱动 ----------------
; 检测不到设备时调用: 驱动没装 -> 询问安装; 装了但没生效 -> 提示重启
CheckDriver() {
	title := "Biubiu按键小工具"
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
