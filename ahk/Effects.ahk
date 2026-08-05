#Requires AutoHotkey v2.0
#SingleInstance Off
global BlockedKeys := []
global BlockingLmb := false
global MouseMovementBlocked := false
global HeldKeys := Map()

OnExit((*) => CleanupEffect())
Hotkey("^+F12", EmergencyExit)

effectId := GetArg("--effect")
if effectId = "" {
    MsgBox("Этот скрипт запускается приложением Chaos Link Agent.")
    ExitApp
}
durationArg := GetArg("--duration")
seedArg := GetArg("--seed")
soundPath := GetArg("--sound")
imagePath := GetArg("--image")
durationMs := durationArg = "" ? 0 : Integer(durationArg)
seed := seedArg = "" ? 0 : Integer(seedArg)
ExecuteEffect(effectId, durationMs, seed, soundPath, imagePath)
ExitApp(0)

ExecuteEffect(effectId, durationMs, seed, soundPath, imagePath) {
    try {
        switch effectId {
            case "release_all": ReleaseEverything()
            case "knife": PressKnife()
            case "reload": Send("r")
            case "jump": Send("{Space}")
            case "drop_weapon": Send("g")
            case "mouse_jerk": MouseJerk(seed)
            case "hold_ctrl": HoldKey("Ctrl", Max(durationMs, 1000))
            case "block_wasd": BlockWasd(Max(durationMs, 1000))
            case "block_lmb": BlockLeftMouse(Max(durationMs, 1000))
            case "grenade_feet": GrenadeAtFeet()
            case "flash": FlashOverlay(Max(durationMs, 1000))
            case "screamer": ScreamerOverlay(Max(durationMs, 1000), soundPath, imagePath)
            default: throw Error("Эффект отсутствует в AHK")
        }
        WriteLog("Выполнено: " effectId)
    } catch as error {
        ReleaseEverything()
        WriteLog(error.Message)
        ExitApp(1)
    }
}

WriteLog(message) {
    try FileAppend(message, "*")
}

HoldKey(key, durationMs) {
    global HeldKeys
    HeldKeys[key] := true
    Send("{" key " down}")
    try Sleep(durationMs)
    finally {
        Send("{" key " up}")
        HeldKeys.Delete(key)
    }
}

PressKnife() {
    cs2Window := WinExist("ahk_exe cs2.exe")
    if !cs2Window
        throw Error("Процесс cs2.exe не найден")

    if !WinActive("ahk_id " cs2Window) {
        WinActivate("ahk_id " cs2Window)
        if !WinWaitActive("ahk_id " cs2Window, , 2)
            throw Error("Не удалось активировать окно CS2")
    }

    SendInput("{vk33sc004 down}")
    Sleep(100)
    SendInput("{vk33sc004 up}")
}

MouseJerk(seed) {
    x := Mod(Abs(seed), 2) = 0 ? 0 : (Mod(Abs(seed), 1000) + 1400)
    y := Mod(Abs(seed // 7), 2) = 0 ? -(Mod(Abs(seed), 900) + 1100) : (Mod(Abs(seed), 900) + 1100)
    if x = 0
        x := -(Mod(Abs(seed), 1000) + 1400)
    DllCall("mouse_event", "UInt", 0x0001, "Int", x, "Int", y, "UInt", 0, "UPtr", 0)
}

BlockWasd(durationMs) {
    EnableKeyBlock(["w", "a", "s", "d"])
    try Sleep(durationMs)
    finally DisableKeyBlock()
}

Swallow(*) {
}

EnableKeyBlock(keys) {
    global BlockedKeys
    if BlockedKeys.Length > 0
        return
    BlockedKeys := keys.Clone()
    for key in BlockedKeys {
        Hotkey("*" key, Swallow, "On")
        Hotkey("*" key " up", Swallow, "On")
        Send("{" key " up}")
    }
}

DisableKeyBlock() {
    global BlockedKeys
    if BlockedKeys.Length = 0
        return
    for key in BlockedKeys {
        try Hotkey("*" key, "Off")
        try Hotkey("*" key " up", "Off")
        try Send("{" key " up}")
    }
    BlockedKeys := []
}

BlockLeftMouse(durationMs) {
    global BlockingLmb
    BlockingLmb := true
    SendInput("{LButton down}")
    try Sleep(durationMs)
    finally DisableLeftMouseBlock()
}

DisableLeftMouseBlock() {
    global BlockingLmb
    if !BlockingLmb
        return
    try SendInput("{LButton up}")
    BlockingLmb := false
}

SetMouseMovementBlocked(blocked) {
    global MouseMovementBlocked
    if blocked {
        BlockInput("MouseMove")
        MouseMovementBlocked := true
    } else if MouseMovementBlocked {
        BlockInput("MouseMoveOff")
        MouseMovementBlocked := false
    }
}

GrenadeAtFeet() {
    global HeldKeys
    try {
        ; 1. Take the grenade first and give CS2 enough time to equip it.
        SendInput("4")
        Sleep(1800)

        ; 2. Block movement keys and physical camera movement, then look down.
        EnableKeyBlock(["w", "a", "s", "d", "Space", "Shift", "q", "e", "r", "g", "1", "2", "3", "4", "5"])
        SetMouseMovementBlocked(true)
        Loop 4 {
            DllCall("mouse_event", "UInt", 0x0001, "Int", 0, "Int", 2200, "UInt", 0, "UPtr", 0)
            Sleep(35)
        }
        Sleep(150)

        ; 3. Crouch for two full seconds. The mouse click is deliberately last.
        HeldKeys["Ctrl"] := true
        SendInput("{Ctrl down}")
        Sleep(2000)
        SendInput("{RButton down}")
        Sleep(140)
        SendInput("{RButton up}")
        Sleep(150)
    } finally {
        try SendInput("{RButton up}")
        try SendInput("{Ctrl up}")
        try HeldKeys.Delete("Ctrl")
        SetMouseMovementBlocked(false)
        DisableKeyBlock()
    }
}

FlashOverlay(durationMs) {
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow")
    overlay.BackColor := "FFFFFF"
    overlay.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " NoActivate")
    SoundBeep(1400, 120)
    try Sleep(durationMs)
    finally overlay.Destroy()
}

ScreamerOverlay(durationMs, soundPath, imagePath) {
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow")
    overlay.BackColor := "090909"
    imageAdded := false
    if imagePath != "" && FileExist(imagePath) {
        extension := StrLower(RegExReplace(imagePath, "^.*\."))
        if extension = "gif"
            imageAdded := AddAnimatedGif(overlay, imagePath)
        if !imageAdded {
            overlay.AddPicture("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight, imagePath)
            imageAdded := true
        }
    }
    if !imageAdded {
        overlay.SetFont("s180 cF03A47 Bold", "Segoe UI")
        overlay.AddText("Center x0 y" Floor(A_ScreenHeight / 2 - 160) " w" A_ScreenWidth, "!")
    }
    overlay.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " NoActivate")
    if soundPath != "" && FileExist(soundPath)
        SoundPlay(soundPath)
    else {
        SoundBeep(350, 300)
        SoundBeep(1700, 240)
    }
    try Sleep(durationMs)
    finally overlay.Destroy()
}

AddAnimatedGif(overlay, imagePath) {
    try {
        browser := overlay.AddActiveX("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight, "Shell.Explorer").Value
        browser.Silent := true
        browser.Navigate("about:blank")
        deadline := A_TickCount + 1500
        while browser.ReadyState != 4 && A_TickCount < deadline
            Sleep(10)
        imageUrl := PathToFileUrl(imagePath)
        html := "<!doctype html><html><head><meta http-equiv='X-UA-Compatible' content='IE=edge'><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#090909}img{width:100%;height:100%;object-fit:cover}</style></head><body><img src='" imageUrl "'></body></html>"
        browser.Document.Open()
        browser.Document.Write(html)
        browser.Document.Close()
        return true
    } catch {
        return false
    }
}

PathToFileUrl(path) {
    path := StrReplace(path, "%", "%25")
    path := StrReplace(path, " ", "%20")
    path := StrReplace(path, "#", "%23")
    path := StrReplace(path, "&", "%26")
    path := StrReplace(path, "'", "%27")
    return "file:///" StrReplace(path, "\", "/")
}

CleanupEffect() {
    global HeldKeys
    try DisableKeyBlock()
    try DisableLeftMouseBlock()
    try SetMouseMovementBlocked(false)
    for key in HeldKeys.Clone()
        try Send("{" key " up}")
    HeldKeys.Clear()
}

ReleaseEverything() {
    CleanupEffect()
    for key in ["Ctrl", "Shift", "Alt", "Space", "LButton", "RButton", "w", "a", "s", "d"]
        try Send("{" key " up}")
}

EmergencyExit(*) {
    ReleaseEverything()
    ExitApp(2)
}

GetArg(name) {
    for index, arg in A_Args {
        if arg = name && index < A_Args.Length
            return A_Args[index + 1]
    }
    return ""
}
