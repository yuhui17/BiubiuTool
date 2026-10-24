/*
Interception 驱动安装 / 卸载工具 (Biubiu小工具 需要这个驱动)
- 编译成 exe 后会内置 install-interception.exe, 单独拷给别人就能用
- 安装或卸载后都需要重启电脑才会生效
*/
#Requires AutoHotkey v2.0
#SingleInstance Force

; 编译成 exe 时的设置 (Ahk2Exe)
;@Ahk2Exe-SetMainIcon icon.ico
;@Ahk2Exe-SetName Interception驱动安装
;@Ahk2Exe-SetDescription Interception驱动安装
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-UpdateManifest 1

; 安装驱动需要管理员权限
if !A_IsAdmin {
	try {
		if A_IsCompiled
			Run('*RunAs "' A_ScriptFullPath '" /restart')
		else
			Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
	}
	ExitApp
}

Title := "Interception 驱动安装"
Installer := A_ScriptDir "\Lib\install-interception.exe"
if A_IsCompiled {
	Installer := A_Temp "\install-interception.exe"
	FileInstall("Lib\install-interception.exe", Installer, 1)
}
if FileExist(A_ScriptDir "\icon.png")
	TraySetIcon(A_ScriptDir "\icon.png")

g := Gui(, Title)
g.SetFont("s10", "Microsoft YaHei UI")
g.OnEvent("Close", (*) => ExitApp())
txtState := g.Add("Text", "x20 y16 w330 h48")
g.Add("Button", "x20 y72 w100 h32", "安装驱动").OnEvent("Click", (*) => DoAction("install"))
g.Add("Button", "x135 y72 w100 h32", "卸载驱动").OnEvent("Click", (*) => DoAction("uninstall"))
g.Add("Button", "x250 y72 w100 h32", "退出").OnEvent("Click", (*) => ExitApp())
UpdateState()
g.Show("w370 h122")
return

UpdateState() {
	if DriverInstalled()
		txtState.Value := "当前状态: 已安装`n(刚安装完的话, 需要重启电脑才会生效)"
	else
		txtState.Value := "当前状态: 未安装`nBiubiu小工具 需要这个驱动才能模拟键盘鼠标"
}

DoAction(act) {
	if (act = "install" && DriverInstalled()) {
		MsgBox("驱动已经安装过了。`n如果 Biubiu小工具 还是检测不到键盘鼠标, 请重启电脑。", Title, "Iconi")
		return
	}
	if (act = "uninstall") {
		if !DriverInstalled() {
			MsgBox("驱动没有安装, 不需要卸载。", Title, "Iconi")
			return
		}
		if (MsgBox("确定要卸载 Interception 驱动吗?`n卸载后 Biubiu小工具 将无法使用。", Title, "YesNo Icon!") != "Yes")
			return
	}
	if !FileExist(Installer) {
		MsgBox("找不到驱动安装程序: " Installer, Title, "Icon!")
		return
	}
	try RunWait('"' Installer '" /' act, , "Hide")
	catch as e {
		MsgBox("运行安装程序失败: " e.Message, Title, "Icon!")
		return
	}
	UpdateState()
	if (DriverInstalled() != (act = "install")) {
		MsgBox((act = "install" ? "安装" : "卸载") "失败, 请重试。", Title, "Icon!")
		return
	}
	if (MsgBox((act = "install" ? "驱动安装完成!" : "驱动卸载完成!") "`n需要重启电脑后才会生效, 现在重启吗?", Title, "YesNo Iconi") = "Yes")
		Shutdown 2
}

; Interception 安装后会在键盘/鼠标设备类的 UpperFilters 里注册 keyboard / mouse 过滤驱动
DriverInstalled() {
	static cls := "HKLM\SYSTEM\CurrentControlSet\Control\Class\"
	kb := RegRead(cls "{4D36E96B-E325-11CE-BFC1-08002BE10318}", "UpperFilters", "")
	ms := RegRead(cls "{4D36E96F-E325-11CE-BFC1-08002BE10318}", "UpperFilters", "")
	return InStr("`n" kb "`n", "`nkeyboard`n") && InStr("`n" ms "`n", "`nmouse`n")
}
