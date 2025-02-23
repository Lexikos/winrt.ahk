#include testcase.ahk
#include ..\winrt.ahk
#include ..\AppPackage.ahk
; #include ..\AppPackage-Win11.ahk
; #include ..\AppRuntimeBootstrap.ahk


TestCase "Load Windows App Runtime", () {
    package_name := UseWindowsAppRuntime('1.6')
    OutputDebug 'Added dependency on package "' package_name '"`n'
}


TestCase "Microsoft.UI.Windowing", () {
    AppWindow := WinRT('Microsoft.UI.Windowing.AppWindow')

    wid := WinRT('Microsoft.UI.WindowId')()
    wid.Value := A_ScriptHwnd
    my := AppWindow.GetFromWindowId(wid)
    
    equals Type(my), 'Microsoft.UI.Windowing.AppWindow'
    equals my.Title, WinGetTitle(A_ScriptHwnd)
    equals Type(my.TitleBar), 'Microsoft.UI.Windowing.AppWindowTitleBar'
    
    ; TODO: proper generic IReference<> handling so we can pass a Color
    ; PropertyValue.CreateUInt32() returns an IReference<UInt32>,
    ; which effectively has binary compatibility with IReference<Color>.
    ; bc := WinRT('Windows.Foundation.PropertyValue').CreateUInt32(0)
    ; my.TitleBar.BackgroundColor := bc
    ; my.TitleBar.ExtendsContentIntoTitleBar := true
    ; my.TitleBar.PreferredHeightOption := 'Tall'
    ; my.Show()
}

