/*
Minimal loader for the Windows App Runtime.

Requires:
  - Microsoft.WindowsAppRuntime.Bootstrap.dll
  - Microsoft.WinAppRuntime.DDLM.* package installed.


# Notes about requirements

The DDLM package is installed by the WindowsAppRuntime installer, but otherwise
might not be present even if other apps which require the runtime are installed.

The Bootstrap DLL is not included in the runtime installer, but can be found in
the SDK (or the Microsoft.WindowsAppRuntime.CBS package on Windows 11).

Other methods of loading the app runtime do not require the Bootstrap DLL or DDLM
package, and can use whatever runtime is installed.  See AppPackage.ahk.


# Notes about usage

If the DLL is not in the executable directory or search path, simply load it by
full path before calling UseWindowsAppRuntime.  This is not necessary if the DLL
is copied into the executable directory (where AutoHotkey.exe or the compiled
script resides).

This file exists mainly for comparison and informational purposes.  If you choose
to use this method, feel free to use the DllCall directly in your script.

*/

; #DllLoad Microsoft.WindowsAppRuntime.Bootstrap.dll

/**
 * Load the Windows App Runtime and add it to the package graph of the current process.
 * @param majorMinorVersion The exact major and minor version to load, such as `"1.6"`.
 * @returns {String} The full package name of the runtime.
 */
UseWindowsAppRuntime(majorMinorVersion) {
    mm := StrSplit(majorMinorVersion, '.')
    ; MddBootstrapInitializeOptions_OnNoMatch_ShowUI := 8
    DllCall("Microsoft.WindowsAppRuntime.Bootstrap.dll\MddBootstrapInitialize2"
        , 'uint', (mm[1] << 16) | mm[2], 'ptr', 0, 'int64', 0, 'int', 8, 'hresult')
}
    
