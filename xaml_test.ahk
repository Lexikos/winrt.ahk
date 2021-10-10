#include winrt.ahk

; DllCall(SetPreferredAppMode, "int", 0)

make_dark(g, dark) {
    static uxtheme := DllCall("GetModuleHandle", "str", "uxtheme", "ptr")
    static SetPreferredAppMode := DllCall("GetProcAddress", "ptr", uxtheme, "ptr", 135, "ptr")
    static AllowDarkModeForWindow := DllCall("GetProcAddress", "ptr", uxtheme, "ptr", 133, "ptr")
    if VerCompare(A_OSVersion, "10.0.17763") >= 0 {
        attr := 19
        if VerCompare(A_OSVersion, "10.0.18985") >= 0 {
            attr := 20
            if AllowDarkModeForWindow ; Not a perfect check since it could be some other function.
                DllCall(AllowDarkModeForWindow, "ptr", g.hwnd, "int", dark)
            ; DllCall("uxtheme\SetWindowTheme", "ptr", g.hwnd, "str", "DarkMode_Explorer", "ptr", 0)
        }
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.hwnd, "int", attr, "int*", dark, "int", 4)
    }
}

XamlTest()

XamlTest() {
    ; static wxm := WinRT("Windows.UI.Xaml.Hosting.WindowsXamlManager").InitializeForCurrentThread()
    dwxs := WinRT("Windows.UI.Xaml.Hosting.DesktopWindowXamlSource")(0, Buffer(8, 0))
    dwxsn := ComObjQuery(dwxs, "{3cbcf1bf-2f76-4e9c-96ab-e84b37972554}")
    wnd := Gui("-DPIScale")
    make_dark(wnd, true)
    wnd.Add("Text", "w0 h0") ; Add a dummy control to work around keyboard input issues.
    wnd.dwxs := dwxs
    ; wnd := {hwnd: A_ScriptHwnd}
    ComCall(AttachToWindow := 3, dwxsn, "ptr", wnd.hwnd)
    ComCall(get_WindowHandle := 4, dwxsn, "ptr*", &hostwnd := 0)
    wnd.xamlwnd := hostwnd
    ; Must use SetWindowPos! Does not work with ControlMove+ControlShow!
    DllCall("SetWindowPos", "ptr", hostwnd, "ptr", 0, "int", 0, "int", 0, "int", 600, "int", 200, "int", 0x40)
    
    dwxs.Content := WinRT("Windows.UI.Xaml.Markup.XamlReader").Load(Format("
    (
        <StackPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="10">
            <TextBlock Text="AutoHotkey version: ">
                <Run Text="{1}" Foreground="#0080ff"/>
            </TextBlock>
            <TextBox/>
        </StackPanel>
    )", A_AhkVersion))
    
    ;itb := ComObjQuery(container, "{676D0BE9-B65C-41C6-BA40-58CF87F201C1}")
    ; NumPut("float", 0, "float", 0, "float", 600, "float", 400, rect := Buffer(16))
    ; ComCall(92, itb, "ptr", rect)
    ; ComCall(92, itb, "float", 0, "float", 0, "float", 600, "float", 400)
    
    ; ListVars
    OnMessage(0x100, XamlKeyDown)
    wnd.Show("w600 h200")
    
    dwxs.NavigateFocus(
        WinRT("Windows.UI.Xaml.Hosting.XamlSourceFocusNavigationRequest")(First := 3))
}

XamlKeyDown(wParam, lParam, nmsg, hwnd) {
    if !(wnd := GuiFromHwnd(hwnd, true)) || !wnd.hasProp('dwxs')
        return
    if !native2 := ComObjQuery(wnd.dwxs, "{e3dcd8c7-3057-4692-99c3-7b7720afda31}")
        return
    kmsg := Buffer(48, 0)
    NumPut("ptr", hwnd, "ptr", nmsg, "ptr", wParam, "ptr", lParam
        , "uint", A_EventInfo, kmsg)
    ; IDesktopWindowXamlSourceNative2::PreTranslateMessage
    ComCall(5, native2, "ptr", kmsg, "int*", &processed:=false)
    if processed
        return 0
    if !wnd.dwxs.HasFocus || wParam < 0x20
        return
    keybuf := Buffer(256, 0)
    DllCall("GetKeyboardState", "ptr", keybuf)
    n := DllCall("ToUnicode", "uint", wParam, "uint", (lParam >> 16) & 0xff
        , "ptr", keybuf, "uint*", &c:=0, "int", 2, "uint", 0)
    if n {
        if n > 0
            SendMessage(0x102, c & 0xffff, lParam, hwnd)
        if n > 1
            SendMessage(0x102, (c >> 16) & 0xffff, lParam, hwnd)
        return 0
    }
}