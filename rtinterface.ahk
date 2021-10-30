
#include ffi.ahk

class RtTypeInfo {
    __new(mdm, token, typeArgs:=false) {
        this.m := mdm
        this.t := token
        this.typeArgs := typeArgs
        
        ; Determine the base type and corresponding RtTypeInfo subclass.
        mdm.GetTypeDefProps(token, &flags, &tbase)
        switch {
            case flags & 0x20:
                this.base := RtTypeInfo.Interface.Prototype
            case (tbase & 0x00ffffff) = 0:  ; Nil token.
                throw Error(Format('Type "{}" has no base type or interface flag (flags = 0x{:x})', this.Name, flags))
            default:
                basetype := this.m.GetTypeByToken(tbase)
                if basetype is RtTypeInfo
                    this.base := basetype.base
                else
                    this.base := basetype.TypeClass.Prototype
                this.SuperType := basetype
        }
    }
    
    class Interface extends RtTypeInfo {
        Class => this.m.CreateInterfaceWrapper(this)
        ArgPassInfo => RtInterfaceArgPassInfo(this)
        ReadWriteInfo => RtInterfaceReadWriteInfo(this)
    }
    
    class Object extends RtTypeInfo {
        Class => this.m.CreateClassWrapper(this)
        ArgPassInfo => RtObjectArgPassInfo(this)
    }
    
    class Struct extends RtTypeInfo {
        Class => _rt_CreateStructWrapper(this)
        Size => this.Class.Prototype.Size
        ReadWriteInfo => ReadWriteInfo.FromClass(this.Class)
    }
    
    class Enum extends RtTypeInfo {
        Class => _rt_CreateEnumWrapper(this)
        ArgPassInfo => RtEnumArgPassInfo(this)
    }
    
    class Delegate extends RtTypeInfo {
        ArgPassInfo => RtDelegateArgPassInfo(this)
    }
    
    ArgPassInfo => false
    ReadWriteInfo => false
    
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
            typeinfo := this.m.GetTypeByToken(t, this.typeArgs)
            return true
        }
        return next_outer
    }
}

class RtDecodedType {
    FundamentalType => this
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
    ArgPassInfo => ArgPassInfo('Unsupported', false, false)
    ToString() => String(this.inner) "*"
}

class RtRefType extends RtTypeMod {
    ; TODO: check in/out-ness instead of IsSet
    __new(inner) {
        super.__new(inner)
        if inner.ArgPassInfo {
            this.ArgPassInfo := ArgPassInfo(
                inner.ArgPassInfo.NativeType '*',
                refType_ScriptToNative(&v) => isSet(v) ? &v : &v := 0,
                false
            )
        }
        else {
            if !(inner is RtTypeInfo.Struct)
                MsgBox 'DEBUG: RtRefType being constructed for type "' String(inner) '", which has no ArgPassInfo'
            ; TODO: perform type checking in ScriptToNative
            this.ArgPassInfo := FFITypes.IntPtr.ArgPassInfo
        }
    }
    ScriptToNative => (&v) => isSet(v) ? &v : &v := 0
    NativeType => this.inner.NativeType '*'
    ToString() => String(this.inner) "&"
}

class RtArrayType extends RtTypeMod {
    ArgPassInfo => ArgPassInfo.Unsupported
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
    static primitives := _rt_GetElementTypeMap()
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
            return m.GetTypeByToken(CorSigUncompressToken(&p))
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
