
#include <D>
#include <T>

; debug
BoundFunc.prototype.DefineProp 'Func', {get: 
    (this) => ObjFromPtrAddRef(NumGet(ObjPtr(this), 5*A_PtrSize+0x10, 'ptr'))
}
BoundFunc.prototype.DefineProp 'Params', {get: 
    (this) => ObjFromPtrAddRef(NumGet(ObjPtr(this), 7*A_PtrSize+0x10, 'ptr'))
}

#include winrt_constants.ahk
#include rtmetadata.ahk

IID_IMetaDataImport := GUID("{7DAC8207-D3AE-4C75-9B67-92801A497D44}")
MAX_NAME_CCH := 1024

IID_IMetaDataAssemblyImport := "{EE62470B-E94B-424e-9B7C-2F00C9249F93}"

do_experiments()
do_experiments() {
if 0 {
    winmd_file := "C:\Windows\System32\WinMetadata\Windows.Foundation.winmd"

    #DllLoad rometadata.dll
    DllCall("rometadata.dll\MetaDataGetDispenser"
        , "ptr", GUID("{E5CB7A31-7512-11d2-89CE-0080C792E5D8}") ; CLSID_CorMetaDataDispenser
        , "ptr", GUID("{809C652E-7396-11D2-9771-00A0C9B4D50C}") ; IID_IMetaDataDispenser
        , "ptr*", mdd := ComValue(13, 0)
        , "hresult")
    ; IMetaDataDispenser::OpenScope
    ComCall(4, mdd, "wstr", winmd_file, "uint", 0
        , "ptr", IID_IMetaDataImport
        , "ptr*", mdi := ComValue(13, 0))
    
    global STATIC_ATTRIBUTE_CTOR := GetStaticAttributeToken(mdi)
    DumpTypes(mdi)
    
} else {
    ; test_typename := "Windows.UI.Notifications.ToastNotification"
    ; test_typename := "Windows.UI.Notifications.ToastNotificationManager"
    ; test_typename := "Windows.ApplicationModel.DataTransfer.Clipboard"
    ; test_typename := "Windows.Data.Html.HtmlUtilities"
    ; test_typename := "Windows.Globalization.Language"
    ; test_typename := "Windows.System.UserProfile.LockScreen"
    ; test_typename := "Windows.Media.FaceAnalysis.FaceDetector"
    ; test_typename := "Windows.Storage.KnownFolders"
    ; test_typename := "Windows.ApplicationModel.Email.EmailMessage"
    
    ; test_typename := "Windows.Foundation.TypedEventHandler``2"
    ; test_typename := "Windows.ApplicationModel.DataTransfer.IClipboardStatics"
    ; test_typename := "Windows.Foundation.EventRegistrationToken"
    ; test_typename := "Windows.Foundation.PropertyValue"
    ; test_typename := "Windows.Foundation.Rect"
    ; test_typename := "Windows.Foundation.IPropertyValueStatics"
    test_typename := "Windows.Foundation.Collections.IVectorView``1"
    
    #DllLoad wintypes.dll
    DllCall("wintypes.dll\RoGetMetaDataFile"
        , "ptr", HStringFromString(test_typename)
        , "ptr", 0
        , "ptr*", hwinmd_file := HString()
        , "ptr*", mdi := ComValue(13, 0)
        , "uint*", &tdtoken:=0
        , "hresult")
    
    ; D MetaDataModule(mdi).Name
    ; D String(hwinmd_file)
    
    global STATIC_ATTRIBUTE_CTOR := GetStaticAttributeToken(mdi)
    ; ComCall(14, mdi, "uint", 0x1000666, "uint*", &scope:=0, "ptr", 0, "uint", 0, "ptr", 0)
    ; D Format("{:x}", scope)
    ; D GetAssemblyRefName(mdi, scope)
    
    ; DumpTypeInfo(mdi, tdtoken)
    
    ; DumpStaticAttribute(mdi, tdtoken)
    
    ; EnumMethods(mdi, tdtoken)
    
    ; EnumInterfaceImpls(mdi, tdtoken)
    
    ; D '>=================='
    
    ; LockScreen := WinRT._GetClass("Windows.System.UserProfile.LockScreen")
    ; D "! Lock screen image: " String(LockScreen.OriginalImageFile)
    ; stream := LockScreen.GetImageStream()
    ; D stream.Size " bytes " stream.CanRead " " stream.CanWrite
    
    ; KnownFolders := WinRT._GetClass("Windows.Storage.KnownFolders")
    ; MusicLib := KnownFolders.MusicLibrary
    ; D "! " MusicLib.DisplayName " " MusicLib.DisplayType
    
    ; Clipboard := WinRT._GetClass("Windows.ApplicationModel.DataTransfer.Clipboard")
    ; D "! Clipboard history is " (Clipboard.IsHistoryEnabled() ? "" : "not ") "enabled"
    
    ; HtmlUtilities := WinRT._GetClass("Windows.Data.Html.HtmlUtilities")
    ; D HtmlUtilities.ConvertToText("! <b>Hello</b>, <i>world</i>!")
    
    ; D cw.get_IsSupported()
    
    ; appId := "{6D809377-6AF0-444b-8957-A3773F02200E}\AutoHotkey\v2-alpha\AutoHotkey64.exe"
    ; appId := "{6D809377-6AF0-444b-8957-A3773F02200E}\AutoHotkey\AutoHotkey.exe"
    TNM := WinRT._GetClass("Windows.UI.Notifications.ToastNotificationManager")
    ; TH := TNM.History
    ; TH.Clear appId
    toastXml := TNM.getTemplateContent(1)
    textEls := toastXml.getElementsByTagName("text")
    D type(textEls.Item(0))
    D type(textEls.GetAt(0))
    ; textEls.Item(0).InnerText := "Hello, world!"
    ; toastXml.getElementsByTagName("image").Item(0)
            ; .setAttribute("src", "C:\Data\Scripts\Drafts\ActiveScript\sample.png")
    ; toastNotifier := TNM.createToastNotifier(appId)
    ; notification := WinRT._GetClass("Windows.UI.Notifications.ToastNotification")(toastXml)
    ; toastNotifier.show(notification)
    
    WinRT._GetClass("Windows.Data.Xml.Dom.XmlNodeList")
}
}

GetStaticAttributeToken(mdi) {
    mdai := ComObjQuery(mdi, IID_IMetaDataAssemblyImport)
    henum := 0
    ; EnumAssemblyRefs
    try while ComCall(8, mdai, "uint*", &henum, "uint*", &asm:=1, "uint", 1, "ptr", 0) = 0 {
        if GetAssemblyRefName(mdi, asm) = "Windows.Foundation"
            break
    }
    finally
        ComCall(15, mdai, "uint", henum, "int") ; CloseEnum
    ; Currently we assume if there's no reference to Windows.Foundation,
    ; the current scope of mdi ((mdModule)1) is Windows.Foundation.
    ; if asm = 0
        ; throw Error("Windows.Foundation assembly reference not found")
    ; FindTypeRef
    ComCall(55, mdi, "uint", asm, "wstr", "Windows.Foundation.Metadata.StaticAttribute"
        , "uint*", &tr:=0)
    
    ; namebuf := Buffer(2*MAX_NAME_CCH)
    henum := 0
    ctor := 0
    ; EnumMemberRefs
    try while ComCall(23, mdi, "uint*", &henum, "uint", tr, "uint*", &mr:=0, "uint", 1, "ptr", 0) = 0 {
        ; GetMemberRefProps
        ComCall(31, mdi, "uint", mr, "uint*", &ttype:=0
            ; , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
            , "ptr", 0, "uint", 0, "ptr", 0
            , "ptr", 0, "ptr", 0)
        if ctor ; This is valid, but probably won't happen in Windows.*.winmd and isn't handled by this script.
            throw Error("Multiple StaticAttribute constructors are referenced")
        ctor := mr
    }
    finally
        ComCall(3, mdi, "ptr", henum, "int") ; CloseEnum
    return ctor
}

DumpTypeRef(mdi, r) {
    name := GetTypeRefProps(mdi, r, &scope)
    D Format("{:x} {}", r, name)
    if (scope >> 24)
        D Format("  in {:x} {}", scope, GetModuleRefProps(mdi, scope))
}

GetModuleRefProps(mdi, mr) {
    namebuf := Buffer(2*MAX_NAME_CCH)
    ComCall(42, mdi, "uint", mr
        , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0)
    return StrGet(namebuf, namelen, "UTF-16")
}

GetTypeRefProps(mdi, r, &scope:=unset) {
    namebuf := Buffer(2*MAX_NAME_CCH)
    ComCall(14, mdi, "uint", r, "uint*", &scope:=0
        , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0)
    return StrGet(namebuf, namelen, "UTF-16")
}

EnumInterfaceImpls(mdi, td) {
    items := Buffer(4*32, 0)
    namebuf := Buffer(2*MAX_NAME_CCH)
    henum := 0
    while ComCall(7, mdi, "ptr*", &henum, "uint", td
        , "ptr", items, "uint", items.size//4, "uint*", &itemcount:=0) = 0 {
        Loop itemcount {
            item := NumGet(items, (A_Index-1)*4, "uint")
            ; GetInterfaceImplProps
            ComCall(13, mdi, "uint", item, "uint*", &td:=0, "uint*", &ti:=0)
            if (ti >> 24) = 0x1b {
                ; GetTypeSpecFromToken
                ComCall(44, mdi, "uint", ti, "ptr*", &psig:=0, "uint*", &nsig:=0)
                impl_name := DecodeMethodSig(mdi, psig, nsig)
            }
            else
                impl_name := GetNameFromToken(mdi, ti)
            D Format("+{:x} {:x} {} : {:x} {}"
                , item, td, GetNameFromToken(mdi, td), ti, impl_name)
            if IsTypeRef(ti) {
                ti := ResolveLocalTypeRef(mdi, ti)
            }
            if (ti >> 24) = 2 { ; mdtTypeDef
                DumpTypeInfo(mdi, ti)
                EnumMethods(mdi, ti)
            }
        }
    }
    ComCall(3, mdi, "ptr", henum, "int") ; CloseEnum
}

DumpStaticAttribute(mdi, td) {
    namebuf := Buffer(2*MAX_NAME_CCH)
    henum := 0
    ; EnumCustomAttributes
    while ComCall(53, mdi, "uint*", &henum, "uint", td, "uint", STATIC_ATTRIBUTE_CTOR
        , "uint*", &attr:=0, "uint", 1, "ptr", 0) = 0 {
        ; GetCustomAttributeProps
        ComCall(54, mdi, "uint", attr
            , "ptr", 0, "uint*", &tctor:=0
            , "ptr*", &pdata:=0, "uint*", &ndata:=0)
        D '!' StrGet(pdata + 3, 'utf-8')
    }
    /*
    ; EnumCustomAttributes
    while ComCall(53, mdi, "uint*", &henum, "uint", td, "uint", 0
        , "uint*", &attr:=0, "uint", 1, "ptr", 0) = 0 {
        ; GetCustomAttributeProps
        ComCall(54, mdi, "uint", attr
            , "ptr", 0, "uint*", &tctor:=0
            , "ptr*", &pdata:=0, "uint*", &ndata:=0)
        if (tctor >> 24) = 0x0a {
            ; GetMemberRefProps
            ComCall(31, mdi, "uint", tctor, "uint*", &ttype:=0
                , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
                , "ptr", 0, "ptr", 0)
            D Format("  {:x} {:x} {}", tctor, ttype, GetNameFromToken(mdi, ttype))
        }
        ; D '! ' StrGet(pdata + 3, 'utf-8')
    }
    */
    ComCall(3, mdi, "ptr", henum, "int") ; CloseEnum
}

IsTypeRef(r) => (r >> 24) = 1
ResolveLocalTypeRef(mdi, r) {
    ; Resolve type ref
    name := GetTypeRefProps(mdi, r, &scope)
    if scope != 1 ; not local module?
        throw Error(Format("Unsupported scope 0x{:x} for {:x} type {}", scope, r, name))
    return FindTypeDefByName(mdi, name)
}

FindTypeDefByName(mdi, name) {
    ComCall(9, mdi, "wstr", name, "uint", 0, "uint*", &r:=0)
    return r
}

EnumMethods(mdi, token) {
    items := Buffer(4*32, 0)
    namebuf := Buffer(2*MAX_NAME_CCH)
    henum := 0
    while ComCall(16, mdi, "ptr*", &henum, "uint", token
        , "ptr", items, "uint", items.size//4, "uint*", &itemcount:=0) = 0 {
        Loop itemcount {
            method := NumGet(items, (A_Index-1)*4, "uint")
            ; GetMethodProps
            ComCall(30, mdi, "uint", method, "uint*", &tclass:=0
                , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
                , "uint*", &attr:=0
                , "ptr*", &psig:=0, "uint*", &siglen:=0 ; signature blob
                , "ptr", 0 ; RVA (not relevant for WinRT?)
                , "ptr", 0) ; Method impl flags (not useful for us)
            cconv := NumGet(psig++, "uchar")
            argc := NumGet(psig++, "uchar")
            sig := DecodeMethodSig(mdi, psig, siglen - 2)
            D Format("{} - {}`n  {:02x} {:02x} {}"
                , StrGet(namebuf, namelen, "UTF-16")
                , DecodeMethodAttr(attr)
                , cconv, argc, sig)
        }
    }
    ComCall(3, mdi, "ptr", henum, "int") ; CloseEnum
}

DecodeMethodSigType(mdi, &p) {
    static primitives := Map(
        0x01, "void",
        0x02, "bool", ; Boolean
        0x03, "wchar", ; Char16
        0x04, "char",
        0x05, "uchar",
        0x06, "short",
        0x07, "ushort",
        0x08, "int",
        0x09, "uint",
        0x0a, "int64",
        0x0b, "uint64",
        0x0c, "float",
        0x0d, "double",
        0x0e, "string",
        0x18, "ptr",
        0x19, "uptr",
        0x1c, "Object",
    )
    b := NumGet(p++, "uchar")
    if "" != (t := primitives.get(b, ""))
        return t
    switch b {
        case 0x0f: ; ptr
            return DecodeMethodSigType(mdi, &p) '*'
        case 0x10: ; ref
            return DecodeMethodSigType(mdi, &p) '&'
        case 0x1D: ; array
            return DecodeMethodSigType(mdi, &p) '[]'
        case 0x11, 0x12: ; value type, class type
            return RegExReplace(GetTypeRefProps(mdi, CorSigUncompressToken(&p), &scope)
                , "^(Windows|System)\.(.*\.)?") (b=0x11 ? "^" : "")
        case 0x13: ; generic type parameter
            return 'T' (NumGet(p++, "uchar") + 1)
        case 0x15: ; GENERICINST <generic type> <argCnt> <arg1> ... <argn>
            t := RegExReplace(DecodeMethodSigType(mdi, &p), '``\d+$') '<'
            Loop argc := NumGet(p++, "uchar")
                t .= (A_Index>1 ? ',' : '') . DecodeMethodSigType(mdi, &p)
            t .= '>'
            return t
        default:
            return Format("{:02x}", b)
    }
}

DecodeMethodSig(mdi, p, size) {
    p2 := p + size
    sig := ""
    while p < p2 {
        (A_Index > 1) && sig .= " "
        sig .= DecodeMethodSigType(mdi, &p)
    }
    if p > p2
        sig .= " ERR"
    return sig
}

DecodeMethodAttr(a) {
    static accesswords := ['PrivateScope', 'Private', 'FamANDAssem', 'Assembly'
        , 'Family', 'FamORAssem', 'Public']
    flags := '' ; accesswords[(a & 7) + 1]
    static flagmap := Map(
        0x8, 'UnmanagedExport',
        0x10, 'Static',
        0x20, 'Final',
        ; 0x40, 'Virtual',
        ; 0x80, 'HideBySig',
        0x100, 'NewSlot',
        0x200, 'CheckAccessOnOverride',
        0x400, 'Abstract',
        0x800, 'SpecialName',
        0x1000, 'RTSpecialName',
        0x2000, 'PinvokeImpl',
        0x4000, 'HasSecurity',
        0x8000, 'RequireSecObject'
    )
    flag := 0x8
    while flag < 0x8000 {
        if f := a & flag
            flagmap.has(f) ? flags .= ' ' flagmap[f] : ''
            ; flags .= ' ' flagmap.get(f, Format("0x{:x}", f))
        flag <<= 1
    }
    return LTrim(flags, ' ')
}

DumpTypeInfo(mdi, tdtoken) {
    namebuf := Buffer(2*MAX_NAME_CCH)
    ; GetTypeDefProps
    ComCall(12, mdi, "uint", tdtoken
        , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
        , "uint*", &flags:=0, "uint*", &basetype:=0)
    D Format("{:x} {:x} {}", tdtoken, flags, StrGet(namebuf, namelen, "UTF-16"))
    if basetype && !(flags & 0x20) { ; tdInterface:=0x20 - WinRT interfaces always extend IInspectable, which doesn't exist in the metadata.
        if IsTypeRef(basetype) {
            ; D Format("{:x}", basetype)
            name := GetTypeRefProps(mdi, basetype, &scope)
            ; if SubStr(name, 1, 7) == "System." {
                D "  extends " name
                ; return
            ; }
        }
        else {
            D "  extends:"
            DumpTypeInfo(mdi, basetype)
        }
    }
}

DumpTypes(mdi) {
    ; EnumTypeDefs
    typedefs := Buffer(4*32, 0)
    namebuf := Buffer(2*MAX_NAME_CCH)
    henum := 0
    while ComCall(6, mdi, "ptr*", &henum, "ptr", typedefs, "uint", 32, "uint*", &tdcount:=0) = 0 {
        Loop tdcount {
            td := NumGet(typedefs, (A_Index-1)*4, "uint")
            DumpTypeInfo(mdi, td)
            DumpStaticAttribute(mdi, td)
        }
    }
    ComCall(3, mdi, "ptr", henum, "int") ; CloseEnum
}

GetNameFromToken(mdi, token) {
    try
        ComCall(45, mdi, "uint", token, "ptr*", &pname:=0)
    catch as e
        return Format("noname(Err:{:x})", e.number)
    return StrGet(pname, "UTF-8")
}


CorIsPrimitiveType(t) => t < ELEMENT_TYPE.PTR || t = ELEMENT_TYPE.I || t = ELEMENT_TYPE.U
CorIsModifierElementType(t) => t = ELEMENT_TYPE.PTR || t = ELEMENT_TYPE.BYREF || (t & ELEMENT_TYPE.MODIFIER)
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


GetAssemblyRefName(mdi, r) {
    mdai := ComObjQuery(mdi, IID_IMetaDataAssemblyImport)
    namebuf := Buffer(2*MAX_NAME_CCH)
    ; GetAssemblyRefProps
    ComCall(4, mdai , "uint", r , "ptr", 0 , "ptr", 0
        , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
        , "ptr", 0 , "ptr", 0 , "ptr", 0 , "ptr", 0)
    return StrGet(namebuf, namelen, "UTF-16")
}


class HString {
	__new(hstr := 0) => this.ptr := hstr
	ToString() => WindowsGetString(this)
	__delete() {
        ; api-ms-win-core-winrt-string-l1-1-0.dll
		DllCall("combase.dll\WindowsDeleteString"
			, "ptr", this) ; this.ptr can be 0 (equivalent to "").
	}
}

HStringFromString(str, len := unset) {
    DllCall("combase.dll\WindowsCreateString"
			, "ptr", StrPtr(str), "uint", IsSet(len) ? len : StrLen(str)
            , "ptr*", &hstr := 0, "hresult")
    return HString(hstr)
}

WindowsGetString(hstr, &len := 0) {
	p := DllCall("combase.dll\WindowsGetStringRawBuffer"
		, "ptr", hstr, "uint*", &len := 0, "ptr")
	return StrGet(p, -len, "UTF-16")
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
    
    ; static Call(p) => p is Integer ? _rt_WrapInspectable(p) : ...
    
    static _GetClass(classname) =>
        this._cls.get(classname, 0) ||
        this._cls[classname] := this._MakeClass(classname)
    
    static _MakeClass(classname) {
        MetaDataModule.GetForTypeName(classname, &mdm, &td)
        return mdm.CreateClassWrapper(td, classname)
    }
    
    ; Returns function (instancePtr => wrapper for instancePtr).
    ; static _GetWrapFn(classname) =>
        ; this._wrp.get(classname, 0) ||
        ; this._wrp[classname] := this._MakeWrapFn(classname)
    
    static _GetWrapFn(classname, proto:=unset) {
        MetaDataModule.GetForTypeName(classname, &mdm, &td)
        if mdm.GetTypeDefFlags(td) & 0x20 { ; interface
            return _rt_WrapInspectable
        }
        return WrapClass(p) => {
            ptr: p,
            base: IsSet(proto) ? proto : proto := WinRT._GetClass(classname).prototype
        }
    }
}

_rt_WrapInspectable(p) {
    ; IInspectable::GetRuntimeClassName
    ComCall(4, p, "ptr*", &hcls:=0)
    return {
        ptr: p,
        base: WinRT._GetClass(_rt_HStringRet(hcls)).prototype
    }
}

AddMethodOverloadTo(obj, name, f, name_prefix:="") {
    if obj.HasOwnProp(name) {
        if (pd := obj.GetOwnPropDesc(name)).HasProp('Call')
            prev := pd.Call
    }
    if IsSet(prev) {
        if !((of := prev) is OverloadedFunc) {
            obj.DefineProp(name, {Call: of := OverloadedFunc()})
            of.Name := name_prefix . name
            of.Add(prev)
        }
        of.Add(f)
    }
    else
        obj.DefineProp(name, {Call: f})
}

class OverloadedFunc {
    m := Map()
    Add(f) {
        n := f.MinParams
        Loop (f.MaxParams - n) + 1
            if this.m.has(n)
                throw Error("Ambiguous function overloads", -1)
            else
                this.m[n++] := f
    }
    Call(p*) {
        if (f := this.m.get(p.Length, 0))
            return f(p*)
        else
            throw Error(Format('Overloaded function "{}" does not accept {} parameters.'
                , this.Name, p.Length), -1)
    }
    static __new() {
        this.prototype.Name := ""
    }
}
