/*
Biubiu强化小工具 (基于 AutoHotInterception)
- 背包 8x8 共 64 格: 水晶 / 红宝石放在哪一格可以设置 (默认第 63 / 64 格), 其余格子是要强化的物品
- 强化前先看格子是不是空格子, 是就跳过 (那一格没有道具)
- 每一格的流程: 右键物品 -> 右键水晶 -> 确认 -> 右键红宝 -> 确认 -> OK -> 确认,
  然后等 GEM 图片出现, 从图片中心往上拖拽一段距离, 再换下一格
- 自动贩卖: 逐格检查, 不是空格子就 右键 -> 确认贩卖, 等格子变成空格子再换下一格; 本来就空的格子跳过
- 强化 / 贩卖都依次处理 ITEM 1 页、ITEM 2 页 (可勾选) 的第 1~64 格, 跳过水晶 / 红宝石那两格;
  强化和贩卖的页面按钮各有一组坐标
- 背包只需取第 1 格和第 64 格的坐标, 其余格子自动按等距计算
- F7 开始强化 / F6 开始贩卖 / F8 停止 (可修改), 点 "取点" 后把鼠标移到目标位置按 F9 记录坐标
*/
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; 编译成 exe 时的设置 (Ahk2Exe)
;@Ahk2Exe-SetMainIcon icon.ico
;@Ahk2Exe-SetName Biubiu强化小工具
;@Ahk2Exe-SetDescription Biubiu强化小工具
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
CoordMode "Pixel", "Screen"
InstallKeybdHook
InstallMouseHook
DllCall("winmm\timeBeginPeriod", "UInt", 1) ; 让间隔精确到 1ms 左右

AHI := AutoHotInterception()
CfgFile := A_ScriptDir "\Biubiu强化小工具.ini"
; 强化完成后侦测位置会出现其中一种图: GEM (要往上拖走) 或 空 (直接下一格)
; 空格子: 背包格子里没有东西的样子; 强化用来跳过没道具的格子, 贩卖用来判断格子有没有东西 / 有没有卖掉
Images := Map(
	"gem", {file: A_ScriptDir "\images\gem.bmp", label: "GEM", use: "强化用"},
	"empty", {file: A_ScriptDir "\images\empty.bmp", label: "空", use: "强化用"},
	"slotEmpty", {file: A_ScriptDir "\images\slot_empty.bmp", label: "空格子", use: "强化 / 贩卖"}
)
DETECT_MARGIN := 60 ; GEM / 空 只在侦测位置 ± (图片一半 + 这么多像素) 内找
SLOT_MARGIN := 8 ; 判断格子是否为空时, 只在格子中心 ± (图片一半 + 这么多像素) 内找, 避免找到隔壁格子
HOLD_MS := 30 ; 每次点击按下到松开的时间
DRAG_STEP := 50 ; 拖拽时每步移动的像素, 越大越快
DRAG_DELAY := 2 ; 拖拽每步之间等待的毫秒, 越小越快
DRAG_HOLD := 15 ; 拖拽按下后 / 松开前等待的毫秒
BTN_LEFT := 0 ; AHI 鼠标按键代码
BTN_RIGHT := 1
TOTAL_SLOTS := 64 ; 背包 8x8, 水晶 / 红宝石所在的格子会被跳过

Running := false
PickName := ""
StartKey := "" ; 开始强化
SellKey := "" ; 开始贩卖
StopKey := ""

CoordNames := ["grid1", "grid64", "confirm", "ok", "detect", "enh1", "enh2"
	, "sellGrid1", "sellGrid64", "sellConfirm", "sell1", "sell2"]
CoordLabels := Map("grid1", "强化 第 1 格", "grid64", "强化 第 64 格", "confirm", "确认强化", "ok", "OK", "detect", "GEM 侦测位置"
	, "enh1", "ITEM 1 (强化)", "enh2", "ITEM 2 (强化)", "sellGrid1", "贩卖 第 1 格", "sellGrid64", "贩卖 第 64 格"
	, "sellConfirm", "确认贩卖", "sell1", "ITEM 1 (贩卖)", "sell2", "ITEM 2 (贩卖)")
; 每种模式的背包格子 (第 1 格 / 第 64 格) 和页面按钮 (第 1 / 第 2 页) 坐标, 状态栏显示用的页名
GridCoords := Map("enhance", ["grid1", "grid64"], "sell", ["sellGrid1", "sellGrid64"])
PageCoords := Map("enhance", ["enh1", "enh2"], "sell", ["sell1", "sell2"])
PageNames := ["ITEM 1", "ITEM 2"]

; 使用第一个鼠标设备发送点击
MouseId := 0
for id, dev in AHI.GetDeviceList() {
	if dev.IsMouse {
		MouseId := id
		break
	}
}
if !MouseId {
	CheckDriver()
	ExitApp
}

; ---------------- 界面 ----------------
g := Gui(, "Biubiu强化小工具")
g.SetFont("s10", "Microsoft YaHei UI")
g.OnEvent("Close", (*) => ExitApp())

; 标题栏: 图标 + 名称
TOP := 58 ; 标题栏高度, 下面所有控件整体下移这么多
if FileExist(IconFile)
	g.Add("Picture", "x15 y8 w42 h42", IconFile)
g.SetFont("s16 Bold c303030")
g.Add("Text", "x66 y12", "Biubiu强化小工具")
g.SetFont("s10 Norm cDefault")
g.Add("Text", "x15 y" TOP - 4 " w400 h1 0x10") ; 分隔线

; 按钮先创建, 让窗口打开时焦点落在按钮上, 而不是热键框 (热键框一获得焦点就会开始录键)
btnSave := g.Add("Button", "x252 y12 w76 h30", "保存设置")
btnSave.OnEvent("Click", SaveConfig)
g.Add("Button", "x334 y12 w76 h30", "读取配置").OnEvent("Click", LoadConfig)
; 热键: 开始强化 / 开始贩卖 / 停止
g.Add("Text", "x20 y" TOP + 17, "强化")
edStart := g.Add("Edit", "x56 y" TOP + 13 " w60 Center ReadOnly", "F7")
g.Add("Text", "x146 y" TOP + 17, "贩卖")
edSell := g.Add("Edit", "x182 y" TOP + 13 " w60 Center ReadOnly", "F6")
g.Add("Text", "x272 y" TOP + 17, "停止")
edStop := g.Add("Edit", "x308 y" TOP + 13 " w60 Center ReadOnly", "F8")
for ed in [edStart, edSell, edStop]
	ed.OnEvent("Focus", CaptureKey.Bind(ed, btnSave))

; 坐标
g.Add("GroupBox", "x10 y" TOP + 52 " w400 h392", "坐标设置   (点「取点」后, 鼠标移到目标位置按 F9)")
Coords := Map()
for i, name in CoordNames {
	y := TOP + 78 + (i - 1) * 30
	g.Add("Text", Format("x24 y{} w118", y + 4), CoordLabels[name])
	Coords[name] := {
		x: g.Add("Edit", Format("x146 y{} w58 Center", y)),
		y: g.Add("Edit", Format("x210 y{} w58 Center", y))
	}
	g.Add("Button", Format("x276 y{} w56 h27", y), "取点").OnEvent("Click", StartPick.Bind(name))
}
g.Add("Button", Format("x340 y{} w62 h27", TOP + 78), "检查").OnEvent("Click", ShowCoords)
g.Add("Text", Format("x340 y{} w64 cGray", TOP + 112), "在屏幕上`n标出所有`n坐标 4 秒")

; 侦测图片: 每张一行 (截图按钮 / 预览 / 状态 / 用途)
g.Add("GroupBox", "x10 y" TOP + 452 " w400 h142", "侦测图片")
for i, key in ["gem", "empty", "slotEmpty"] {
	y := TOP + 476 + (i - 1) * 38
	g.Add("Button", Format("x24 y{} w100 h30", y), "截图 " Images[key].label).OnEvent("Click", ShotImage.Bind(key))
	Images[key].pic := g.Add("Picture", Format("x134 y{} w34 h34 Border", y - 2))
	Images[key].txt := g.Add("Text", Format("x176 y{} w120", y + 6), "未截图")
	g.Add("Text", Format("x320 y{} w80 cGray", y + 6), Images[key].use)
}

; 流程 (强化 / 贩卖共用)
g.Add("GroupBox", "x10 y" TOP + 602 " w400 h156", "流程设置   (强化 / 贩卖共用)")
g.Add("Text", "x24 y" TOP + 630, "每步间隔ms:")
edStep := g.Add("Edit", "x110 y" TOP + 626 " w60 Center Number", 300)
g.Add("Text", "x190 y" TOP + 630, "从第几格开始:")
edStartSlot := g.Add("Edit", "x284 y" TOP + 626 " w44 Center Number", 1)
g.Add("Text", "x334 y" TOP + 630 " cGray", "(1-64)")
g.Add("Text", "x24 y" TOP + 664, "水晶在第")
edCrystal := g.Add("Edit", "x82 y" TOP + 660 " w44 Center Number", 63)
g.Add("Text", "x130 y" TOP + 664, "格")
g.Add("Text", "x160 y" TOP + 664, "红宝在第")
edRuby := g.Add("Edit", "x218 y" TOP + 660 " w44 Center Number", 64)
g.Add("Text", "x266 y" TOP + 664, "格")
g.Add("Text", "x292 y" TOP + 664 " cGray", "(这两格不处理)")
g.Add("Text", "x24 y" TOP + 696, "页面:")
chkP1 := g.Add("CheckBox", "x100 y" TOP + 694 " Checked", "ITEM 1")
chkP2 := g.Add("CheckBox", "x180 y" TOP + 694 " Checked", "ITEM 2")
g.Add("Text", "x260 y" TOP + 696 " cGray", "空格子会自动跳过")
g.Add("Text", "x24 y" TOP + 728, "拖拽距离:")
edDrag := g.Add("Edit", "x100 y" TOP + 724 " w60 Center Number", 100)
g.Add("Text", "x166 y" TOP + 728 " cGray", "像素 (GEM 往上拖)")
g.Add("Text", "x290 y" TOP + 728, "找图容差:")
edTol := g.Add("Edit", "x356 y" TOP + 724 " w44 Center Number", 30)

txtStatus := g.Add("Text", "x15 y" TOP + 768 " w400 cGray")

LoadConfig()
ApplyHotkeys()
UpdatePreviews()
SetStatus("")
g.Show("w420 h" TOP + 794)
return

; ---------------- 运行 ----------------
; mode: "enhance" 强化 / "sell" 贩卖
StartRun(mode, *) {
	global Running
	if Running
		return
	if (err := Validate(mode)) != "" {
		MsgBox(err, "Biubiu强化小工具", "Icon!")
		return
	}
	Running := true
	SetTimer(mode = "sell" ? RunSell : RunEnhance, -1)
}

StopRun(*) {
	global Running
	Running := false
}

; 开始键的热键回调; 开始键和停止键设成同一个键时 (toggles), 运行中再按一次就停止
HotkeyStart(mode, toggles, *) {
	if Running {
		if toggles
			StopRun()
		return
	}
	StartRun(mode)
}

Validate(mode) {
	pages := SelectedPages()
	if !pages.Length
		return "请至少勾选一个页面"
	need := mode = "sell" ? ["sellGrid1", "sellGrid64", "sellConfirm"] : ["grid1", "grid64", "confirm", "ok", "detect"]
	for pg in pages
		need.Push(PageCoords[mode][pg])
	for name in need
		if !HasCoord(name)
			return "请先设置坐标: " CoordLabels[name]
	for key in (mode = "sell" ? ["slotEmpty"] : ["gem", "empty", "slotEmpty"])
		if !FileExist(Images[key].file)
			return "请先截图「" Images[key].label "」图片"
	s := ToInt(edStartSlot.Value)
	if (s < 1 || s > TOTAL_SLOTS)
		return "从第几格开始 要填 1 到 " TOTAL_SLOTS
	c := ToInt(edCrystal.Value), r := ToInt(edRuby.Value)
	if (c < 1 || c > TOTAL_SLOTS || r < 1 || r > TOTAL_SLOTS)
		return "水晶 / 红宝所在的格子要填 1 到 " TOTAL_SLOTS
	if (c = r)
		return "水晶和红宝不能在同一格"
	return ""
}

; 水晶 / 红宝石所在的格子不强化也不贩卖
IsMaterialSlot(slot) => slot = ToInt(edCrystal.Value) || slot = ToInt(edRuby.Value)

; 勾选的页面编号 (1 = ITEM 1, 2 = ITEM 2)
SelectedPages() {
	pages := []
	if chkP1.Value
		pages.Push(1)
	if chkP2.Value
		pages.Push(2)
	return pages
}

; 点该模式第 pg 页的页面按钮坐标
SwitchPage(mode, pg) {
	SetStatus("切换到 " PageNames[pg] " 页…")
	ClickPos(GetCoord(PageCoords[mode][pg]))
}

; 自动贩卖: 每页第 1~64 格 (跳过水晶 / 红宝格), 不是空格子就 右键 -> 确认贩卖, 等格子变成空格子再换下一格
RunSell() {
	global Running
	step := ToInt(edStep.Value)
	confirm := GetCoord("sellConfirm")
	sold := 0
	where := ""
	try {
		for pi, pg in SelectedPages() {
			SwitchPage("sell", pg)
			SleepCheck(step)
			slot := (pi = 1) ? ToInt(edStartSlot.Value) : 1 ; "从第几格开始" 只对第一页有效
			while (Running && slot <= TOTAL_SLOTS) {
				where := PageNames[pg] " 页 第 " slot " 格"
				p := SlotPos(slot, "sell")
				if (!IsMaterialSlot(slot) && !SlotIsEmpty(p)) {
					SetStatus(where " / " TOTAL_SLOTS ":  贩卖中…   (按 " StopKey " 停止)")
					ClickPos(p, BTN_RIGHT)
					SleepCheck(step)
					ClickPos(confirm)
					SleepCheck(step)
					SetStatus(where " / " TOTAL_SLOTS ":  等待格子变空…   (按 " StopKey " 停止)")
					while (Running && !SlotIsEmpty(p))
						SleepCheck(100)
					if !Running
						break
					sold++
				}
				slot++
			}
			if !Running
				break
		}
	} catch as e {
		MsgBox("运行出错: " e.Message, "Biubiu强化小工具", "Icon!")
		Running := false
	}
	if Running
		SetStatus("贩卖完成! 共卖出 " sold " 格")
	else
		SetStatus("已停止在 " where "  (本次卖出 " sold " 格)")
	Running := false
}

SlotIsEmpty(p) => FindImageAround(Images["slotEmpty"].file, p.x, p.y, SLOT_MARGIN, &cx, &cy)

RunEnhance() {
	global Running
	step := ToInt(edStep.Value)
	crystal := SlotPos(ToInt(edCrystal.Value)), ruby := SlotPos(ToInt(edRuby.Value))
	confirm := GetCoord("confirm"), ok := GetCoord("ok")
	done := 0
	where := ""
	try {
		for pi, pg in SelectedPages() {
			SwitchPage("enhance", pg)
			SleepCheck(step)
			slot := (pi = 1) ? ToInt(edStartSlot.Value) : 1 ; "从第几格开始" 只对第一页有效
			while (Running && slot <= TOTAL_SLOTS) {
				where := PageNames[pg] " 页 第 " slot " 格"
				p := SlotPos(slot)
				; 水晶 / 红宝那两格, 以及空格子 (没有道具) 直接跳过
				if (IsMaterialSlot(slot) || SlotIsEmpty(p)) {
					slot++
					continue
				}
				SetStatus(where " / " TOTAL_SLOTS ":  强化中…   (按 " StopKey " 停止)")
				; 物品 / 水晶 / 红宝用右键, 确认 / OK 用左键
				for act in [[p, BTN_RIGHT], [crystal, BTN_RIGHT], [confirm, BTN_LEFT], [ruby, BTN_RIGHT]
					, [confirm, BTN_LEFT], [ok, BTN_LEFT], [confirm, BTN_LEFT]] {
					if !Running
						break
					ClickPos(act[1], act[2])
					SleepCheck(step)
				}
				; 等到侦测到 GEM 或 空 其中一张图
				SetStatus(where " / " TOTAL_SLOTS ":  等待 GEM / 空 图片…   (按 " StopKey " 停止)")
				found := ""
				d := GetCoord("detect")
				while (Running && found = "") {
					if FindImageAround(Images["gem"].file, d.x, d.y, DETECT_MARGIN, &gx, &gy)
						found := "gem"
					else if FindImageAround(Images["empty"].file, d.x, d.y, DETECT_MARGIN, &ex, &ey)
						found := "empty"
					else
						SleepCheck(100)
				}
				if !Running
					break
				; GEM 要从图片中心往上拖走; 空 就直接下一格
				if (found = "gem") {
					SleepCheck(step)
					DragUp(gx, gy, ToInt(edDrag.Value))
					SleepCheck(step)
				}
				done++
				slot++
			}
			if !Running
				break
		}
	} catch as e {
		MsgBox("运行出错: " e.Message, "Biubiu强化小工具", "Icon!")
		Running := false
	}
	if Running
		SetStatus("全部完成! 共强化 " done " 格")
	else
		SetStatus("已停止在 " where "  (本次完成 " done " 格)")
	Running := false
}

ClickPos(p, btn := 0) { ; btn: BTN_LEFT / BTN_RIGHT
	MoveTo(p.x, p.y)
	AHI.SendMouseButtonEvent(MouseId, btn, 1)
	Sleep HOLD_MS
	AHI.SendMouseButtonEvent(MouseId, btn, 0)
}

; 用 Interception 相对移动把鼠标移到屏幕坐标 (x, y)
; 远距离每次走剩余距离的一半, 避免系统鼠标加速造成来回过冲; 最后逐像素修正
; settle: 到位后再等多少毫秒 (点击前让游戏反应过来; 拖拽中途不需要)
MoveTo(x, y, settle := 20) {
	Loop 60 {
		MouseGetPos(&cx, &cy)
		dx := x - cx, dy := y - cy
		if (dx = 0 && dy = 0)
			break
		mx := Abs(dx) > 2 ? Round(dx / 2) : (dx > 0) - (dx < 0)
		my := Abs(dy) > 2 ? Round(dy / 2) : (dy > 0) - (dy < 0)
		AHI.SendMouseMove(MouseId, mx, my)
		Sleep 2
	}
	if settle
		Sleep settle
}

; 左键按住 (x, y), 每次往上移 DRAG_STEP 像素, 一共拖 dist 像素后松开
DragUp(x, y, dist) {
	MoveTo(x, y)
	AHI.SendMouseButtonEvent(MouseId, BTN_LEFT, 1)
	Sleep DRAG_HOLD
	moved := 0
	while (moved < dist) {
		moved := Min(moved + DRAG_STEP, dist)
		MoveTo(x, y - moved, 0)
		Sleep DRAG_DELAY
	}
	Sleep DRAG_HOLD
	AHI.SendMouseButtonEvent(MouseId, BTN_LEFT, 0)
}

; 在 (x, y) 附近找图: 范围 = 以 (x, y) 为中心, 图片大小再往外扩 margin 像素; 找到时 cx, cy 返回图片中心
FindImageAround(file, x, y, margin, &cx, &cy) {
	size := ImageSize(file)
	mx := size.w // 2 + margin, my := size.h // 2 + margin
	return FindImageIn(file, x - mx, y - my, x + mx, y + my, &cx, &cy)
}

; 在矩形 (x1, y1) - (x2, y2) 内找图; 找到时 cx, cy 返回图片中心
FindImageIn(file, x1, y1, x2, y2, &cx, &cy) {
	size := ImageSize(file)
	if !ImageSearch(&fx, &fy, x1, y1, x2, y2, "*" ToInt(edTol.Value) " " file)
		return false
	cx := fx + size.w // 2
	cy := fy + size.h // 2
	return true
}

SleepCheck(ms) {
	end := A_TickCount + ms
	while (Running && A_TickCount < end)
		Sleep Min(10, end - A_TickCount)
}

ToInt(v) => IsInteger(Trim(v)) ? Integer(Trim(v)) : 0

; ---------------- 坐标 ----------------
HasCoord(name) => IsInteger(Trim(Coords[name].x.Value)) && IsInteger(Trim(Coords[name].y.Value))

GetCoord(name) {
	return {x: ToInt(Coords[name].x.Value), y: ToInt(Coords[name].y.Value)}
}

; 由该模式的第 1 格 (左上) 和第 64 格 (右下) 按等距算出第 i 格的中心
SlotPos(i, mode := "enhance") {
	a := GetCoord(GridCoords[mode][1]), b := GetCoord(GridCoords[mode][2])
	col := Mod(i - 1, 8), row := (i - 1) // 8
	return {x: Round(a.x + (b.x - a.x) * col / 7), y: Round(a.y + (b.y - a.y) * row / 7)}
}

StartPick(name, *) {
	global PickName := name
	Hotkey("F9", DoPick, "On")
	SetStatus("把鼠标移到「" CoordLabels[name] "」的位置, 按 F9 记录")
}

DoPick(*) {
	global PickName
	Hotkey("F9", "Off")
	if (PickName = "")
		return
	MouseGetPos(&x, &y)
	Coords[PickName].x.Value := x
	Coords[PickName].y.Value := y
	SetStatus(CoordLabels[PickName] " 坐标已设为 " x ", " y)
	PickName := ""
}

; 在屏幕上把所有坐标标出来 4 秒: 红 = 强化格子, 蓝 = 水晶, 紫 = 红宝, 橙 = 贩卖格子, 绿 = 其他坐标
ShowCoords(*) {
	static ov := 0
	if ov
		try ov.Destroy()
	vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
	ov := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20")
	ov.BackColor := "010101"
	ov.SetFont("s8 Bold", "Microsoft YaHei UI")
	marks := 0
	if (HasCoord("grid1") && HasCoord("grid64")) {
		Loop 64 {
			p := SlotPos(A_Index)
			if (A_Index = ToInt(edCrystal.Value))
				Mark(ov, p.x - vx, p.y - vy, "00A0FF", "水晶")
			else if (A_Index = ToInt(edRuby.Value))
				Mark(ov, p.x - vx, p.y - vy, "FF40FF", "红宝")
			else
				Mark(ov, p.x - vx, p.y - vy, "FF3030", A_Index)
		}
		marks += 64
	}
	if (HasCoord("sellGrid1") && HasCoord("sellGrid64")) {
		Loop 64 {
			p := SlotPos(A_Index, "sell")
			Mark(ov, p.x - vx, p.y - vy, "FFA000", A_Index)
		}
		marks += 64
	}
	for name in ["confirm", "ok", "detect", "enh1", "enh2", "sellConfirm", "sell1", "sell2"] {
		if HasCoord(name) {
			p := GetCoord(name)
			Mark(ov, p.x - vx, p.y - vy, "30D030", CoordLabels[name])
			marks++
		}
	}
	if !marks {
		ov.Destroy()
		ov := 0
		SetStatus("还没有设置任何坐标")
		return
	}
	ov.Show(Format("x{} y{} w{} h{} NA", vx, vy, vw, vh))
	WinSetTransColor("010101", ov)
	SetTimer(DestroyQuiet.Bind(ov), -4000)
	SetStatus("已在屏幕上标出坐标 (4 秒)")
}

DestroyQuiet(gui) {
	try gui.Destroy() ; 可能已经被再次点「检查」时关掉了
}

Mark(gui, x, y, color, label) {
	gui.Add("Text", Format("x{} y{} w10 h10 Background{}", x - 5, y - 5, color))
	gui.Add("Text", Format("x{} y{} c{} BackgroundTrans", x + 7, y - 9, color), label)
}

; ---------------- 侦测图片 ----------------
ShotImage(key, *) {
	img := Images[key]
	g.Hide()
	Sleep 200
	try r := CaptureRegion(img.file, "框选「" img.label "」图片")
	catch as e {
		r := ""
		MsgBox("截图失败: " e.Message, "Biubiu强化小工具", "Icon!")
	}
	g.Show()
	if !r
		return
	; GEM / 空 截图时, 侦测位置还没设置就默认用截图区域的中心
	if ((key = "gem" || key = "empty") && !HasCoord("detect")) {
		Coords["detect"].x.Value := r.x + r.w // 2
		Coords["detect"].y.Value := r.y + r.h // 2
	}
	UpdatePreviews()
	SetStatus("「" img.label "」图片已保存")
}

UpdatePreviews() {
	for key, img in Images {
		if FileExist(img.file) {
			sz := GetImageSize(img.file)
			img.pic.Value := "*w34 *h34 " img.file
			img.txt.Value := "已截图 (" sz.w " x " sz.h ")"
		} else {
			img.txt.Value := "未截图"
		}
	}
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

; ---------------- 录键 ----------------
; 热键框获得焦点后, 读取下一次按下的键 (支持 ctrl/alt/shift/win 组合); Esc 取消, 10 秒无操作自动取消
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

ApplyHotkeys() {
	global StartKey, SellKey, StopKey
	s := Trim(edStart.Value), b := Trim(edSell.Value), t := Trim(edStop.Value)
	if (s = StartKey && b = SellKey && t = StopKey)
		return
	if (s = b) {
		MsgBox("强化和贩卖的开始键不能设成同一个键", "Biubiu强化小工具", "Icon!")
		edStart.Value := StartKey, edSell.Value := SellKey, edStop.Value := StopKey
		return
	}
	for k in [StartKey, SellKey, StopKey]
		if (k != "")
			try Hotkey(ToHotkey(k), "Off")
	try {
		Hotkey(ToHotkey(s), HotkeyStart.Bind("enhance", s = t), "On")
		Hotkey(ToHotkey(b), HotkeyStart.Bind("sell", b = t), "On")
		if (t != s && t != b)
			Hotkey(ToHotkey(t), StopRun, "On")
	} catch as e {
		MsgBox("热键设置无效: " e.Message, "Biubiu强化小工具", "Icon!")
	}
	StartKey := s, SellKey := b, StopKey := t
	if !Running
		SetStatus("")
}

SetStatus(text) {
	if (text = "")
		text := "按 " StartKey " 开始强化 / " SellKey " 开始贩卖 / " StopKey " 停止"
	txtStatus.Value := text
}

; ---------------- 配置 ----------------
SaveConfig(*) {
	ApplyHotkeys()
	IniWrite(edStart.Value, CfgFile, "Main", "Start")
	IniWrite(edSell.Value, CfgFile, "Main", "Sell")
	IniWrite(edStop.Value, CfgFile, "Main", "Stop")
	IniWrite(ToInt(edStep.Value), CfgFile, "Main", "Step")
	IniWrite(ToInt(edStartSlot.Value), CfgFile, "Main", "StartSlot")
	IniWrite(ToInt(edTol.Value), CfgFile, "Main", "Tolerance")
	IniWrite(ToInt(edDrag.Value), CfgFile, "Main", "DragDist")
	IniWrite(ToInt(edCrystal.Value), CfgFile, "Main", "CrystalSlot")
	IniWrite(ToInt(edRuby.Value), CfgFile, "Main", "RubySlot")
	IniWrite(chkP1.Value, CfgFile, "Main", "Page1")
	IniWrite(chkP2.Value, CfgFile, "Main", "Page2")
	for name in CoordNames
		IniWrite(Trim(Coords[name].x.Value) "," Trim(Coords[name].y.Value), CfgFile, "Coords", name)
	SetStatus("设置已保存")
}

LoadConfig(ctrl := 0, *) {
	if !FileExist(CfgFile) {
		if ctrl
			MsgBox("还没有保存过设置", "Biubiu强化小工具")
		return
	}
	edStart.Value := IniRead(CfgFile, "Main", "Start", "F7")
	edSell.Value := IniRead(CfgFile, "Main", "Sell", "F6")
	edStop.Value := IniRead(CfgFile, "Main", "Stop", "F8")
	edStep.Value := IniRead(CfgFile, "Main", "Step", 300)
	edStartSlot.Value := IniRead(CfgFile, "Main", "StartSlot", 1)
	edTol.Value := IniRead(CfgFile, "Main", "Tolerance", 30)
	edDrag.Value := IniRead(CfgFile, "Main", "DragDist", 100)
	edCrystal.Value := IniRead(CfgFile, "Main", "CrystalSlot", 63)
	edRuby.Value := IniRead(CfgFile, "Main", "RubySlot", 64)
	chkP1.Value := ToInt(IniRead(CfgFile, "Main", "Page1", 1))
	chkP2.Value := ToInt(IniRead(CfgFile, "Main", "Page2", 1))
	for name in CoordNames {
		f := StrSplit(IniRead(CfgFile, "Coords", name, ","), ",")
		if (f.Length = 2)
			Coords[name].x.Value := f[1], Coords[name].y.Value := f[2]
	}
	if ctrl {
		ApplyHotkeys()
		UpdatePreviews()
		SetStatus("已读取配置")
	}
}

; ---------------- 驱动 ----------------
; 检测不到设备时调用: 驱动没装 -> 询问安装; 装了但没生效 -> 提示重启
CheckDriver() {
	title := "Biubiu强化小工具"
	if DriverInstalled() {
		if (MsgBox("Interception 驱动已经安装, 但还没有生效。`n需要重启电脑后才能使用, 现在重启吗?", title, "YesNo Icon!") = "Yes")
			Shutdown 2
		return
	}
	if (MsgBox("没有检测到 Interception 驱动 (本工具需要它来模拟鼠标)。`n`n现在安装吗? 安装后需要重启电脑。", title, "YesNo Icon?") != "Yes")
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
