
class MetaDataModule {
    __new(mdi) {
        if mdi is Integer
            this.ptr := mdi
        else if ComObjType(mdi) = 13
            ObjAddRef(this.ptr := ComObjValue(mdi))
        else
            throw TypeError("Parameter #1 type invalid", -1, type(mdi))
    }
    __delete() {
        ObjRelease(this.ptr)
    }
    
    StaticAttr => _rt_CacheAttributeCtors(this, this, 'StaticAttr')
    FactoryAttr => _rt_CacheAttributeCtors(this, this, 'FactoryAttr')
    ActivatableAttr => _rt_CacheAttributeCtors(this, this, 'ActivatableAttr')
    
    AddFactoriesToWrapper(w, td) {
        for attr in this.EnumCustomAttributes(td, this.ActivatableAttr) {
            this.AddIActivationFactoryToWrapper(w)
        }
        for attr in this.EnumCustomAttributes(td, this.FactoryAttr) {
            ; GetCustomAttributeProps
            ComCall(54, this, "uint", attr
                , "ptr", 0, "ptr", 0, "ptr*", &pdata:=0, "uint*", &ndata:=0)
            iface_name := StrGet(pdata + 3, "utf-8")
            ; FindTypeDefByName
            ComCall(9, this, "wstr", iface_name, "uint", 0, "uint*", &ti:=0)
            this.AddInterfaceToWrapper(w, ti,, "Call")
        }
    }
    
    AddIActivationFactoryToWrapper(w) {
        ActivateInstance(cls) {
            ComCall(6, ComObjQuery(cls, "{00000035-0000-0000-C000-000000000046}") ; IActivationFactory
                , "ptr*", inst := {base: cls.prototype})
            return inst
        }
        D '! adding IActivationFactory to ' w.prototype.__class
        AddMethodOverloadTo(w, "Call", ActivateInstance, w.prototype.__class ".")
    }
    
    CreateClassWrapper(td, classname) {
        w := Class()
        w.base := RtObject
        w.prototype := RtObject()
        w.prototype.__class := classname ;:= this.GetTypeDefProps(td, &flags)
        ; if flags & 0x20 {
            ; D '+ interface ' classname
            ; this.AddInterfaceToWrapper(w.prototype, td, true)
            ; return w
        ; }
        D '+ class ' classname
        ; static oiid := GUID("{00000035-0000-0000-C000-000000000046}") ; IActivationFactory
        static oiid := GUID("{AF86E2E0-B12D-4c6a-9C5A-D7AA65101E90}") ; IInspectable
        hr := DllCall("combase.dll\RoGetActivationFactory"
            , "ptr", HStringFromString(classname)
            , "ptr", oiid
            , "ptr*", w, "int")
        if hr < 0
            D '- no class factory for ' classname
        this.AddFactoriesToWrapper(w, td)
        ; For each static interface:
        for attr in this.EnumCustomAttributes(td, this.StaticAttr) {
            ; GetCustomAttributeProps
            ComCall(54, this, "uint", attr
                , "ptr", 0, "uint*", &tctor:=0, "ptr*", &pdata:=0, "uint*", 0)
            iface_name := StrGet(pdata + 3, "utf-8")
            ; FindTypeDefByName
            ComCall(9, this, "wstr", iface_name, "uint", 0, "uint*", &ti:=0)
            this.AddInterfaceToWrapper(w, ti)
        }
        ; For each instance interface:
        for impl in this.EnumInterfaceImpls(td) {
            ; GetCustomAttributeByName
            isdefault := ComCall(60, this, "uint", impl, "wstr", "Windows.Foundation.Metadata.GuidAttribute", "ptr", 0, "ptr", 0) = 0
            ; GetInterfaceImplProps
            ComCall(13, this, "uint", impl, "ptr", 0, "uint*", &ti:=0)
            if IsTypeRef(ti)
                ti := ResolveLocalTypeRef(this, ti)
            this.AddInterfaceToWrapper(w.prototype, ti, isdefault)
        }
        return w
    }
    
    AddInterfaceToWrapper(w, td, isdefault:=false, nameoverride:=unset, genericTypes:=false) {
        classname := w.HasOwnProp('prototype') ? w.prototype.__class : w.__class ;debug
        if (td >> 24) = 0x1b { ; mdtTypeSpec
            ; GetTypeSpecFromToken
            ComCall(44, this, "uint", td, "ptr*", &psig:=0, "uint*", &nsig:=0)
            ; 0x15 0x12 <typeref> <argcount> <args>
            if NumGet(psig, 0, "ushort") != 0x1215 {
                D "- unsupported typespec {:x} in class {}", td, classname
                return
            }
            p := psig + 2
            name := GetTypeRefProps(this, CorSigUncompressToken(&p))
            argc := NumGet(p++, "uchar")
            genericTypes := DecodeSigTypes(this, p, nsig - (p - psig), argc)
            MetaDataModule.GetForTypeName(name, &mdm, &td)
            ; return mdm.AddInterfaceToWrapper(w, td,,, genericTypes)
            this := mdm
            pguid := _rt_GetParameterizedIID([name, ...])
        }
        else {
            ; GetCustomAttributeByName
            if ComCall(60, this, "uint", td, "wstr", "Windows.Foundation.Metadata.GuidAttribute"
                , "ptr*", &pguid:=0, "uint*", &nguid:=0) != 0 {
                D "- interface {:x} can't be added; no GUID", td
                return
            }
            ; Attribute is serialized with leading 16-bit version (1) and trailing 16-bit number of named args (0).
            if nguid != 20
                throw Error("Unexpected GuidAttribute data; length = " nguid)
            pguid += 2
        }
        if isdefault {
            w.__DefaultIID := pguid
            w.__DefaultIName := this.GetTypeDefProps(td)
        }
        namebuf := Buffer(2*MAX_NAME_CCH)
        DllCall("ole32\StringFromGUID2", "ptr", pguid, "ptr", namebuf, "int", MAX_NAME_CCH)
        D iid := StrGet(namebuf)
        for method in this.EnumMethods(td) {
            ; GetMethodProps
            ComCall(30, this, "uint", method, "uint*", &tclass:=0
                , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
                , "uint*", &attr:=0
                , "ptr*", &psig:=0, "uint*", &nsig:=0 ; signature blob
                , "ptr", 0, "ptr", 0)
            if IsSet(nameoverride)
                name := nameoverride
            else
                D name := StrGet(namebuf, namelen, "UTF-16")            
            D "  " DecodeMethodSig(this, psig+2, nsig-2)
            types := DecodeSig(this, psig, nsig, genericTypes)
            wrapper := MethodWrapper(5 + A_Index, iid, types, classname '.' name)
            if attr & 0x400 { ; tdSpecialName
                switch SubStr(name, 1, 4) {
                case "get_":
                    w.DefineProp(SubStr(name, 5), {Get: wrapper})
                    continue
                case "put_":
                    w.DefineProp(SubStr(name, 5), {Set: wrapper})
                    continue
                }
            }
            AddMethodOverloadTo(w, name, wrapper, classname ".")
        }
    }
    
    GetTypeDefProps(td, &flags:=0, &basetd:=0) {
        namebuf := Buffer(2*MAX_NAME_CCH)
        ; GetTypeDefProps
        ComCall(12, this, "uint", td
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
            , "uint*", &flags:=0, "uint*", &basetd:=0)
        ; Testing shows namelen includes a null terminator, but the docs aren't
        ; clear, so rely on StrGet's positive-length behaviour to truncate.
        return StrGet(namebuf, namelen, "UTF-16")
    }
    
    GetTypeDefFlags(td) {
        ; GetTypeDefProps
        ComCall(12, this, "uint", td
            , "ptr", 0, "uint", 0, "ptr", 0
            , "uint*", &flags:=0, "ptr", 0)
        return flags
    }
    
    EnumMethods(td)                 => _rt_Enumerator(18, this, "uint", td)
    EnumCustomAttributes(td, tctor) => _rt_Enumerator(53, this, "uint", td, "uint", tctor)
    EnumInterfaceImpls(td)          => _rt_Enumerator(7, this, "uint", td)
    
    Name {
        get {
            namebuf := Buffer(2*MAX_NAME_CCH)
            ; GetScopeProps
            ComCall(10, this, "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0, "ptr", 0)
            return StrGet(namebuf, namelen, "UTF-16")
        }
    }
    
    static GetForTypeName(typename, &mdm, &td) {
        #DllLoad wintypes.dll
        DllCall("wintypes.dll\RoGetMetaDataFile"
            , "ptr", HStringFromString(typename)
            , "ptr", 0
            , "ptr", 0
            , "ptr*", &mdi := 0
            , "uint*", &td := 0
            , "hresult")
        mdm := this(mdi)
    }
}

_rt_Enumerator(methodidx, this, args*) {
    henum := index := count := 0
    ; Getting the items in batches improves performance, with diminishing returns.
    buf := Buffer(4 * batch_size:=32)
    ; Prepare the args for ComCall, with the caller's extra args in the middle.
    args.InsertAt(1, methodidx, this, "ptr*", &henum)
    args.Push("ptr", buf, "uint", batch_size, "uint*", &count)
    ; Call CloseEnum when finished enumerating.
    args.__delete := args => ComCall(3, this, "uint", henum, "int")
    next(&item) {
        if index = count {
            index := 0
            if ComCall(args*) ; S_FALSE (1) means no items.
                return false
        }
        item := NumGet(buf, (index++) * 4, "uint")
        return true
    }
    return next
}

_rt_FindAssemblyRef(mdai, target_name) {
    namebuf := Buffer(2*MAX_NAME_CCH)
    ; EnumAssemblyRefs
    for asm in _rt_Enumerator(8, mdai) {
        ; GetAssemblyRefProps
        ComCall(4, mdai , "uint", asm, "ptr", 0, "ptr", 0
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
            , "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0)
        if StrGet(namebuf, namelen, "UTF-16") = target_name
            return asm
    }
    return 0
}

_rt_CacheAttributeCtors(mdi, o, retprop) {
    mdai := ComObjQuery(mdi, "{EE62470B-E94B-424e-9B7C-2F00C9249F93}") ; IID_IMetaDataAssemblyImport
    ; Currently we assume if there's no reference to Windows.Foundation,
    ; the current scope of mdi (mdModule(1)) is Windows.Foundation.
    asm := _rt_FindAssemblyRef(mdai, "Windows.Foundation") || 1
    
    DefOnce(o, n, v) {
        if o.HasOwnProp(n)  ; We currently only support one constructor overload for each usage.
            throw Error("Conflicting constructor found for " n, -1)
        o.DefineProp n, {value: v}
    }
    
    ; FindTypeRef
    ComCall(55, mdi, "uint", asm, "wstr", "Windows.Foundation.Metadata.StaticAttribute"
        , "uint*", &tr:=0)
    ; EnumMemberRefs
    for mr in _rt_Enumerator(23, mdi, "uint", tr) {
        ; GetMemberRefProps
        ComCall(31, mdi, "uint", mr, "uint*", &ttype:=0, "ptr", 0, "uint", 0, "ptr", 0, "ptr", 0, "ptr", 0)
        DefOnce o, 'StaticAttr', mr
    }
    
    ; FindTypeRef
    ComCall(55, mdi, "uint", asm, "wstr", "Windows.Foundation.Metadata.ActivatableAttribute"
        , "uint*", &tr:=0)
    ; EnumMemberRefs
    for mr in _rt_Enumerator(23, mdi, "uint", tr) {
        ; GetMemberRefProps
        ComCall(31, mdi, "uint", mr, "uint*", &ttype:=0
            , "ptr", 0, "uint", 0, "ptr", 0
            , "ptr*", &psig:=0, "uint*", &nsig:=0)
        if NumGet(psig, 3, "uchar") = 9 ; uint
            DefOnce o, 'ActivatableAttr', mr
        else
            DefOnce o, 'FactoryAttr', mr
    }
    
    return o.%retprop%
}

class RtMarshal {
    static __new() {
        this.Classes := Map()
        this.Classes.CaseSense := "off"
    }
    static String := {
        I: HStringFromString,
        O: _rt_HStringRet,
        T: "ptr"
    }
    static Char16 := {
        I: Ord,
        O: Chr,
        T: "ushort"
    }
    static Boolean := {
        I: v => !!v,
        O: v => v,
        T: "char"
    }
    static Object := {
        I: v => v, ; TODO: validate type
        O: ObjBindMethod(ComValue,, 13), ; TODO: wrap runtime type
        T: "ptr"
    }
    static Void := {}
}

GetMarshalForClass(classname) =>
    RtMarshal.Classes.get(classname, 0) ||
    RtMarshal.Classes[classname] := {
        T: "ptr",
        I: v => v, ; TODO: validate type
        O: WinRT._GetWrapFn(classname)
    }

DecodeSigType(mdi, &p, genericTypes:=false) {
    static primitives := Map(
        0x01, RtMarshal.Void,
        0x02, RtMarshal.Boolean,
        0x03, RtMarshal.Char16,
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
        0x0e, RtMarshal.String,
        0x18, "ptr",
        0x19, "uptr",
        0x1c, RtMarshal.Object,
    )
    b := NumGet(p++, "uchar")
    if "" != (t := primitives.get(b, ""))
        return t
    switch b {
        case 0x0f: ; ptr
            ; return DecodeSigType(mdi, &p) '*'
            throw Error("pointer type not handled")
        case 0x10: ; ref
            t := DecodeSigType(mdi, &p) '&'
            ; throw Error("ref type not handled")
            D '- unhandled ref type ' t
            return t
        case 0x1D: ; array
            t := DecodeSigType(mdi, &p) '[]'
            ; throw Error("array type not handled")
            D '- unhandled array type ' t
            return t
        ; case 0x11, 0x12: ; value type, class type
        case 0x11: ; value type
            t := RegExReplace(GetTypeRefProps(mdi, CorSigUncompressToken(&p), &scope)
                , "^(Windows|System)\.(.*\.)?") (b=0x11 ? "^" : "")
            D '- unhandled value type ' t
            return "ptr" ; incorrect and unsafe for structs!
        case 0x12: ; class type
            t := GetTypeRefProps(mdi, CorSigUncompressToken(&p))
            return GetMarshalForClass(t)
        case 0x13: ; generic type parameter
            ; return 'T' (NumGet(p++, "uchar") + 1)
            if genericTypes {
                return genericTypes[NumGet(p++, "uchar") + 1]
            }
            ; throw Error("generic type parameter not handled")
            D '- unhandled generic type parameter #' (NumGet(p++, "uchar") + 1)
            return "ptr"
        case 0x15: ; GENERICINST <generic type> <argCnt> <arg1> ... <argn>
            t := RegExReplace(DecodeMethodSigType(mdi, &p), '``\d+$') '<'
            Loop argc := NumGet(p++, "uchar")
                t .= (A_Index>1 ? ',' : '') . DecodeMethodSigType(mdi, &p)
            t .= '>'
            ; return t
            ; throw Error("generic type not handled",, t)
            D '- unhandled generic type ' t
            return "ptr"
    }
    ; return Format("{:02x}", b)
    throw Error("type not handled",, Format("{:02x}", b))
}

DecodeSig(mdi, p, size, genericTypes:=false) {
    if size < 3
        throw Error("Invalid signature")
    cconv := NumGet(p++, "uchar")
    argc := NumGet(p++, "uchar") + 1 ; +1 for return type
    return DecodeSigTypes(mdi, p, size - 2, argc, genericTypes)
}

DecodeSigTypes(mdi, p, size, count, genericTypes:=false) {
    types := [], p2 := p + size
    while p < p2 {
        types.Push(DecodeSigType(mdi, &p, genericTypes))
        --count
    }
    if p != p2 || count
        throw Error("Signature decoding error")
    return types
}

MethodWrapper(idx, iid, types, name:=unset) {
    rettype := types.RemoveAt(1)
    cca := [], cca.Length := 1 + 2*types.Length
    fa := [], fa.Length := types.Length + 1
    fa[1] := ComObjQuery.Bind( , iid)
    if types.Length {
        for t in types {
            if t is String 
                cca[2*A_Index] := t
            else {
                fa[1+A_Index] := t.I
                cca[2*A_Index] := t.T
            }
        }
    }
    if rettype != RtMarshal.Void {
        if rettype is String
            cca.Push(rettype '*'), fr := Number
        else
            cca.Push(rettype.T '*'), fr := rettype.O
    }
    fc := ComCall.Bind(idx, cca*)
    if IsSet(name)
        fc.DefineProp 'Name', {value: name}  ; For our use debugging; has no effect on any built-in stuff.
    fc := IsSet(fr)
        ? _rt_filter_call_a_r.Bind(fc, fa, fr)
        : _rt_filter_call_a.Bind(fc, fa)
    fc.DefineProp 'MinParams', pv := {value: 1 + types.Length}  ; +1 for `this`
    fc.DefineProp 'MaxParams', pv
    return fc
}

; fc := ComCall.Bind(idx, , "ptr", , "ptr*", )
; _rt_filter_call_a_r.Bind(fc, [HString.s.Bind(HString)], _rt_HStringRet)

_rt_filter_call_a_r(fc, fa, fr, args*) {
    try {
        for f in fa
            IsSet(f) && args[A_Index] := f(args[A_Index])
        return (args.Push(&rv:=0), fc(args*), fr(rv))
    } catch as e {
        e.message .= "`n`nSource: " fc.Name
        throw
    }
}

_rt_filter_call_a(fc, fa, args*) {
    for f in fa
        IsSet(f) && args[A_Index] := f(args[A_Index])
    return (fc(args*), "")
}

_rt_filter_call_r(fc, fr, args*) {
    return (args.Push(&rv:=0), fc(args*), fr(rv))
}

_rt_HStringRet(hstr) {
	p := DllCall("combase.dll\WindowsGetStringRawBuffer", "ptr", hstr, "uint*", &len:=0, "ptr")
    DllCall("combase.dll\WindowsDeleteString", "ptr", hstr)
	return StrGet(p, -len, "UTF-16")
}

class RtClass extends Class {
    static __new() {
        this.prototype.ptr := 0
    }
    __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
}

class RtObject extends Object {
    static __new() {
        this.ptr := 0
        this.prototype.ptr := 0
        this.prototype.DefineProp('__delete', {Call: this.__delete})
    }
    static __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
}

_rt_GetParameterizedIID(names) {
    static pfn := CallbackCreate(_rt_MetaDataLocate, "F")
    ; Make an array of pointers to the names.  StrPtr(names[1]) would return
    ; the address of a temporary string, so make more direct copies.
    namePtrArr := Buffer(A_PtrSize * names.Length)
    nameStr := ""
    for name in names
        nameStr .= name "|"
    pStr := StrPtr(nameStr := RTrim(nameStr, "|"))
    Loop Parse nameStr, "|" {
        NumPut("ptr", pStr, namePtrArr, (A_Index-1)*A_PtrSize)
        pStr := NumPut("ushort", 0, pStr += 2 * StrLen(A_LoopField))
    }
    DllCall("combase.dll\RoGetParameterizedTypeInstanceIID"
        , "uint", names.Length, "ptr", namePtrArr
        , "ptr*", pfn  ; Locator interface (only one virtual method, so passed with *).
        , "ptr", oiid := GUID(), "ptr*", &pextra:=0, "hresult")
    DllCall("combase.dll\RoFreeParameterizedTypeExtra"
        , "ptr", pextra)
    return oiid
}

_rt_MetaDataLocate(pname, mdb) {
    name := StrGet(pname, "UTF-16")
    ; mdb : IRoSimpleMetaDataBuilder -- unconventional interface with no base type
    try {
        MetaDataModule.GetForTypeName(name, &mdm, &td)
        typename := mdm.GetTypeDefProps(td, &flags)
        if flags & 0x20 { ; tdInterface
            if ComCall(60, mdm, "uint", td, "wstr", "Windows.Foundation.Metadata.GuidAttribute"
                    , "ptr*", &pguid:=0, "ptr", 0) != 0
                throw Error("GUID not found for " name)
            if p := InStr(name, "``") {
                ; SetParameterizedInterface
                ComCall(8, mdb, "ptr", pguid, "uint", SubStr(name, p + 1))
            }
            else {
                ; SetWinRtInterface
                ComCall(0, mdb, "ptr", pguid)
            }
        }
        else {
            c := WinRT._GetClass(name)
            ; SetRuntimeClassSimpleDefault
            ComCall(4, mdb, "ptr", pname, "wstr", c.prototype.__DefaultIName
                , "ptr", c.prototype.__DefaultIID)
        }
    }
    catch as e {
        D '- ' type(e) ' locating metadata for "' name '": ' e.message
        return 0x80004005 ; E_FAIL
    }
    return 0
}