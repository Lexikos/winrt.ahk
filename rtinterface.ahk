
#include ffi.ahk

class RtTypeInfo {
    /**
     * @param {RtMetaDataModule} mdm 
     * @param {mdToken} token 
     * @param {Array} typeArgs Optional array of generic type parameters.
     */
    __new(mdm, token, typeArgs:=false) {
        this.m := mdm
        this.t := token
        this.typeArgs := typeArgs
        
        ; Determine the base type and corresponding RtTypeInfo subclass.
        tdp := mdm.GetTypeDefProps(token)
        this.IsSealed := tdp.flags & 0x100 ; tdSealed (not composable; can't be subclassed)
        switch {
            case tdp.flags & 0x20:
                this.base := RtTypeInfo.Interface.Prototype
            case tdp.extends.IsNull():  ; Nil token.
                throw Error(Format('Type "{}" has no base type or interface flag (flags = 0x{:x})', this.Name, tdp.flags))
            default:
                basetype := this.m.GetTypeByToken(tdp.extends)
                if basetype is RtTypeInfo
                    this.base := basetype.base
                else if basetype.hasProp('TypeClass')
                    this.base := basetype.TypeClass.Prototype
                ;else: just leave RtTypeInfo as base.
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
        ReadWriteInfo => RtInterfaceReadWriteInfo(this)
        GetGuidFromMetadata() {
            for ii in this.m.EnumInterfaceImpls(this.t) {
                if this.m.GetCustomAttributeByName(ii, 'Windows.Foundation.Metadata.DefaultAttribute') {
                    it := this.m.GetInterfaceImplProps(ii).iface
                    return this.m.GetTypeByToken(it, this.typeArgs).GUID
                }
            }
            throw Error("Default interface not found for runtime class.",, this.Name)
        }
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
    
    class Attribute extends RtTypeInfo {
        ; Just for identification. Attributes are only used in metadata.
    }
    
    ArgPassInfo => false
    ReadWriteInfo => false
    static Prototype.IsSealed := false
    
    Name => this.ToString()
    
    ToString() {
        tdp := this.m.GetTypeDefProps(t := this.t), name := tdp.name
        while (tdp.flags & 7) >= 2 { ; tdVisibilityMask = 7, visibility is tdNestedXxx - used in Win32metadata, not WinRT
            tdEncl := this.m.GetNestedClassProps(t)
            tdp := this.m.GetTypeDefProps(tdEncl)
            name := tdp.name '/' name
            t := tdEncl
        }
        if this.typeArgs {
            for t in this.typeArgs
                name .= (A_Index=1 ? '<' : ',') . String(t)
            name .= '>'
        }
        return name
    }

    GUID => super.GUID := this.GetGuidFromMetadata()
    
    GetGuidFromMetadata() => this.typeArgs
        ? _rt_GetParameterizedIID(this.m.GetTypeDefProps(this.t).name, this.typeArgs)
        : this.m.GetGuidPtr(this.t)
    
    ; Whether this class type supports direct activation (IActivationFactory).
    HasIActivationFactory => this.m.ActivatableAttr != -1 ? this.m.EnumCustomAttributes(this.t, this.m.ActivatableAttr)() : false
    ; Enumerate factory interfaces of this class type.
    Factories() => _rt_EnumAttrWithTypeArg(this.m, this.t, this.m.FactoryAttr)
    ; Enumerate composition factory interfaces of this class type.
    Composers() => _rt_EnumAttrWithTypeArg(this.m, this.t, this.m.ComposableAttr)
    ; Enumerate static member interfaces of this class type.
    Statics() => _rt_EnumAttrWithTypeArg(this.m, this.t, this.m.StaticAttr)
    
    ; Enumerate fields of this struct/enum type.
    Fields() {
        getinfo(&f) {
            f := this.m.GetFieldProps(f)
            f.type := rtSignatureDecoder(this.m, f.sig, this.typeArgs).Decode()
            if f.flags & 0x8000 ; fdHasDefault
                f.value := mdGetFieldConstant(this.m, f.t)
        }
        ; EnumFields
        return mdEnumerator_f(getinfo, 20, this.m, "uint", mdTokenVerifyType(this.t, 0x02))
    }
    
    ; Enumerate methods of this interface/class type.
    Methods(name?) {
        next := this.m.EnumMethods(this.t)
        return (&v) => next(&v) && (v := this.m.GetMethodProps(v))
    }
    
    ; Decode a method signature and return [return type, parameter types*].
    MethodArgTypes(sig) => rtSignatureDecoder(this.m, sig, this.typeArgs).Decode()
    
    Implements() {
        next := this.m.EnumInterfaceImpls(this.t)
        return (&typeinfo, &ii:=unset) {
            if !next(&ii)
                return false
            ip := this.m.GetInterfaceImplProps(ii)
            typeinfo := this.m.GetTypeByToken(ip.iface, this.typeArgs)
            return true
        }
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
    ArgPassInfo => ArgPassInfo.Unsupported
    ToString() => String(this.inner) "*"
}

class RefObjPtrAdapter {
    __new(stn, nts, r) {
        this.r := r
        this.stn := stn
        this.nts := nts
    }
    ptr {
        get {
            if !IsSetRef(this.r)
                return 0
            v := this.stn ? (this.stn)(%this.r%) : %this.r%
            ; v is stored in this.v to keep it alive until after ComCall's caller releases the parameters (including 'this').
            return v is Integer ? v : (this.v := v).Ptr
        }
        set => %this.r% := (this.nts)(value)
    }
}

RefArgStruct(nt) {
    ; The value actually passed to DllCall is always a pointer, regardless of nt.
    static baseClass
    if !IsSet(baseClass) {
        baseClass := Class('RefArgStruct')
        baseClass.Prototype.DefineProp('ptr', {type: 'uptr'})
    }
    c := Class('RefArgStruct(' (nt is Class ? nt.Prototype.__Class : nt) ')', baseClass)
    c.Prototype
        .DefineProp('__value', {
            set: RefArgStruct_value_in(this, value?) {
                if IsSet(value) {
                    if value is nt
                        this.ptr := ObjGetDataPtr(value)
                    else {
                        this.s := nt()
                        this.r := value
                        if IsSet(v := %value%?)
                            %this.s% := v
                        this.ptr := ObjGetDataPtr(this.s)
                    }
                }
            }
        })
        .DefineProp('__delete', {
            call: RefArgStruct_value_out(this) {
                if r := (this.r ?? false)
                    %r% := %this.s%
            }
        })
    return c
}

class RtRefType extends RtTypeMod {
    ; TODO: check in/out-ness instead of IsSet
    __new(inner) {
        super.__new(inner)
        if (inner.typeArgs ?? 0) && inner.typeArgs[1] is RtTypeArg {
            this.ArgPassInfo := ArgPassInfo.Unsupported
            return ; Incomplete generic type (not usable at runtime)
        }
        if api := inner.ArgPassInfo {
            numberRef_ScriptToNative(&v) => isSet(v) ? &v : &v := 0
            refPtrType_ScriptToNative(a, v) => v = 0 && v is Integer ? v : a(v)
            canTreatAsPtr(nt) {
                return nt != 'float' && nt != 'double' && (A_PtrSize = 8 || !InStr(nt, '64'))
            }
            if api.NativeToScript && canTreatAsPtr(api.NativeType) {
                this.ArgPassInfo := ArgPassInfo(
                    'Ptr*',
                    refPtrType_ScriptToNative.Bind(ObjBindMethod(RefObjPtrAdapter,, api.ScriptToNative, api.NativeToScript)),
                    false
                )
                return
            }
            else if !(api.ScriptToNative || api.NativeToScript) {
                this.ArgPassInfo := ArgPassInfo(
                    api.NativeType '*',
                    numberRef_ScriptToNative,
                    false
                )
                return
            }
            MsgBox 'DEBUG: RtRefType being constructed for type "' String(inner) '", with unsupported ArgPassInfo properties'
        }
        else if ObjGetDataSize((cls := inner.Class).Prototype) {
            this.Class := RefArgStruct(cls)
            this.ArgPassInfo := false
            return
        }
        else if !(inner is RtTypeInfo.Struct) && inner != RtRootTypes.Guid {
            MsgBox 'DEBUG: RtRefType being constructed for type "' String(inner) '", which has no ArgPassInfo'
        }
        ; TODO: perform type checking in ScriptToNative
        this.ArgPassInfo := FFITypes.IntPtr.ArgPassInfo
    }
    ScriptToNative => (&v) => isSet(v) ? &v : &v := 0
    NativeType => this.inner.NativeType '*'
    ToString() => String(this.inner) "&"
}

class RtArrayType extends RtTypeMod {
    __new(inner, rank := 1, size := [unset], lbound := [unset]) {
        super.__new(inner)
        ; These properties are unlikely to be used for WinRT, but are used for Win32metadata.
        this.rank := rank, this.size := size, this.lbound := lbound
    }
    ArgPassInfo => ArgPassInfo.Unsupported
    ubound[n] => this.size[n] - (this.lbound[n] ?? 0) - 1
    ToString() {
        s := String(this.inner) "["
        Loop this.rank {
            s .= (A_Index > 1 ? "," : "")
                . ((this.lbound[A_Index] ?? 0)
                    ? this.lbound[A_Index] ".." this.ubound[A_Index]
                    : (this.size[A_Index] ?? ""))
        }
        return s .= "]"
    }
}

_rt_EnumAttrWithTypeArg(mdi, tk, attrCtor) {
    if attrCtor = -1 ; Caller found no reference to the attribute in mdi.
        return (&v) => 0
    attrToType(&v) {
        v := WinRT.GetType(getArg1String(mdi.GetCustomAttributeProps(v).data.ptr))
    }
    getArg1String(pdata) {
        return StrGet(pdata + 3, NumGet(pdata + 2, "uchar"), "utf-8")
    }
    ; EnumCustomAttributes := 53
    return mdEnumerator_f(attrToType, 53, mdi, "uint", mdTokenVerify(tk), "uint", mdTokenVerifyType(attrCtor, 0x0a))
}

class rtSignatureDecoder extends mdSignatureDecoder {
    __new(mdm, sig, typeArgs?) {
        this.m := mdm
        super.__new(sig, typeArgs?)
    }
    MakePrimitive(t) => RtRootTypes.%t%
    MakeClass(t) => this.m.GetTypeByToken(t)
    MakePtr(t) => RtPtrType(t)
    MakeRef(t) => RtRefType(t)
    MakeArray(t, rank := 1, size := [unset], lbound := [unset]) =>
        RtArrayType(t, rank, size, lbound)
    MakeTypeArg(index) => RtTypeArg(index)
    MakeGenericInst(baseType, types) {
        t := {
            typeArgs: types,
            m: baseType.m, t: baseType.t,
            base: baseType.base
            ; base: baseType -- not doing this because most of the cached properties
            ; need to be recalculated for the generic instance, GUID in particular.
        }
        ; Check/update cache to ensure there's only one typeinfo for this combination of
        ; types (to reduce memory usage and permit other optimizations).  This could be
        ; optimized by decoding sig to names only, rather than resolving to the array
        ; of types (above).
        if cached := WinRT.TypeCache.Get(tname := t.Name, false)
            return cached
        return WinRT.TypeCache[tname] := t
    }
}

