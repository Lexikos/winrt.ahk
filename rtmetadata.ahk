
class MetaDataModule {
    ptr := 0
    __delete() {
        (p := this.ptr) && ObjRelease(p)
    }
    StaticAttr => _rt_CacheAttributeCtors(this, this, 'StaticAttr')
    FactoryAttr => _rt_CacheAttributeCtors(this, this, 'FactoryAttr')
    ActivatableAttr => _rt_CacheAttributeCtors(this, this, 'ActivatableAttr')
    ComposableAttr => _rt_CacheAttributeCtors(this, this, 'ComposableAttr')
    
    ObjectTypeRef => _rt_memoize(this, 'ObjectTypeRef')
    _init_ObjectTypeRef() {
        mdai := ComObjQuery(this, "{EE62470B-E94B-424e-9B7C-2F00C9249F93}") ; IID_IMetaDataAssemblyImport
        asm := _rt_FindAssemblyRef(mdai, "mscorlib") || 1
        ; FindTypeRef
        if ComCall(55, this, "uint", asm, "wstr", "System.Object", "uint*", &tr:=0, "int") != 0 {
            D '- System.Object not found'
            return -1
        }
        return tr
    }
    
    AddFactoriesToWrapper(w, t) {
        if t.HasIActivationFactory {
            this.AddIActivationFactoryToWrapper(w)
        }
        for f in t.Factories() {
            this.AddInterfaceToWrapper(w, f, false, "Call")
        }
        for f in t.Composers() {
            this.AddInterfaceToWrapper(w, f, false, "Call")
            if w.HasOwnProp("Call")
                AddMethodOverloadTo(w, "Call", w => w(0, 0), w.prototype.__class ".")
        }
    }
    
    AddIActivationFactoryToWrapper(w) {
        ActivateInstance(cls) {
            ComCall(6, ComObjQuery(cls, "{00000035-0000-0000-C000-000000000046}") ; IActivationFactory
                , "ptr*", inst := {base: cls.prototype})
            return inst
        }
        AddMethodOverloadTo(w, "Call", ActivateInstance, w.prototype.__class ".")
    }
    
    CreateInterfaceWrapper(t) {
        w := _rt_CreateClass(t.Name, RtObject)
        this.AddInterfaceToWrapper(w.prototype, t, true)
        addreq(w.prototype, t)
        addreq(w, t) {
            for impl in t.Implements() {
                impl.m.AddInterfaceToWrapper(w, impl, false)
                addreq(w, impl)
            }
        }
        return w
    }
    
    CreateClassWrapper(t) {
        if (baseclass := t.BaseType).HasProp('Class')
            baseclass := baseclass.Class
        else
            throw Error("This type is not a class",, String(baseclass))
        w := _rt_CreateClass(classname := t.Name, baseclass)
        ; Add any constructors:
        this.AddFactoriesToWrapper(w, t)
        ; Add static interfaces to the class:
        for ti in t.Statics() {
            this.AddInterfaceToWrapper(w, ti)
        }
        ; Need a factory?
        if ObjOwnPropCount(w) > 1 {
            static oiid := GUID("{AF86E2E0-B12D-4c6a-9C5A-D7AA65101E90}") ; IInspectable
            hr := DllCall("combase.dll\RoGetActivationFactory"
                , "ptr", HStringFromString(classname)
                , "ptr", oiid
                , "ptr*", w, "hresult")
        }
        wrapped := Map()
        addRequiredInterfaces(wp, t, isclass) {
            for ti, impl in t.Implements() {
                ; GetCustomAttributeByName
                isdefault := isclass && ComCall(60, this, "uint", impl
                    , "wstr", "Windows.Foundation.Metadata.DefaultAttribute"
                    , "ptr", 0, "ptr", 0) = 0
                if isdefault
                    t.DefineProp 'DefaultInterface', {value: ti}
                if wrapped.has(ti_name := ti.Name)
                    continue
                wrapped[ti_name] := true
                ti.m.AddInterfaceToWrapper(wp, ti, isdefault)
                ; Interfaces "required" by ti are also implemented by the class
                ; even if it doesn't "require" them directly (sometimes it does).
                addRequiredInterfaces(wp, ti, false)
            }
        }
        ; Add instance interfaces:
        addRequiredInterfaces(w.prototype, t, true)
        return w
    }
    
    AddInterfaceToWrapper(w, t, isdefault:=false, nameoverride:=false) {
        pguid := t.GUID
        if !pguid {
            D "- interface {:x} can't be added; no GUID", t.Name
            return
        }
        namebuf := Buffer(2*MAX_NAME_CCH)
        DllCall("ole32\StringFromGUID2", "ptr", pguid, "ptr", namebuf, "int", MAX_NAME_CCH)
        iid := StrGet(namebuf)
        d_scope(&dbg, iid ' ' t.Name)
        name_prefix := w.HasOwnProp('prototype') ? w.prototype.__class ".Prototype." : w.__class "."
        for method in t.Methods() {
            name := nameoverride ? nameoverride : method.name
            D name DecodeMethodSig(this, method.sig.ptr, method.sig.size)
            ; TODO: signature abstraction?
            types := _rt_DecodeSig(this, method.sig.ptr, method.sig.size, t.typeArgs)
            wrapper := MethodWrapper(5 + A_Index, iid, types, name_prefix name)
            if method.flags & 0x400 { ; tdSpecialName
                switch SubStr(name, 1, 4) {
                case "get_":
                    w.DefineProp(SubStr(name, 5), {Get: wrapper})
                    continue
                case "put_":
                    w.DefineProp(SubStr(name, 5), {Set: wrapper})
                    continue
                }
            }
            AddMethodOverloadTo(w, name, wrapper, name_prefix)
        }
    }
    
    FindTypeDefByName(name) {
        ComCall(9, this, "wstr", name, "uint", 0, "uint*", &r:=0)
        return r
    }
    
    GetTypeDefProps(td, &flags:=0, &basetd:=0) {
        namebuf := Buffer(2*MAX_NAME_CCH)
        ; GetTypeDefProps
        ComCall(12, this, "uint", td
            , "ptr", namebuf, "uint", namebuf.Size//2, "uint*", &namelen:=0
            , "uint*", &flags:=0, "uint*", &basetd:=0)
        ; Testing shows namelen includes a null terminator, but the docs aren't
        ; clear, so rely on StrGet's positive-length behaviour to truncate.
        return StrGet(namebuf, namelen, "UTF-16")
    }
    
    GetTypeRefProps(r, &scope:=unset) {
        namebuf := Buffer(2*MAX_NAME_CCH)
        ComCall(14, this, "uint", r, "uint*", &scope:=0
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0)
        return StrGet(namebuf, namelen, "UTF-16")
    }
    
    GetGuidPtr(td) {
        ; GetCustomAttributeByName
        if ComCall(60, this, "uint", td
            , "wstr", "Windows.Foundation.Metadata.GuidAttribute"
            , "ptr*", &pguid:=0, "uint*", &nguid:=0) != 0
            return 0
        ; Attribute is serialized with leading 16-bit version (1) and trailing 16-bit number of named args (0).
        if nguid != 20
            throw Error("Unexpected GuidAttribute data length: " nguid)
        return pguid + 2
    }
    
    EnumMethods(td)                 => _rt_Enumerator(18, this, "uint", td)
    EnumCustomAttributes(td, tctor) => _rt_Enumerator(53, this, "uint", td, "uint", tctor)
    EnumTypeDefs()                  => _rt_Enumerator(6, this)
    EnumInterfaceImpls(td)          => _rt_Enumerator(7, this, "uint", td)
    
    Name {
        get {
            namebuf := Buffer(2*MAX_NAME_CCH)
            ; GetScopeProps
            ComCall(10, this, "ptr", namebuf, "uint", namebuf.Size//2, "uint*", &namelen:=0, "ptr", 0)
            return StrGet(namebuf, namelen, "UTF-16")
        }
    }
    
    static Open(path) {
        #DllLoad rometadata.dll
        DllCall("rometadata.dll\MetaDataGetDispenser"
            , "ptr", CLSID_CorMetaDataDispenser, "ptr", IID_IMetaDataDispenser
            , "ptr*", mdd := ComValue(13, 0), "hresult")
        ; IMetaDataDispenser::OpenScope
        ComCall(4, mdd, "wstr", path, "uint", 0
            , "ptr", IID_IMetaDataImport
            , "ptr*", mdm := MetaDataModule())
        return mdm
    }
}

_rt_Enumerator(args*) => _rt_Enumerator_f(false, args*)

_rt_Enumerator_f(f, methodidx, this, args*) {
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
        (f) && f(&item)
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
            , "ptr", namebuf, "uint", namebuf.Size//2, "uint*", &namelen:=0
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
    
    defOnce(o, n, v) {
        if o.HasOwnProp(n)  ; We currently only support one constructor overload for each usage.
            && o.%n% != v
            throw Error("Conflicting constructor found for " n, -1)
        o.DefineProp n, {value: v}
    }
    
    searchFor(attrType, nameForSig) {
        ; FindTypeRef
        if ComCall(55, mdi, "uint", asm, "wstr", attrType, "uint*", &tr:=0, "int") != 0 {
            defOnce(o, nameForSig(0), -1)
            return
        }
        ; EnumMemberRefs
        for mr in _rt_Enumerator(23, mdi, "uint", tr) {
            ; GetMemberRefProps
            ComCall(31, mdi, "uint", mr, "uint*", &ttype:=0
                , "ptr", 0, "uint", 0, "ptr", 0
                , "ptr*", &psig:=0, "uint*", &nsig:=0)
            defOnce(o, nameForSig(psig), mr)
        }
        else {
            defOnce(o, nameForSig(0), -1)
            D '- no {} memberref in {}', attrType, o.name
        }
    }
    
    searchFor("Windows.Foundation.Metadata.StaticAttribute"
        , psig => 'StaticAttr')
    
    searchFor("Windows.Foundation.Metadata.ActivatableAttribute"
        , psig => NumGet(psig, 3, "uchar") = 9 ? 'ActivatableAttr' : 'FactoryAttr') ; 9 = uint (first arg is uint, not interface name)
    
    searchFor("Windows.Foundation.Metadata.ComposableAttribute"
        , psig => 'ComposableAttr')
    
    return o.%retprop%
}

_rt_GetFieldConstant(mdi, field) {
    mdt := ComObjQuery(mdi, "{D8F579AB-402D-4B8E-82D9-5D63B1065C68}") ; IMetaDataTables
    
    static tabConstant := 11, GetTableInfo := 9
    ComCall(GetTableInfo, mdt, "uint", tabConstant
        , "uint*", &cbRows := 0, "uint*", &cRows := 0
        , "uint*", &cCols := 0, "uint*", &iKey := 0
        , "ptr", 0)
    
    static colType := 0, colParent := 1, colValue := 2, GetColumn := 13, GetBlob := 15
    Loop cRows {
        ComCall(GetColumn, mdt, "uint", tabConstant, "uint", colParent, "uint", A_Index, "uint*", &value:=0)
        if value != field
            continue
        ComCall(GetColumn, mdt, "uint", tabConstant, "uint", colValue, "uint", A_Index, "uint*", &value:=0)
        ComCall(GetBlob, mdt, "uint", value, "uint*", &ndata:=0, "ptr*", &pdata:=0)
        ComCall(GetColumn, mdt, "uint", tabConstant, "uint", colType, "uint", A_Index, "uint*", &value:=0)
        ; Type must be one of the basic element types (2..14) or CLASS (18) with value 0.
        ; WinRT only uses constants for enums, always I4 (8) or U4 (9).
        return RtMarshal.SimpleType[value].GetReader()(pdata)
        ;return {ptr: pdata, size: ndata}
    }
}

class RtMarshal {
    static __new() {
        this.Classes := Map()
        this.Classes.CaseSense := "off"
        this.SimpleType := st := Map()
        for t in [
            {E: 0x1, N: "Void"},
            {E: 0x2, Size: 1, N: "Boolean", T: "char", I: (v => !!v)},
            {E: 0x3, Size: 2, N: "Char16", T: "ushort", I: Ord, O: Chr},
            {E: 0x4, Size: 1, N: "Int8", T: "char"},
            {E: 0x5, Size: 1, N: "UInt8", T: "uchar"},
            {E: 0x6, Size: 2, N: "Int16", T: "short"},
            {E: 0x7, Size: 2, N: "UInt16", T: "ushort"},
            {E: 0x8, Size: 4, N: "Int32", T: "int"},
            {E: 0x9, Size: 4, N: "UInt32", T: "uint"},
            {E: 0xa, Size: 8, N: "Int64", T: "int64"},
            {E: 0xb, Size: 8, N: "UInt64", T: "uint64"},
            {E: 0xc, Size: 4, N: "Single", T: "float"},
            {E: 0xd, Size: 8, N: "Double", T: "double"},
            {E: 0xe, Size: A_PtrSize, N: "String", T: "ptr"
                , I: HStringFromString, O: HStringRet
                , Iw: WindowsCreateString, Ow: WindowsGetString, Del: WindowsDeleteString},
            {E: 0x18, Size: A_PtrSize, N: "IntPtr", T: "ptr"},
            {E: 0x1c, N: "Object", T: "ptr", O: _rt_WrapInspectable},
            ] {
            this.%t.N% := st[t.E] := RtMarshal.Info(t)
        }
        this._IntPtr := RtMarshal.%'Int' A_PtrSize*8%
    }
    
    class Info {
        static Call(t) {
            t.base := this.prototype
            return t
        }
        ToString() => this.N
        GetReader(offset:=0) {
            if this.HasProp('Ow')
                return ((o,t,f,p) => f(NumGet(p,o,t))).Bind(offset, this.T, this.Ow)
            if this.HasProp('O')
                throw Error("Unsupported (has .O)", -1)
            return NumGet.Bind( , offset, this.T)
        }
        GetWriter(offset:=0) {
            numtype := this.T, inp := this.HasProp('Iw') ? this.Iw : this.HasProp('I') ? this.I : ""
            return inp ? (ptr, value) => NumPut(numtype, inp(value), ptr, offset)
                       : (ptr, value) => NumPut(numtype,     value , ptr, offset)
        }
    }
    
    static Ref(t) {
        if t.HasProp('ref')
            return t.ref
        return t.ref := RtMarshal.Info({
            T: t.T "*",
            ; TODO: check in/out-ness instead of IsSet
            I: (&v) => isSet(v) ? &v : &v := 0,
            N: t.N "&" ; For debug only.
        })
    }
}

MethodWrapper(idx, iid, types, name:=unset) {
    rettype := types.RemoveAt(1)
    cca := [], cca.Length := 1 + 2*types.Length
    fa := [], fa.Capacity := types.Length + 1
    if iid
        fa.Push(ComObjQuery.Bind( , iid))
    if types.Length {
        for t in types {
            if t is RtTypeInfo
                t := t.Marshal
            if t is String 
                cca[2*A_Index] := t
            else {
                t.HasProp('I') && fa.Push(t.I)
                cca[2*A_Index] := t.T
            }
        }
    }
    if rettype != RtMarshal.Void {
        if rettype is RtTypeInfo
            rettype := rettype.Marshal
        if rettype is String
            cca.Push(rettype '*'), fr := Number
        else
            cca.Push(rettype.T '*'), fr := rettype.HasProp('O') ? rettype.O : Number
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


_rt_filter_call_a_r(fc, fa, fr, args*) {
    try {
        for f in fa
            IsSet(f) && args[A_Index] := f(args[A_Index])
        return (args.Push(&rv:=0), fc(args*), fr(rv))
    } catch as e {
        e.message .= "`n`nSource: " fc.Name
        ; D '> STACK TRACE`n' e.stack
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


class RtClass extends Class {
    static prototype.ptr := 0
    __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
}

class RtAny {
    static __new() {
        if this = RtAny ; Subclasses will inherit it anyway.
            this.DefineProp('__set', {call: this.prototype.__set})
    }
    static Call(*) {
        throw Error("This class is abstract and cannot be constructed.", -1, this.prototype.__class)
    }
    __set(name, *) {
        throw PropertyError(Format('This value of type "{}" has no property named "{}".', type(this), name), -1)
    }
}

class RtObject extends RtAny {
    static __new() {
        this.DefineProp('ptr', {value: 0})
        this.prototype.DefineProp('ptr', {value: 0})
        this.DefineProp('__delete', {call: this.prototype.__delete})
    }
    __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
}

class RtEnum extends RtAny {
    static Call(n, p*) {
        if e := this.__item.get(n, 0)
            return e
        return {n: n, base: this.prototype}
    }
    static Parse(v) { ; TODO: parse space-delimited strings for flag enums
        if v is this
            return v.n
        if v is Number
            return this[v].n
        if v is String
            return this.%v%.n
        throw TypeError(Format('Value of type "{}" cannot be converted to {}.', type(v), this.prototype.__class), -1)
    }
    s => String(this.n) ; TODO: produce space-delimited strings for flag enums
    ToString() => this.s
}

_rt_CreateClass(classname, baseclass) {
    w := Class()
    w.base := baseclass
    w.prototype := {__class: classname, base: baseclass.prototype}
    return w
}

_rt_CreateEnumWrapper(t) {
    w := _rt_CreateClass(t.Name, RtEnum)
    def(n, v) => w.DefineProp(n, {value: v})
    def '__item', items := Map()
    for f in t.Fields() {
        switch f.flags {
            case 0x601: ; Private | SpecialName | RTSpecialName
                def '__basicType', f.type
            case 0x8056: ; public | static | literal | hasdefault
                def f.name, items[f.value] := {n: f.value, s: f.name, base: w.prototype}
        }
    }
    return w
}

class RtStruct extends RtAny {
    __new(ptr := unset) {
        if !IsSet(ptr) {
            this.DefineProp '__buf', {value: buf := Buffer(Max(this.Size, 8), 0)}
            ptr := buf.ptr
        }
        this.DefineProp 'ptr', {value: ptr}
    }
    static GetInner(offset, outer) {
        inner := this(outer.ptr + offset)
        inner.DefineProp '__outer', {value: outer} ; Keep outer alive.
        return inner
    }
}

_rt_CreateStructWrapper(t) {
    w := _rt_CreateClass(t.Name, RtStruct)
    w.DefineProp 'Call', {call: Object.Call} ; Bypass RtAny.Call.
    wp := w.prototype
    offset := 0, alignment := 1, destructors := []
    for f in t.Fields() {
        ft := f.type
        D '{} {} @{}', String(ft), f.name, offset
        if ft is RtMarshal.Info {
            falign := fsize := ft.Size
            offset := align(offset, fsize)
            wp.DefineProp f.name, {get: ft.GetReader(offset), set: ft.GetWriter(offset)}
            if ft.HasProp('Del')
                destructors.Push(make_primitive_dtor(offset, ft.T, ft.Del))
        }
        else switch ft.FundamentalType.Name {
            case "ValueType":
                wp.DefineProp f.name, {
                    get: RtStruct.GetInner.Bind(w, offset),
                    ; TODO: setter
                }
                fsize := ft.Class.prototype.Size
                falign := ft.Class.__align
            case "Enum":
                wp.DefineProp f.name, make_enum_prop(ft.Class, offset)
                falign := fsize := ft.Class.__basicType.Size
            default:
                throw Error(Format('Unsupported field type {} in struct {}', ft.Name, t.Name))
        }
        if alignment < falign
            alignment := falign
        offset += fsize
    }
    align(n, to) => (n + (to - 1)) // to * to
    w.DefineProp '__align', {value: alignment}
    wp.DefineProp 'Size', {value: align(offset, alignment)}
    if destructors.Length {
        struct_delete(destructors, this) {
            if this.HasProp('__outer') ; Lifetime managed by outer RtStruct.
                return
            for d in destructors
                d(this)
            ; FIXME: call all destructors in the event of any one throwing
        }
        wp.DefineProp '__delete', {call: struct_delete.Bind(destructors)}
    }
    make_primitive_dtor(offset, bt, del) => (
        struct => del(NumGet(struct, offset, bt))
    )
    make_enum_prop(cls, offset) {
        local bt := cls.__basicType.T
        return {
            get: (outer) => cls(NumGet(outer, offset, bt)),
            set: (outer, value) => NumPut(bt, cls.Parse(value), outer, offset)
        }
    }
    return w
}

_rt_GetParameterizedIID(name, types) {
    static vt := Buffer(A_PtrSize)
    static pvt := NumPut("ptr", CallbackCreate(_rt_MetaDataLocate, "F"), vt) - A_PtrSize
    ; Make an array of pointers to the names.  StrPtr(names[1]) would return
    ; the address of a temporary string, so make more direct copies.
    namePtrArr := Buffer(A_PtrSize * (1 + types.Length))
    for t in types
        name .= "|" String(t)
    pStr := StrPtr(name)
    Loop Parse name, "|" {
        NumPut("ptr", pStr, namePtrArr, A_PtrSize * (A_Index-1))
        pStr := NumPut("ushort", 0, pStr += 2 * StrLen(A_LoopField))
    }
    DllCall("combase.dll\RoGetParameterizedTypeInstanceIID"
        , "uint", namePtrArr.Size//A_PtrSize, "ptr", namePtrArr
        , "ptr*", pvt  ; "*" turns it into an "object" on DllCall's stack.
        , "ptr", oiid := GUID(), "ptr*", &pextra:=0, "hresult")
    DllCall("combase.dll\RoFreeParameterizedTypeExtra"
        , "ptr", pextra)
    return oiid
}

_rt_MetaDataLocate(this, pname, mdb) {
    name := StrGet(pname, "UTF-16")
    ; mdb : IRoSimpleMetaDataBuilder -- unconventional interface with no base type
    try {
        t := WinRT.GetType(name)
        if t.IsInterface { ; tdInterface
            if !(pguid := t.GUID)
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
            t := WinRT.GetType(name).DefaultInterface
            ; SetRuntimeClassSimpleDefault
            ComCall(4, mdb, "ptr", pname, "wstr", t.Name, "ptr", t.GUID)
        }
    }
    catch as e {
        D '- ' type(e) ' locating metadata for "' name '": ' e.message
        return 0x80004005 ; E_FAIL
    }
    return 0
}
