#include testcase.ahk
#include ..\winrt.ahk


TestCase "Load Windows App Runtime", () {
    ; Load the bootstrapper. Unpackaged apps are expected to be distributed
    ; with this, but it can also be found in an installed package. This one
    ; likely always exists on Windows 11 systems (and never on 10):
    ;DllCall("LoadLibrary", 'str', "C:\Windows\SystemApps\Microsoft.WindowsAppRuntime.CBS_8wekyb3d8bbwe\Microsoft.WindowsAppRuntime.Bootstrap.dll", 'ptr') || Throw(OSError())

    ; Use the bootstrapper to load the Windows App Runtime v1.6 packages.
    ; This requires the DDLM package to be also present, even though packaged
    ; apps don't require it (so it might not be installed, but installing the
    ; App SDK runtime should fix that).
    ; MddBootstrapInitializeOptions_OnNoMatch_ShowUI := 8
    ;DllCall("Microsoft.WindowsAppRuntime.Bootstrap.dll\MddBootstrapInitialize2", 'uint', 0x00010006, 'ptr', 0, 'int64', 0, 'int', 8, 'hresult')
    
    ; Requires Windows 11 (but does not require the DDLM package):
    DllCall("KernelBase.dll\TryCreatePackageDependency"
        , 'ptr', 0 ; user context = caller
        ; Installed under A_WinDir (a system package File Explorer depends on):
        ; , 'str', "Microsoft.WindowsAppRuntime.CBS_8wekyb3d8bbwe"
        ; Installed under A_ProgramFiles:
        , 'str', "Microsoft.WindowsAppRuntime.1.6_8wekyb3d8bbwe"
        , 'int64', 0 ;(1 << 48) | (6 << 32) ; 1.6.0.0 - no need to specify because it's in the package name.
        , 'int', 0 ; architecture = unspecified (works for x86, x64 and probably ARM)
        , 'int', 0 ; lifetimeKind = Process
        , 'ptr', 0 ; lifetimeArtifact must be NULL when lifetimeKind = Process
        , 'int', 0 ; options = None
        , 'ptr*', &pdid := 0, 'hresult')
    
    DllCall("KernelBase.dll\AddPackageDependency"
        , 'ptr', pdid
        , 'int', 0 ; rank - arbitrary and irrelevant if this is the only package?
        , 'int', 0 ; options = None
        , 'ptr*', &pdependency_context := 0 ; Output used with RemovePackageDependency (not necessary).
        , 'ptr*', &pfullname := 0
        , 'hresult')
    
    OutputDebug 'Added dependency on package "' StrGet(pfullname) '"`n'
    ; "The caller is responsible for freeing this resource once it is no longer needed by calling HeapFree."
    ; Umm... what heap?  Apparently the process heap.
    heap := DllCall("GetProcessHeap", 'ptr')
    DllCall("HeapFree", 'ptr', heap, 'uint', 0, 'ptr', pdid) || throw(OSError())
    DllCall("HeapFree", 'ptr', heap, 'uint', 0, 'ptr', pfullname) || throw(OSError())
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

