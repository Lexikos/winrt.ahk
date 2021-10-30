
class RtMetaDataItem {
    __new(mdm, token) {
        this.m := mdm
        this.t := token
    }
}

class RtRootTypeInfo {
    __new(name, baseType, cls:=unset) {
        this.Name := name
        this.BaseType := baseType
        IsSet(cls) && this.Class := cls
    }
    ToString() => this.Name
    FundamentalType => this
    static ValueType := RtRootTypeInfo("ValueType", 0)
    static   Enum := RtRootTypeInfo("Enum", this.ValueType)
    static RefType := RtRootTypeInfo("RefType", 0)
    static   Object := RtRootTypeInfo("Object", this.RefType, RtObject)
    static   Delegate := RtRootTypeInfo("Delegate", this.RefType)
    static   Interface := RtRootTypeInfo("Interface", this.RefType, RtObject)
    static Attribute := RtRootTypeInfo("Attribute", 0)  ; Used only as metadata.
}

class RtTypeInfo extends RtMetaDataItem {
    __new(mdm, token, typeArgs:=false) {
        super.__new(mdm, token)
        this.typeArgs := typeArgs
    }

    static cache := Map(
        ; All WinRT typedefs tested on Windows 10.0.19043 derive from one of these.
        ; System.Guid might also be used in parameters, but isn't implemented yet.
        "System.Attribute", RtRootTypeInfo.Attribute,
        "System.Enum", RtRootTypeInfo.Enum,
        "System.MulticastDelegate", RtRootTypeInfo.Delegate,
        "System.Object", RtRootTypeInfo.Object,
        "System.ValueType", RtRootTypeInfo.ValueType,
    )
    static __new() {
        if this != RtTypeInfo
            return
        cache := this.cache
        for e, t in RtMarshal.SimpleType {
            cache[t.N] := t
        }
    }
    
    Name => this.ToString()
    
    ToString() {
        name := this.m.GetTypeDefProps(this.t)
        if this.typeArgs {
            for t in this.typeArgs
                name .= (A_Index=1 ? '<' : ',') . String(t)
            name .= '>'
        }
        return name
    }
    
    BaseType => _rt_memoize(this, 'BaseType')
    _init_BaseType() {
        this.m.GetTypeDefProps(this.t, &flags, &tbase)
        switch {
            case flags & 0x20:
                return RtRootTypeInfo.Interface
            case (tbase & 0x00ffffff) = 0:  ; Nil token.
                throw Error(Format('Type "{}" has no base type or interface flag (flags = 0x{:x})', this.Name, flags))
            default:
                return WinRT.GetTypeByToken(this.m, tbase)
        }
    }

    IsInterface => this.BaseType = RtRootTypeInfo.Interface
    FundamentalType => this.BaseType.FundamentalType
    
    GUID => _rt_memoize(this, 'GUID')
    _init_GUID() => this.typeArgs
        ? _rt_GetParameterizedIID(this.m.GetTypeDefProps(this.t), this.typeArgs)
        : this.m.GetGuidPtr(this.t)
    
    ; Whether this class type supports direct activation (IActivationFactory).
    HasIActivationFactory => _rt_Enumerator(53, this.m, "uint", this.t, "uint", this.m.ActivatableAttr)(&_)
    ; Enumerate factory interfaces of this class type.
    Factories() => _rt_EnumAttrWithTypeArg(this.m, this.t, this.m.FactoryAttr)
    ; Enumerate composition factory interfaces of this class type.
    Composers() => _rt_EnumAttrWithTypeArg(this.m, this.t, this.m.ComposableAttr)
    ; Enumerate static member interfaces of this class type.
    Statics() => _rt_EnumAttrWithTypeArg(this.m, this.t, this.m.StaticAttr)
    
    ; Enumerate fields of this struct/enum type.
    Fields() {
        namebuf := Buffer(2*MAX_NAME_CCH)
        getinfo(&f) {
            ; GetFieldProps
            ComCall(57, this.m, "uint", ft := f, "ptr", 0
                , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
                , "ptr*", &flags:=0, "ptr*", &psig:=0, "uint*", &nsig:=0
                , "ptr", 0, "ptr", 0, "ptr", 0)
            f := {
                flags: flags,
                name: StrGet(namebuf, namelen, "UTF-16"),
                ; Signature should be CALLCONV_FIELD (6) followed by a single type.
                type: _rt_DecodeSigType(this.m, &p:=psig+1, psig+nsig, this.typeArgs),
            }
            if flags & 0x8000 ; fdHasDefault
                f.value := _rt_GetFieldConstant(this.m, ft)
        }
        ; EnumFields
        return _rt_Enumerator_f(getinfo, 20, this.m, "uint", this.t)
    }
    
    ; Enumerate methods of this interface/class type.
    Methods() {
        namebuf := Buffer(2*MAX_NAME_CCH)
        resolve_method(&m) {
            ; GetMethodProps
            ComCall(30, this.m, "uint", m, "ptr", 0
                , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
                , "uint*", &attr:=0
                , "ptr*", &psig:=0, "uint*", &nsig:=0 ; signature blob
                , "ptr", 0, "ptr", 0)
            m := {
                name: StrGet(namebuf, namelen, "UTF-16"),
                flags: attr, ; CorMethodAttr
                sig: {ptr: psig, size: nsig}
            }
        }
        return _rt_Enumerator_f(resolve_method, 18, this.m, "uint", this.t)
    }
    
    ; Decode a method signature and return [return type, parameter types*].
    MethodArgTypes(sig) {
        if (NumGet(sig, 0, "uchar") & 0x0f) > 5
            throw ValueError("Invalid method signature", -1)
        return _rt_DecodeSig(this.m, sig.ptr, sig.size, this.typeArgs)
    }
    
    Implements() {
        ; EnumInterfaceImpls
        next_inner := _rt_Enumerator(7, this.m, "uint", this.t)
        next_outer(&typeinfo, &impltoken:=unset) {
            if !next_inner(&impltoken)
                return false
            ; GetInterfaceImplProps
            ComCall(13, this.m, "uint", impltoken, "ptr", 0, "uint*", &t:=0)
            typeinfo := WinRT.GetTypeByToken(this.m, t, this.typeArgs)
            return true
        }
        return next_outer
    }

    ; Marshalling
    Marshal => _rt_memoize(this, 'Marshal')
    _init_Marshal() {
        local proto
        ; FIXME: use OOP for this, not switch
        switch (String(this.FundamentalType)) {
        case "Interface":
            ; Attempt to get runtime class (at runtime) to make all methods
            ; available.  This sometimes fails for generic interfaces, so pass
            ; the interface as a default type to wrap.
            return RtMarshal.Info({
                T: "ptr",
                O: _rt_WrapInspectable.Bind(, this)
            })
        case "Object":
            return RtMarshal.Info({
                T: "ptr",
                O: WrapClass(p) => p && {
                    ptr: p,
                    base: IsSet(proto) ? proto : proto := this.Class.prototype
                }
            })
        case "Enum":
            return RtMarshal.Info({
                T: "uint",
                O: this.Class,
                I: this.Class.Parse.Bind(this.Class)
            })
        case "ValueType":
            return _init_ValueType_Marshal()
        case "Delegate":
            ; TODO: implement delegate support
            D '! delegate type {} will be treated as ptr', this.Name
            return RtMarshal.Info({T: "ptr"})
        }
        _init_ValueType_Marshal() {
            local cls := this.Class
            local size := cls.prototype.Size
            if size = 8 || size = 4 {
                local nt := size > A_PtrSize ? "int64" : "ptr"
                return RtMarshal.Info({
                    T: nt,
                    I: NumGet.Bind( , nt),
                    O: n => (
                        NumPut("int64", n, newstruct := cls()),
                        newstruct
                    )
                })
            }
            ; else if size < 8
            else {
                throw Error("Struct of size " size " not supported.",, String(this))
            }
        }
        unsupported_type(mode, *) {
            throw Error(Format('{} type "{}" is not supported', mode, String(this)), -2)
        }
        D 'Unsupported - {} : {}', String(this), String(this.FundamentalType)
        return RtMarshal.Info({T: "ptr", I: unsupported_type.Bind("Parameter"), O: unsupported_type.Bind("Return")})
    }

    Class => _rt_memoize(this, 'Class')
    _init_Class() {
        d_scope(&dbg, this.Name)
        switch (String(this.FundamentalType)) {
            case "Interface": return this.m.CreateInterfaceWrapper(this)
            case "Object": return this.m.CreateClassWrapper(this)
            case "Enum": return _rt_CreateEnumWrapper(this)
            case "ValueType": return _rt_CreateStructWrapper(this)
        }
        throw PropertyError("Class property not valid for " String(this.FundamentalType))
    }
}

class RtDecodedType {
}

class RtTypeArg extends RtDecodedType {
    __new(n) {
        this.index := n
    }
    ToString() => "T" this.index
}

class RtTypeMod extends RtDecodedType {
    __new(inner) {
        this.inner := inner
    }
}

class RtPtrType extends RtTypeMod {
    ; static prototype.T := "ptr"
    ToString() => String(this.inner) "*"
}

class RtRefType extends RtTypeMod {
    ; TODO: check in/out-ness instead of IsSet
    static prototype.I := (&v) => isSet(v) ? &v : &v := 0
    T => this.inner.T '*'
    ToString() => String(this.inner) "&"
}

class RtArrayType extends RtTypeMod {
    T => 'Unsupported'
    ToString() => String(this.inner) "[]"
}

_rt_EnumAttrWithTypeArg(mdi, t, attr) {
    attrToType(&v) {
        ; GetCustomAttributeProps
        ComCall(54, mdi, "uint", v
            , "ptr", 0, "ptr", 0, "ptr*", &pdata:=0, "uint*", &ndata:=0)
        v := WinRT.GetType(getArg1String(pdata))
    }
    getArg1String(pdata) {
        return StrGet(pdata + 3, NumGet(pdata + 2, "uchar"), "utf-8")
    }
    ; EnumCustomAttributes := 53
    return _rt_Enumerator_f(attrToType, 53, mdi, "uint", t, "uint", attr)
}

_rt_DecodeSig(m, p, size, typeArgs:=false) {
    if size < 3
        throw Error("Invalid signature")
    p2 := p + size
    cconv := NumGet(p++, "uchar")
    argc := NumGet(p++, "uchar") + 1 ; +1 for return type
    return _rt_DecodeSigTypes(m, &p, p2, argc, typeArgs)
}

_rt_DecodeSigTypes(m, &p, p2, count, typeArgs:=false) {
    if p > p2
        throw ValueError("Bad params", -1)
    types := []
    while p < p2 && count {
        types.Push(_rt_DecodeSigType(m, &p, p2, typeArgs))
        --count
    }
    ; > vs != is less robust, but some callers want a subset of a signature.
    if p > p2
        throw Error("Signature decoding error")
    return types
}

_rt_DecodeSigGenericInst(m, &p, p2, typeArgs:=false) {
    if p > p2
        throw ValueError("Bad params", -1)
    baseType := _rt_DecodeSigType(m, &p, p2, typeArgs)
    types := []
    types.Capacity := count := NumGet(p++, "uchar")
    while p < p2 && count {
        types.Push(_rt_DecodeSigType(m, &p, p2, typeArgs))
        --count
    }
    if p > p2
        throw Error("Signature decoding error")
    ; FIXME: cache generic instance
    return {
        typeArgs: types,
        m: baseType.m, t: baseType.t,
        base: baseType.base
        ; base: baseType -- not doing this because most of the cached properties
        ; need to be recalculated for the generic instance, GUID in particular.
    }
}

_rt_DecodeSigType(m, &p, p2, typeArgs:=false) {
    ; FIXME: replace RtMarshal primitives?
    static primitives := RtMarshal.SimpleType
    static modifiers := Map(
        0x0f, RtPtrType,
        0x10, RtRefType,
        0x1D, RtArrayType,
    )
    b := NumGet(p++, "uchar")
    if t := primitives.get(b, 0)
        return t
    if modt := modifiers.get(b, 0)
        return modt(_rt_DecodeSigType(m, &p, p2, typeArgs))
    switch b {
        case 0x11, 0x12: ; value type, class type
            return WinRT.GetTypeByToken(m, CorSigUncompressToken(&p))
        case 0x13: ; generic type parameter
            if typeArgs
                return typeArgs[NumGet(p++, "uchar") + 1]
            return RtTypeArg(NumGet(p++, "uchar") + 1)
        case 0x15: ; GENERICINST <generic type> <argCnt> <arg1> ... <argn>
            return _rt_DecodeSigGenericInst(m, &p, p2, typeArgs)
        case 0x1F, 0x20: ; CMOD <typeDef/Ref> ...
            modt := m.GetTypeRefProps(CorSigUncompressToken(&p))
            D '! unhandled modifier ' modt
            return _rt_DecodeSigType(m, &p, p2, typeArgs)
    }
    throw Error("type not handled",, Format("{:02x}", b))
}
