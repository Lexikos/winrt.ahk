#include testcase.ahk
#include ..\winmd.ahk

D ??= (s) => OutputDebug(s)

WinmdDir := A_WinDir "\System32\WinMetadata"

TestCase "Struct TypeDef and TypeRef", () {
    mdm := mdModule.Open(WinmdDir "\Windows.Foundation.winmd")
    assert mdm is mdModule && mdm.Name = "Windows.Foundation.winmd"
    
    td := mdm.FindTypeDefByName('Windows.Foundation.Size')
    assert td is mdToken && td.Type = 'TypeDef' && td.Row > 0
    
    tdp := mdm.GetTypeDefProps(td)
    equals tdp.name, 'Windows.Foundation.Size'
    assert tdp.flags & 0x4000 ; WindowsRuntime
    equals tdp.flags &    7,   1 ; Visibility = Public
    equals tdp.flags & 0x18, 0x8 ; Layout = SequentialLayout
    equals tdp.flags & 0x60,   0 ; not 0x20 Interface (mask is defined as 0x60 but no other flags are defined)
    assert tdp.extends is mdToken && tdp.extends.Type = 'TypeRef' && tdp.extends.Row > 0
    
    throws ()=> mdm.GetTypeDefProps({}), TypeError
    throws ()=> mdm.GetTypeDefProps(0), ValueError
    throws ()=> mdm.GetTypeDefProps(mdToken(0)), ValueError
    tdp := mdm.GetTypeDefProps(td.t)
    equals tdp.name, 'Windows.Foundation.Size'
    
    trp := mdm.GetTypeRefProps(tdp.extends)
    equals trp.name, 'System.ValueType'
    equals trp.scope.Type, 'AssemblyRef'
    
    for fd in mdm.EnumFields(td) {
        assert fd is mdToken && fd.Type = 'FieldDef' && fd.Row > 0
        fp := mdm.GetFieldProps(fd)
        equals fp.name, ['Width', 'Height'][A_Index]
        equals fp.flags, 6 ; Visibility = Public, no other flags
        equals mdSignatureDecoder(fp.sig).Decode(), 'Single'
    } else throw
    
    for fd in mdm.EnumFieldsWithName(td, 'Height') {
        assert A_Index = 1 && mdm.GetFieldProps(fd).name == 'Height'
    }
}

TestCase "Attribute", () {
    mdm := mdModule.Open(WinmdDir "\Windows.Foundation.winmd")
    
    td := mdm.FindTypeDefByName('Windows.Foundation.Size')
    for a in mdm.EnumCustomAttributes(td) {
        ap := mdm.GetCustomAttributeProps(a)
        ac := mdm.GetMemberRefProps(ap.ctor)
        acp := mdm.GetTypeRefProps(ac.parent)
        ad := mdDecodeAttribData(ap.data, ac.sig)
        
        equals acp.name, "Windows.Foundation.Metadata.ContractVersionAttribute"
        equals ad[1], "Windows.Foundation.FoundationContract"
        equals ad[2], 0x10000
    }
}

TestCase "Simple interfaces", () {
    mdm := mdModule.Open(WinmdDir "\Windows.Foundation.winmd")
    
    td := mdm.FindTypeDefByName('Windows.Foundation.IClosable')
    assert mdm.EnumMethods(td)(&md)
    mp := mdm.GetMethodProps(md)
    equals mp.name, 'Close'
    argtypes := mdSignatureDecoder(mp.sig).Decode()
    equals argtypes[1], 'Void'
    equals argtypes.Length, 1
    equals mdm.EnumInterfaceImpls(td)(), 0 ; No implemented interfaces
    
    td := mdm.FindTypeDefByName('Windows.Foundation.IMemoryBuffer')
    assert mdm.EnumMethods(td)(&md)
    mp := mdm.GetMethodProps(md)
    equals mp.name, 'CreateReference'
    argtypes := mdSignatureDecoder(mp.sig).Decode()
    equals mdm.GetTypeRefProps(argtypes[1]).name, 'Windows.Foundation.IMemoryBufferReference'
    equals argtypes.Length, 1
    equals mdm.EnumInterfaceImpls(td)(&ii), 1 ; interface IMemoryBuffer : IClosable
    ip := mdm.GetInterfaceImplProps(ii)
    equals ip.iface.Type, 'TypeRef' ; TypeDef and TypeSpec are also possible in other cases.
    equals mdm.GetTypeRefProps(ip.iface).name, 'Windows.Foundation.IClosable'
}


/*
seen := Map()
see(path) {
    mdm := mdModule.Open(path)
    mdt := ComObjQuery(mdm, "{D8F579AB-402D-4B8E-82D9-5D63B1065C68}") ; IMetaDataTables
    ComCall(7, mdt, "uint*", &nTables:=0)
    Loop nTables {
        ComCall(9, mdt, "uint", A_Index-1, "ptr", 0, "uint*", &rowCount:=0, "ptr", 0, "ptr", 0, "astr*", &name:="")
        if rowCount
            seen[name] := mdm.Name
    }
}
Loop Files A_WinDir "\System32\WinMetadata\*.winmd" {
    see(A_LoopFileFullPath)
}
see("..\Windows.Win32.winmd")
for name, mname in seen {
    OutputDebug name "`n" ;"`tin " mname "`n"
}