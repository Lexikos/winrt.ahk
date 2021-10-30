
#include <D>
#include <T>
#warn all, stdout
#warn LocalSameAsGlobal, off

; debug
BoundFunc.prototype.DefineProp 'Func', {get:
    (this) => ObjFromPtrAddRef(NumGet(ObjPtr(this), 5*A_PtrSize+0x10, 'ptr'))
}
BoundFunc.prototype.DefineProp 'Params', {get: 
    (this) => ObjFromPtrAddRef(NumGet(ObjPtr(this), 7*A_PtrSize+0x10, 'ptr'))
}

#include rtmetadata.ahk
#include rtinterface.ahk
#include windows.ahk
#include hstring.ahk
#include overload.ahk

OnError((e, *) => D("> STACK:`n" e.Stack "> ======"))

IID_IMetaDataImport := GUID("{7DAC8207-D3AE-4C75-9B67-92801A497D44}")
CLSID_CorMetaDataDispenser := GUID("{E5CB7A31-7512-11d2-89CE-0080C792E5D8}")
IID_IMetaDataDispenser := GUID("{809C652E-7396-11D2-9771-00A0C9B4D50C}")

MAX_NAME_CCH := 1024

IID_IMetaDataAssemblyImport := "{EE62470B-E94B-424e-9B7C-2F00C9249F93}"

WaitSync(async) {
    loop
        sleep 10
    until async.status.n
    return async.GetResults()
}

do_experiments
do_experiments() {
    ; LockScreen := WinRT("Windows.System.UserProfile.LockScreen")
    ; D "! Lock screen image: " String(LockScreen.OriginalImageFile)
    ; stream := LockScreen.GetImageStream()
    ; D stream.Size " bytes " stream.CanRead " " stream.CanWrite
    
    ; KnownFolders := WinRT("Windows.Storage.KnownFolders")
    ; MusicLib := KnownFolders.MusicLibrary
    ; D "! " MusicLib.DisplayName " " MusicLib.DisplayType
    
    ; HtmlUtilities := WinRT("Windows.Data.Html.HtmlUtilities")
    ; D HtmlUtilities.ConvertToText("! <b>Hello</b>, <i>world</i>!")
    
    ale := Windows.Storage.AccessCache.AccessListEntry()
    ale.token := "hello"
    ale.metadata := "world"
    D ale.token ", " ale.metadata "!"
}

; test_clipboard_async_enums
test_clipboard_async_enums() {
    Clipboard := WinRT("Windows.ApplicationModel.DataTransfer.Clipboard")
    D "! Clipboard history is " (Clipboard.IsHistoryEnabled() ? "" : "not ") "enabled"
    results := WaitSync(Clipboard.GetHistoryItemsAsync())
    if results.Status.s = "Success" {
        items := results.Items
        Loop Min(items.Size, 5) {
            item := items.GetAt(A_Index-1)
            dpv := item.Content
            if dpv.Contains("Text") {
                D A_index ": " WaitSync(dpv.GetTextAsync())
            }
        }
    }
    else
        MsgBox results.Status.s
}

; test_storagefile
test_storagefile() {
    StorageFile := Windows.Storage.StorageFile
    AS_Completed := Windows.Foundation.AsyncStatus.Completed
    async := StorageFile.GetFileFromPathAsync("C:\Data\Pictures\anime\kokkoku\Kokkoku 2.png")
    Loop
        sleep 10
    until async.status = AS_Completed
    sfile := async.GetResults()
    D sfile.DisplayType
    D "100-nano`t" time := sfile.DateCreated.UniversalTime
    D "YYYYMMDD`t" ytime := DateAdd("16010101", time/10000000 + 36000, "S")
    D "`t`t" FormatTime(ytime)
    D "FileGetTime`t" FileGetTime(sfile.Path, "C")
    D "Attributes`t" String(sfile.Attributes)
    ; D async.ErrorCode
}

test_notifications
test_notifications() {
    appId := "{6D809377-6AF0-444b-8957-A3773F02200E}\AutoHotkey\v2-alpha\AutoHotkey64.exe"
    ; appId := "{6D809377-6AF0-444b-8957-A3773F02200E}\AutoHotkey\AutoHotkey.exe"
    TNM := WinRT("Windows.UI.Notifications.ToastNotificationManager")
    TNM.History.Clear appId
    toastXml := TNM.getTemplateContent(1)
    textEls := toastXml.getElementsByTagName("text")
    textEls.GetAt(0).InnerText := "Hello, world!"
    toastXml.getElementsByTagName("image").Item(0)
            .setAttribute("src", "C:\Data\Scripts\Drafts\ActiveScript\sample.png")
    ; toastXml := WinRT("Windows.Data.Xml.Dom.XmlDocument")()
    ; toastXml.LoadXml("
    ; (
    ;     <toast activationType="protocol" launch="https://google.com">
    ;       <visual>
    ;         <binding template="ToastGeneric">
    ;           <text>Restaurant suggestion...</text>
    ;           <text>We noticed that you are near Wasaki. Thomas left a 5 star rating after his last visit, do you want to try it?</text>
    ;         </binding>
    ;       </visual>
    ;       <actions>
    ;         <action activationType="protocol" content="Show calculator" arguments="ms-calculator:" />
    ;       </actions>
    ;     </toast>
    ; )")
    toastNotifier := TNM.createToastNotifier(appId)
    notification := WinRT("Windows.UI.Notifications.ToastNotification")(toastXml)
    toastNotifier.show(notification)
}

; test_rtinterface
test_rtinterface() {
    testnames := [
        ; "Windows.Foundation.IAsyncOperation``1<Windows.Storage.StorageFile>",
        ; "Windows.Foundation.Collections.IVectorView``1<Windows.Data.Xml.Dom.IXmlNode>",
        ; "Windows.UI.Xaml.Controls.TextBox",
        "Windows.Foundation.HResult",
        "Windows.Foundation.EventRegistrationToken",
        "Windows.Foundation.AsyncStatus",
        "Windows.Foundation.Rect",
        "Windows.Foundation.Size",
        "Windows.Foundation.TimeSpan",
        "Windows.Foundation.DateTime",
        ]
    for testname in testnames {
        dump(testname)
    }
    dump(tn) {
        t := WinRT.GetType(tn)
        switch t.FundamentalType.Name {
            case "Object": dumpc(t)
            case "Interface": dumpi(t)
            case "ValueType", "Enum": dumpv(t)
            default:
                D '{} is a {}', String(t), String(t.FundamentalType)
        }
    }
    dumpv(t) {
        d_scope(&s, t.Name)
        ; dumpc(t)
        for f in t.Fields() {
            d_ f
            D String(f.type)
        }
    }
    dumpc(ht) {
        D '+' ht.Name
        if ht.HasIActivationFactory
            D "supports direct activation"
        for t in ht.Factories() {
            D "factory " String(t)
        }
        for t in ht.Composers() {
            D "composer " String(t)
        }
        for t in ht.Statics() {
            D "static " String(t)
        }
        dumpi(ht)
        if (b := ht.BaseType) is RtTypeInfo {
            D 'extends ...'
            dumpc(b)
        }
    }
    dumpi(ht, indent:="") {
        for t in ht.Implements() {
            D indent "requires " String(t)
            dumpi(t, indent "  ")
        }
    }
}

; test_structs
test_structs() {
    ; Rect := Windows.Foundation.Rect
    r := Windows.Foundation.Rect()
    MouseGetPos(&x, &y)
    r.X := x, r.Y := y
    r.Width := 200, r.Height := r.Width*.75
    ; @Debug-Output => {r.X} {r.Y} {r.Width} {r.Height}
}

; test_namespaces
test_namespaces() {
    dumpn(n, indent:="") {
        for name, n2 in n {
            ; D indent name " (" n2._name ")"
            D indent n2._name
            dumpn(n2, indent "  ")
        }
    }
    dumpn(Windows)
    ; dumpn(Windows.UI)
    ; dumpn(Windows.ui.xaml)
}

scan_files_for_structs
scan_files_for_structs() {
    Loop Files A_WinDir "\System32\WinMetadata\*.winmd" {
        ; IMetaDataDispenser::OpenScope
        mdm := MetaDataModule.Open(A_LoopFilePath)
        ; EnumTypeDefs
        for td in mdm.EnumTypeDefs() {
            t := RtTypeInfo(mdm, td)
            if t.FundamentalType.Name != "ValueType"
                continue
            fields := [t.Fields()*]
            if fields.Length = 0  ; Metadata-only struct.
                continue
            simple := true
            for f in fields {
                ; if !(f.type is RtMarshal.Info) || f.type.HasProp('I') || f.type.HasProp('O')
                ; if !(f.type is RtMarshal.Info)
                ;     simple := false
                if f.type = RtMarshal.String
                    simple := false
            }
            if simple
                continue
            try
                cls := t.Class
            catch as e
                D '{}: {}', type(e), e.message
            else
                D 'Struct size: ' cls.prototype.Size
            ; dumps(t.name, fields)
        }
    }
    dumps(name, fields) {
        d_scope(&s, name)
        for f in fields {
            if f.type is RtMarshal.Info || f.type.FundamentalType.Name = "Enum"
                D f.name ' : ' String(f.type)
            else
                dumps(f.name ' : ' f.type.name, f.type.Fields())
        }
    }
}

; scan_files_for_rettypes
scan_files_for_rettypes() {
    Loop Files A_WinDir "\System32\WinMetadata\*.winmd" {
        ; IMetaDataDispenser::OpenScope
        mdm := MetaDataModule.Open(A_LoopFilePath)
        ; EnumTypeDefs
        for td in mdm.EnumTypeDefs() {
            dumpt(RtTypeInfo(mdm, td))
        }
    }
    dumpt(t) {
        local s
        for m in t.Methods() {
            try {
                ra := t.MethodArgTypes(m.sig)
                if ra[1] is RtTypeInfo && ra[1].FundamentalType.Name = "ValueType"
                    && ra[1].Name != "Windows.Foundation.EventRegistrationToken" {
                    IsSet(s) || d_scope(&s, t.Name)
                    d m.name ' -> ' ra[1].Name
                }
            }
            catch OSError as e {
                if e.number != 0x80073D54
                    throw
                ; IsSet(s) || d_scope(&s, t.Name)
                ; d m.name ' -- unsupported ' e.extra
            }
        }
    }
}


DecodeMethodSig(mdi, p, size) { ;debug
    sig := ""
    for t in _rt_DecodeSig(mdi, p, size) {
        (A_Index > 1) && sig .= " "
        sig .= String(t)
    }
    return RegExReplace(StrReplace(sig, " ", ", "), "^([^\s,]+)(?:, (.*))?", "($2) -> $1")
}


CorSigUncompressedDataSize(p) => (
    (NumGet(p, "uchar") & 0x80) = 0x00 ? 1 :
    (NumGet(p, "uchar") & 0xC0) = 0x80 ? 2 : 4
)
CorSigUncompressData(&p) {
    if (NumGet(p, "uchar") & 0x80) = 0x00
        return  NumGet(p++, "uchar")
    if (NumGet(p, "uchar") & 0xC0) = 0x80
        return (NumGet(p++, "uchar") & 0x3f) << 8
            |   NumGet(p++, "uchar")
    else
        return (NumGet(p++, "uchar") & 0x1f) << 24
            |   NumGet(p++, "uchar") << 16
            |   NumGet(p++, "uchar") << 8
            |   NumGet(p++, "uchar")
}
CorSigUncompressToken(&p) {
    tk := CorSigUncompressData(&p)
    return [0x02000000, 0x01000000, 0x1b000000, 0x72000000][(tk & 3) + 1]
        | (tk >> 2)
}





class GUID extends Buffer {
    __new(sguid:=unset) {
        super.__new(16, 0)
        if IsSet(sguid)
            DllCall("ole32.dll\IIDFromString", "wstr", sguid, "ptr", this, "hresult")
    }
    ToString() {
		buf := Buffer(78)
		DllCall("ole32.dll\StringFromGUID2", "ptr", this, "ptr", buf, "int", 39)
		return StrGet(buf, "UTF-16")
	}
}


class WinRT {
    static __new() {
        ; this._wrp := Map()
        ; this._wrp.CaseSense := "off"
        this._cls := Map()
        this._cls.CaseSense := "off"
    }
    
    static Call(p) => (
        p is String ? this.GetType(p).Class :
        p is Object ? _rt_WrapInspectable(p.ptr) :
        _rt_WrapInspectable(p)
    )
    
    static _CacheGetMetaData(typename, &td) {
        #DllLoad wintypes.dll
        DllCall("wintypes.dll\RoGetMetaDataFile"
            , "ptr", HStringFromString(typename)
            , "ptr", 0
            , "ptr", 0
            , "ptr*", m := RtMetaDataModule()
            , "uint*", &td := 0
            , "hresult")
        static cache := Map()
        ; Cache modules by filename to conserve memory and so cached property values
        ; can be used by all namespaces within the module.
        return cache.get(mn := m.Name, false) || cache[mn] := m
    }
    
    static _CacheGetTypeNS(name) {
        if !(p := InStr(name, ".",, -1))
            throw ValueError("Invalid typename", -1, name)
        static cache := Map()
        ; Cache module by namespace, since all types *directly* within a namespace
        ; must be defined within the same file (but child namespaces can be defined
        ; in a different file).
        try {
            if m := cache.get(ns := SubStr(name, 1, p-1), false) {
                ; Module already loaded - find the TypeDef within it.
                td := m.FindTypeDefByName(name)
            }
            else {
                ; Since we haven't seen this namespace before, let the system work out
                ; which module contains its metadata.
                cache[ns] := m := this._CacheGetMetaData(name, &td)
            }
        }
        catch OSError as e {
            if e.number = 0x80073D54 {
                e.message := "(0x80073D54) Type not found."
                e.extra := name
            }
            throw
        }
        return RtTypeInfo(m, td)
    }
    
    static _CacheGetType(name) {
        static cache := RtTypeInfo.cache
        ; Cache typeinfo by full name.
        return cache.get(name, false)
            || cache[name] := this._CacheGetTypeNS(name)
    }
    
    static GetType(name) {
        if p := InStr(name, "<") {
            baseType := this._CacheGetType(baseName := SubStr(name, 1, p-1))
            typeArgs := []
            while RegExMatch(name, "\G([^<>,]++(?:<(?:(?1)(?:,|(?=>)))++>)?)(?=[,>])", &m, ++p) {
                typeArgs.Push(this.GetType(m.0))
                p += m.Len
            }
            if p != StrLen(name) + 1
                throw Error("Parse error or bad name.", -1, SubStr(name, p) || name)
            ; FIXME: cache generic instance
            return {
                typeArgs: typeArgs,
                m: baseType.m, t: baseType.t,
                base: baseType.base
            }
        }
        return this._CacheGetType(name)
    }
    
    static GetTypeByToken(m, t, typeArgs:=false) {
        scope := -1
        switch (t >> 24) {
        case 0x01: ; TypeRef (most common)
            ; TODO: take advantage of GetTypeRefProps's scope parameter
            return this.GetType(m.GetTypeRefProps(t))
        case 0x02: ; TypeDef
            MsgBox 'DEBUG: GetTypeByToken was called with a TypeDef token.`n`n' Error().Stack
            ; TypeDefs usually aren't referenced directly, so just resolve it by
            ; name to ensure caching works correctly.  Although GetType resolving
            ; the TypeDef will be a bit redundant, it should perform the same as
            ; if a TypeRef token was passed in.
            return this.GetType(m.GetTypeDefProps(t))
        case 0x1b: ; TypeSpec
            ; GetTypeSpecFromToken
            ComCall(44, m, "uint", t, "ptr*", &psig:=0, "uint*", &nsig:=0)
            ; Signature: 0x15 0x12 <typeref> <argcount> <args>
            nsig += psig++
            return _rt_DecodeSigGenericInst(m, &psig, nsig, typeArgs)
        default:
            throw Error(Format("Cannot resolve token 0x{:08x} to type info.", t), -1)
        }
    }
}

class RtMetaDataModule extends MetaDataModule {
    
}

_rt_WrapInspectable(p, typeinfo:=false) {
    if !p
        return
    ; IInspectable::GetRuntimeClassName
    hr := ComCall(4, p, "ptr*", &hcls:=0, "int")
    if hr >= 0 {
        typeinfo := WinRT.GetType(HStringRet(hcls))
    }
    else if !typeinfo || hr != -2147467263 { ; E_NOTIMPL
        e := OSError(hr)
        e.Message := "IInspectable::GetRuntimeClassName failed`n`t" e.Message
        throw e
    }
    return {
        ptr: p,
        base: typeinfo.Class.prototype
    }
}


_rt_memoize(this, propname, f := unset) {
    value := IsSet(f) ? f(this) : this._init_%propname%()
    this.DefineProp propname, {value: value}
    return value
}

d_start(m) {
    ; @Debug-Output:startCollapsed => {m}
}
d_(m) {
    ; @Debug-Output => {m}
}
d_end() {
    ; @Debug-Output:end
}
d_scope(&s, m) {
    global A_DebuggerName
    static ender := {__delete: this => d_end()}
    return IsSet(A_DebuggerName) && (s := {base: ender}, d_start(m))
}
