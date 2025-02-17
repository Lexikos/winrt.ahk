#include testcase.ahk
#include ..\winmd.ahk

; These tests expect Windows.Win32.winmd in the parent directory.

TestCase "Gdip", () {
    mdm := mdModule.Open("..\Windows.Win32.winmd")
    
    td := mdm.FindTypeDefByName('Windows.Win32.Graphics.GdiPlus.Apis')
    for md in mdm.EnumMethods(td) {
        mp := mdm.GetMethodProps(md)
        if mp.name = 'GdipGetImageWidth' {
            argtypes := mdSignatureDecoder(mp.sig).Decode()
            equals typeRefName(argtypes[1]), 'Windows.Win32.Graphics.GdiPlus.Status'
            assert argtypes[2] is mdModifier.Ptr
            if argtypes[2].t.Type = 'TypeRef' ; Older metadata version
                equals typeRefName(argtypes[2].t), 'Windows.Win32.Graphics.GdiPlus.GpImage'
            else ; Win32metadata 63.0.31-preview
                equals mdm.GetTypeDefProps(argtypes[2].t).name, 'Windows.Win32.Graphics.GdiPlus.GpImage'
            assert argtypes[3] is mdModifier.Ptr
            equals argtypes[3].t, 'UInt32'
            
            tdStatus := mdm.FindTypeDefByName('Windows.Win32.Graphics.GdiPlus.Status')
            tdp := mdm.GetTypeDefProps(tdStatus)
            equals typeRefName(tdp.extends), 'System.Enum'
            for fd in mdm.EnumFields(tdStatus) {
                fp := mdm.GetFieldProps(fd)
                if fp.name = 'Win32Error' { ; 7
                    equals fp.flags & 0x50, 0x50 ; static literal
                    equals mdGetFieldConstant(mdm, fd), 7
                }
            }
            
            tdImage := mdm.FindTypeDefByName('Windows.Win32.Graphics.GdiPlus.GpImage')
            ; assert mdm.GetCustomAttributeByName(tdImage, 'Windows.Win32.Foundation.Metadata.NativeTypedefAttribute') ; This was removed from the metadata (it's really not a typedef after all)
            ; tdp := mdm.GetTypeDefProps(tdImage)
            for fd in mdm.EnumFields(tdImage) {
                fp := mdm.GetFieldProps(fd)
                equals fp.name, 'Value'
                equals mdSignatureDecoder(fp.sig).Decode(), 'IntPtr'
            }
        }
    }
    
    typeRefName(tr) => mdm.GetTypeRefProps(tr).name
}

TestCase "Find function by name", () {
    mdm := mdModule.Open("..\Windows.Win32.winmd")
    
    target_name := "SetThreadDpiAwarenessContext"
    
    for td in mdm.EnumTypeDefs() {
        tdp := mdm.GetTypeDefProps(td)
        if SubStr(tdp.name, -5) = ".Apis" {
            for md in mdm.EnumMethodsWithName(td, target_name) {
                mdp := mdm.GetMethodProps(md)
                break 2
            }
        }
    }
    
    equals mdp.name, target_name
    equals tdp.name, "Windows.Win32.UI.HiDpi.Apis"
    
    md := mdp.t
    argtypes := mdSignatureDecoder(mdp.sig).Decode()
    argprops := []
    argprops.Length := argtypes.Length ; includes return count at index 1
    for pd in mdm.EnumParams(md) {
        pp := mdm.GetParamProps(pd)
        argprops[pp.index + 1] := pp ; pp.index is 0 for return count
    }
    equals typeRefName(argtypes[1]), 'Windows.Win32.UI.HiDpi.DPI_AWARENESS_CONTEXT' ; return type
    equals typeRefName(argtypes[2]), 'Windows.Win32.UI.HiDpi.DPI_AWARENESS_CONTEXT' ; first param
    assert !argprops.Has(1) || argprops[1].name = "" && argprops[1].flags = 0
    equals argprops[2].name, "dpiContext"
    equals argprops[2].flags, 1 ; in=1, out=2, optional=0x10, hasDefault=0x1000, hasFieldMarshal=0x2000
    
    typeRefName(tr) => mdm.GetTypeRefProps(tr).name
}