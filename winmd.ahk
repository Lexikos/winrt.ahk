#Requires AutoHotkey v2.1-alpha.19

#include guid.ahk
#include CorSig.ahk

class mdModule {
    
    ; Open a .winmd file.
    ; Returns an instance of the class on which it was called.
    static Open(path) {
        static CLSID_CorMetaDataDispenser := GUID("{E5CB7A31-7512-11d2-89CE-0080C792E5D8}")
        static IID_IMetaDataDispenser := GUID("{809C652E-7396-11D2-9771-00A0C9B4D50C}")
        static IID_IMetaDataImport := GUID("{7DAC8207-D3AE-4C75-9B67-92801A497D44}")
        #DllLoad rometadata.dll
        DllCall("rometadata.dll\MetaDataGetDispenser"
            , "ptr", CLSID_CorMetaDataDispenser, "ptr", IID_IMetaDataDispenser
            , "ptr*", mdd := ComValue(13, 0), "hresult")
        ; IMetaDataDispenser::OpenScope
        ComCall(4, mdd, "wstr", path, "uint", 0
            , "ptr", IID_IMetaDataImport
            , "ptr*", mdm := this())
        return mdm
    }
    
    ptr := 0 ; IMetaDataImport*
    __delete() {
        (p := this.ptr) && ObjRelease(p)
    }
    
    ;#region IMetaDataImport methods
    
    EnumTypeDefs()                  => mdEnumerator(6, this)
    EnumInterfaceImpls(td)          => mdEnumerator(7, this, "uint", mdTokenVerifyType(td, 0x02))
    EnumMethods(td)                 => mdEnumerator(18, this, "uint", mdTokenVerifyType(td, 0x02))
    EnumMethodsWithName(td, name)   => mdEnumerator(19, this, "uint", mdTokenVerifyType(td, 0x02), "wstr", name)
    EnumFields(td)                  => mdEnumerator(20, this, "uint", mdTokenVerifyType(td, 0x02))
    EnumFieldsWithName(td, name)    => mdEnumerator(21, this, "uint", mdTokenVerifyType(td, 0x02), "wstr", name)
    EnumParams(md)                  => mdEnumerator(22, this, "uint", mdTokenVerifyType(md, 0x06))
    /**
     * @param {mdToken|Integer} tk Token of the object whose attributes are to be enumerated, or 0 for all.
     * @param {mdToken|Integer} tCtor If td is 0 or tCtor is 0, attributes are not filtered by type; otherwise,
     *  only attributes which reference this constructor (MemberRef or MethodDef token) are enumerated.
     */
    EnumCustomAttributes(tk, tCtor:=0) => mdEnumerator(53, this, "uint", mdTokenVerify(tk), "uint", mdTokenVerifyType(tCtor, 0x0a, 0x06, -1))
    
    FindTypeDefByName(szTypeDef, tkEnclosingClass:=0) {
        ComCall(9, this, "wstr", szTypeDef, "uint", mdTokenVerifyType(tkEnclosingClass, 0x02, 0x01, -1), "uint*", &td:=0)
        return mdToken(td)
    }
    
    FindTypeRef(tkScope, name) {
        ComCall(55, this, "uint", mdTokenVerifyType(tkScope, 0x23, 0x01, 0x1a), "wstr", name, "uint*", &tr:=0, "int")
        return mdToken(tr)
    }
    
    GetTypeDefProps(td) {
        namebuf := mdNameBuffer()
        ComCall(12, this, "uint", mdTokenVerifyType(td, 0x02)
            , "ptr", namebuf, "uint", namebuf.Size//2, "uint*", &namelen:=0
            , "uint*", &flags:=0, "uint*", &tkExtends:=0)
        ; Testing shows namelen includes a null terminator, but the docs aren't
        ; clear, so rely on StrGet's positive-length behaviour to truncate.
        return {
            flags: flags,
            extends: mdToken(tkExtends),
            name: namebuf.ToString(namelen),
            t: td
        }
    }
    
    GetInterfaceImplProps(ii) {
        ComCall(13, this, "uint", mdTokenVerifyType(ii, 0x09), "uint*", &tkClass:=0, "uint*", &tkIface:=0)
        return {
            class: mdToken(tkClass),
            iface: mdToken(tkIface),
            t: ii
        }
    }
    
    GetTypeRefProps(tr) {
        namebuf := mdNameBuffer()
        ComCall(14, this, "uint", mdTokenVerifyType(tr, 0x01), "uint*", &tkResolutionScope:=0
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0)
        return {
            name: namebuf.ToString(namelen),
            scope: mdToken(tkResolutionScope),
            t: tr
        }
    }
    
    GetMethodProps(md) {
        namebuf := mdNameBuffer(), sig := mdSignature()
        ComCall(30, this, "uint", mdTokenVerifyType(md, 0x06), "ptr", 0
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
            , "uint*", &flags:=0
            , "ptr", ObjGetDataPtr(sig), "ptr", ObjGetDataPtr(sig) + A_PtrSize
            , "ptr", 0, "ptr", 0)
        return {
            flags: flags, ; CorMethodAttr
            name: namebuf.ToString(namelen),
            sig: sig,
            t: md
        }
    }
    
    GetMemberRefProps(mr) {
        namebuf := mdNameBuffer(), sig := mdSignature()
        ComCall(31, this, "uint", mdTokenVerifyType(mr, 0x0a), "uint*", &tkParent:=0
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
            , "ptr", ObjGetDataPtr(sig), "ptr", ObjGetDataPtr(sig) + A_PtrSize)
        return {
            name: namebuf.ToString(namelen),
            parent: mdToken(tkParent),
            sig: sig,
            t: mr
        }
    }
    
    GetCustomAttributeProps(tkAt) {
        data := mdBufferlike()
        ComCall(54, this, "uint", mdTokenVerify(tkAt), "uint*", &tkParent:=0, "uint*", &tkCtor:=0
            , "ptr", ObjGetDataPtr(data), "ptr", ObjGetDataPtr(data) + A_PtrSize)
        return {
            data: data,
            ctor: tkCtor,
            parent: tkParent,
            t: tkAt
        }
    }
    
    GetFieldProps(fd) {
        namebuf := mdNameBuffer(), sig := mdSignature()
        ComCall(57, this, "uint", mdTokenVerifyType(fd, 0x04), "ptr", 0
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
            , "ptr*", &flags:=0
            , "ptr", ObjGetDataPtr(sig), "ptr", ObjGetDataPtr(sig) + A_PtrSize
            , "ptr", 0, "ptr", 0, "ptr", 0)
        return {
            flags: flags, ; CorFieldAttr
            name: namebuf.ToString(namelen),
            sig: sig,
            t: fd
        }
    }
    
    GetParamProps(pd) {
        namebuf := mdNameBuffer()
        ComCall(59, this, "uint", mdTokenVerifyType(pd, 0x08), "ptr", 0, "uint*", &index:=0
            , "ptr", namebuf, "uint", namebuf.size//2, "uint*", &namelen:=0
            , "uint*", &flags:=0 , "ptr", 0, "ptr", 0, "ptr", 0)
        return {
            index: index,
            flags: flags, ; CorParamAttr
            name: namebuf.ToString(namelen),
            t: pd
        }
    }
    
    GetNestedClassProps(td) {
        ComCall(62, this, "uint", mdTokenVerifyType(td, 0x02), "uint*", &tdEncl:=0)
        return mdToken(tdEncl)
    }
    
    GetTypeSpecFromToken(ts) {
        sig := mdSignature()
        ComCall(44, this, "uint", mdTokenVerifyType(ts, 0x1b)
            , "ptr", ObjGetDataPtr(sig), "ptr", ObjGetDataPtr(sig) + A_PtrSize)
        return sig
    }
    
    /**
     * Gets the first custom attribute with the given name which is applied to the given token.
     * @param {mdToken | Integer} tk 
     * @param {String} name 
     * @returns {mdBufferlike | Boolean}
     *  Returns {ptr,size} of the attribute data, or false if no attribute was found.
     */
    GetCustomAttributeByName(tk, name) {
        data := mdBufferlike()
        ; The Rometadataapi.h docs say it returns S_OK or a HRESULT *ERROR CODE*,
        ; but in reality it returns S_FALSE (S = success) if there's no attribute.
        if ComCall(60, this, "uint", mdTokenVerify(tk), "wstr", name
            , "ptr", ObjGetDataPtr(data), "ptr", ObjGetDataPtr(data) + A_PtrSize) = 0
            return data
        return false
    }
    
    ;#endregion

    Name {
        get {
            namebuf := mdNameBuffer()
            ; GetScopeProps
            ComCall(10, this, "ptr", namebuf, "uint", namebuf.Size//2, "uint*", &namelen:=0, "ptr", 0)
            return namebuf.ToString(namelen)
        }
    }
}

class mdToken {
    t : u32
    __new(value := 0) {
        this.t := value
    }
    __value {
        set {
            this.t := value is mdToken ? value.t : value
        }
    }
    Type => mdToken.TypeNameMap[this.t >> 24] ?? Format("0x{:02x}", this.t >> 24)
    Row => this.t & 0xFFFFFF
    IsNull() => !(this.t & 0xFFFFFF)
    ToString() => this.Type '<' this.Row '>'
    ; Use ptr only for passing to output parameters (ComCall parameter type "ptr").
    Ptr => ObjGetDataPtr(this)
    ; Map of token types to names. Only includes token types listed in enum CorTokenType.
    ; Other tables are likely never referenced by token.  Types marked with ";N" haven't
    ; been observed in WinRT/Win32metadata, but can likely be found in CLR assemblies.
    ; Whether they are returned/accepted by any of the APIs we use is a separate matter.
    static TypeNameMap := Map(
        0x00, "Module",
        0x01, "TypeRef",
        0x02, "TypeDef",
        0x04, "FieldDef",
        0x06, "MethodDef",
        0x08, "ParamDef",
        0x09, "InterfaceImpl",
        0x0a, "MemberRef",
        0x0c, "CustomAttribute",
        0x0e, "Permission", ;N
        0x11, "Signature", ;N
        0x14, "Event",
        0x17, "Property",
        0x1a, "ModuleRef",
        0x1b, "TypeSpec",
        0x20, "Assembly",
        0x23, "AssemblyRef",
        0x26, "File", ;N
        0x27, "ExportedType", ;N
        0x28, "ManifestResource", ;N
        0x2a, "GenericParam",
        0x2b, "MethodSpec", ;N
    )
    static null := mdToken(0)
}

mdTokenVerify(tk) {
    t := tk is mdToken ? tk.t : tk
    if !(t is Integer)
        throw TypeError("Expected mdToken or Integer, but got " type(t),, t)
    if (t & ~0xFFFFFFFF)
        throw ValueError("Invalid token value",, t)
    return t
}

mdTokenVerifyType(tk, types*) {
    t := mdTokenVerify(tk)
    ; Null tokens not permitted by default.
    ; API says to use "NULL" or "zero", so null tokens with non-zero token type are not permitted.
    if !(t & 0xFFFFFF)
        return (t = 0 && types[-1] = -1) ? t : throw(ValueError("Unexpected null token",, tk))
    for tt in types
        if ((t >> 24) = tt)
            return t
    throw ValueError("Invalid token type",, Format("0x{:08x}", t))
}

mdTokenVerifyNonzero(tk) {
    t := mdTokenVerify(tk)
    return (t & 0xFFFFFF) || throw(ValueError("Unexpected null token",, tk))
}

class mdNameBuffer extends Buffer {
    ; Sources indicate a limit of MAX_CLASS_NAME (1024) applies to a type's full name in current
    ; versions of Microsoft's CLR implementation; it's certainly enough for all Win32metadata and
    ; official WinRT types. This simplifies various functions, which don't have a documented way
    ; to get the required buffer size, and would typically return much shorter strings.
    __new() => (super.__new(1024 * 2), StrPut("", this, "UTF-16"))
    static __new() {
        this.Prototype.DefineProp 'ToString', {call: f := StrGet.Bind(,, "UTF-16")}
    }
}

class mdBufferlike {
    ptr : uptr
    size : u32
}

class mdSignature extends mdBufferlike {
}

class mdSignatureDecoder {
    pos := 0
    ptr => this.sig.ptr + this.pos
    size => this.sig.size - this.pos
    __new(sig, typeArgs:=false) {
        this.sig := sig
        this.typeArgs := typeArgs
    }
    
    ReadUInt8() => NumGet(this.sig, this.pos++, "uchar")
    
    Decode() {
        p := 0
        cconv := this.ReadUInt8()
        if cconv = 6 ; Field
            return this.DecodeType()
        argc := this.ReadUInt8() + 1 ; +1 for return type
        return this.DecodeTypes(argc)
    }
    
    DecodeTypes(count) {
        types := []
        loop count
            types.Push(this.DecodeType())
        return types
    }
    
    DecodeGenericInst() {
        baseType := this.DecodeType()
        types := []
        types.Capacity := count := this.ReadUInt8()
        loop count
            types.Push(this.DecodeType())
        return this.MakeGenericInst(baseType, types)
    }
    
    DecodePackedUInt() {
        if (NumGet(this.sig, this.pos, "uchar") & 0x80) = 0x00
            return NumGet(this.sig, this.pos++, "uchar")
        if (NumGet(this.sig, this.pos, "uchar") & 0xC0) = 0x80
            return (NumGet(this.sig, this.pos++, "uchar") & 0x3f) << 8
                |   NumGet(this.sig, this.pos++, "uchar")
        else
            return (NumGet(this.sig, this.pos++, "uchar") & 0x1f) << 24
                |   NumGet(this.sig, this.pos++, "uchar") << 16
                |   NumGet(this.sig, this.pos++, "uchar") << 8
                |   NumGet(this.sig, this.pos++, "uchar")
    }
    
    DecodePackedInt() {
        if (NumGet(this.sig, this.pos, "uchar") & 0x80) = 0x00 {
            i := NumGet(this.sig, this.pos++, "uchar")
            return (i & 1) * 0xffffffc0 | (i >> 1)
        }
        else if (NumGet(this.sig, this.pos, "uchar") & 0xC0) = 0x80 {
            i := (NumGet(this.sig, this.pos++, "uchar") & 0x3f) << 8
                | NumGet(this.sig, this.pos++, "uchar")
            return (i & 1) * 0xffffe000 | (i >> 1)
        }
        else {
            i := (NumGet(this.sig, this.pos++, "uchar") & 0x1f) << 24
                | NumGet(this.sig, this.pos++, "uchar") << 16
                | NumGet(this.sig, this.pos++, "uchar") << 8
                | NumGet(this.sig, this.pos++, "uchar")
            return (i & 1) * 0xf0000000 | (i >> 1)
        }
    }
    
    DecodeToken(permittedTypes*) {
        t := this.DecodePackedUInt()
        static prefix := [0x02000000, 0x01000000, 0x1b000000]
        t := prefix[(t & 3) + 1] | (t >> 2)
        return mdToken(mdTokenVerifyType(t, permittedTypes*))
    }
    
    DecodeType() {
        static primitives := Map(
            0x1, 'Void',
            0x2, 'Boolean',
            0x3, 'Char16',
            0x4, 'Int8',
            0x5, 'UInt8',
            0x6, 'Int16',
            0x7, 'UInt16',
            0x8, 'Int32',
            0x9, 'UInt32',
            0xa, 'Int64',
            0xb, 'UInt64',
            0xc, 'Single',
            0xd, 'Double',
            0xe, 'String',
            0x18, 'IntPtr',
            0x19, 'UIntPtr', ; Encountered in Win32metadata, but not WinRT.
            0x1c, 'Object',
        )
        static modifiers := Map(
            0x0f, 'Ptr',
            0x10, 'Ref',
            0x1D, 'Array', ; WinRT uses this type of array.
        )
        b := this.ReadUInt8()
        if t := primitives.get(b, 0)
            return this.MakePrimitive(t)
        if modt := modifiers.get(b, 0)
            return this.Make%modt%(this.DecodeType())
        switch b {
            case 0x11, 0x12: ; value type, class type
                t := this.DecodeToken(0x01, 0x02)
                return this.MakeClass(t)
            case 0x13: ; generic type parameter
                t := this.ReadUInt8() + 1
                return this.typeArgs ? this.typeArgs[t] : this.MakeTypeArg(t)
            case 0x15: ; GENERICINST <generic type> <argCnt> <arg1> ... <argn>
                return this.DecodeGenericInst()
            case 0x1F, 0x20: ; CMOD <typeDef/Ref> ...
                modt := this.DecodeToken(0x01, 0x02)
                t    := this.DecodeType()
                return this.MakeModifier(modt, t)
            case 0x14: ; ARRAY Type Rank NumSizes Size* NumLoBounds LoBound*
                ; Fixed-size arrays (as commonly used in Win32metadata.winmd) are encoded
                ; with this element type. Single-dim zero-based arrays of unspecified size
                ; (as used in WinRT parameters) are encoded with 0x1D instead.
                t := this.DecodeType()
                rank := this.DecodePackedUInt()
                size := [], size.Length := rank
                lbound := [], lbound.Length := rank
                Loop this.DecodePackedUInt()
                    size[A_Index] := this.DecodePackedUInt()
                Loop this.DecodePackedUInt()
                    lbound[A_Index] := this.DecodePackedInt()
                return this.MakeArray(t, rank, size, lbound)
        }
        throw Error("type not handled",, Format("{:02x}", b))
    }
    
    MakePrimitive(t) => t
    MakeClass(t) => t
    MakePtr(t) => mdModifier.Ptr(t)
    MakeRef(t) => mdModifier.Ref(t)

    MakeModifier(modt, t) {
        ; @Debug-Breakpoint
        return t
    }
    
    MakeArray(t, rank := 1, size := [unset], lbound := [unset]) {
        ; @Debug-Breakpoint
        throw Error("Not implemented")
    }
    
    MakeGenericInst(baseType, types) {
        ; @Debug-Breakpoint
        throw Error("Not implemented")
    }
    
    MakeTypeArg(index) {
        ; @Debug-Breakpoint
        throw Error("Not implemented")
    }
    
    Make() => throw() ; This is just here to suppress a warning from the IDE about this.Make%...%()
}

class mdModifier {
    __new(t) {
        this.t := t
    }
    ToString() => RegExReplace(Type(this), '.*\.') '<' String(this.t) '>'
    class Ptr extends mdModifier {
        ToString() => String(this.t) '*'
    }
    class Ref extends mdModifier {
        ToString() => String(this.t) '&'
    }
}

mdGetFieldConstant(mdi, field) {
    field := field.t ?? field
    mdt := ComObjQuery(mdi, "{D8F579AB-402D-4B8E-82D9-5D63B1065C68}") ; IMetaDataTables
    
    static tabConstant := 11, GetTableInfo := 9
    ComCall(GetTableInfo, mdt, "uint", tabConstant
        , "ptr", 0, "uint*", &cRows := 0, "ptr", 0, "ptr", 0, "ptr", 0)
    
    static colType := 0, colParent := 1, colValue := 2, GetColumn := 13, GetBlob := 15
    ; Rows look to be ordered by Parent, which could be because they are allocated sequentially
    ; as each field is defined by the compiler, but a simple test compiling C# with mixed fields
    ; and parameter default values showed rows ordered by Parent row ID, not by definition order.
    ; That's perfect for binary search.  Row ID excludes the upper byte, but our metadata only
    ; includes the one type of Parent (FieldDef) anyway.
    left := 1, right := cRows
    ; When we're called for sequential fields, the rows we want are often sequential as well,
    ; so try the next row after the last found row first.  Worst case, it's always wrong and
    ; the binary search has an extra iteration which isn't 50-50 but still helps the search.
    static last_i
    i := (IsSet(last_i) && last_i < cRows) ? last_i + 1 : (left + right) // 2
    while left <= right {
        ComCall(GetColumn, mdt, "uint", tabConstant, "uint", colParent, "uint", i, "uint*", &value:=0)
        if field > value
            left := i + 1
        else if field < value
            right := i - 1
        else
            break
        i := (left + right) // 2
    }
    if left > right {
        ; Rather than falling back to linear search in case the rows weren't ordered as expected,
        ; assume the field parameter was invalid.  If that turns out to not be the case, we want
        ; to know what files need the slower method (or to fix it with another optimization).
        throw ValueError("No constant found for token.", Format("0x{:x}", field))
    }
    last_i := i
    ComCall(GetColumn, mdt, "uint", tabConstant, "uint", colValue, "uint", i, "uint*", &value:=0)
    ComCall(GetBlob, mdt, "uint", value, "uint*", &ndata:=0, "ptr*", &pdata:=0)
    ComCall(GetColumn, mdt, "uint", tabConstant, "uint", colType, "uint", i, "uint*", &value:=0)
    ; Type must be one of the basic element types (2..14) or CLASS (18) with value 0.
    ; WinRT only uses constants for enums, always I4 (8) or U4 (9).
    switch value {
        ; List types used in WinRT first.
        case 8: return NumGet(pdata, "int")
        case 9: return NumGet(pdata, "uint")
        ; Types used in Win32metadata:
        case 5: return NumGet(pdata, "uchar")
        case 6: return NumGet(pdata, "short")
        case 14: return StrGet(pdata, ndata//2, "UTF-16")
    }
    throw Error("Constant type not handled",, value)
}

mdEnumerator(args*) => mdEnumerator_f((&v) => (v := mdToken(v), true), args*)

mdEnumerator_f(f, methodidx, this, args*) {
    henum := index := count := 0
    ; Getting the items in batches improves performance, with diminishing returns.
    buf := Buffer(4 * batch_size:=32)
    ; Prepare the args for ComCall, with the caller's extra args in the middle.
    args.InsertAt(1, methodidx, this, "ptr*", &henum)
    args.Push("ptr", buf, "uint", batch_size, "uint*", &count)
    ; Call CloseEnum when finished enumerating.
    args.__delete := args => ComCall(3, this, "uint", henum, "int")
    next(&item?) {
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

mdDecodeAttribData(data, sig) {
    static readers := Map(
        2,  (&p, *) =>  NumGet(p++, "char") != 0, ; BOOLEAN
        3,  (&p, *) => Chr(NumGet(p++, "ushort")), ; CHAR
        4,  (&p, *) =>  NumGet(p++, "char"),
        5,  (&p, *) =>  NumGet(p++, "uchar"),
        6,  (&p, *) => (NumGet((p += 2) - 2, "short")),
        7,  (&p, *) => (NumGet((p += 2) - 2, "ushort")),
        8,  (&p, *) => (NumGet((p += 4) - 4, "int")),
        9,  (&p, *) => (NumGet((p += 4) - 4, "uint")),
        10, (&p, *) => (NumGet((p += 8) - 8, "int64")),
        11, (&p, *) => (NumGet((p += 8) - 8, "uint64")),
        12, (&p, *) => (NumGet((p += 4) - 4, "float")),
        13, (&p, *) => (NumGet((p += 8) - 8, "double")),
        14, readString,
        17, readValueType,
        18, readClassType,
    )
    readString(&p, *) {  ; String
        if NumGet(p, "uchar") = 0xFF ; Reserved to mean null
            return (++p, unset)
        len := CorSigUncompressData(&p)
        s := StrGet(p, len, "UTF-8")
        p += len
        return s
    }
    readValueType(&p, &psig) {
        tt := CorSigUncompressToken(&psig)
        ; Currently not using tt (likely a TypeRef) because it's often a reference to
        ; a netstandard type, and we have no good way to locate appropriate metadata.
        ; Probably not safe to assume all enums are 32-bit, but other checks should
        ; detect a decoding error if this assumption is wrong.
        return NumGet((p += 4) - 4, "int")
    }
    readClassType(&p, &psig) {
        tt := CorSigUncompressToken(&psig)
        ; Currently assuming tt is a TypeRef to System.Type, since I think that's the
        ; only valid way that a class type can appear in an attribute constructor,
        ; and it lets us avoid a dependency on mdModule.
        return readString(&p, &psig)
    }
    v := []
    if NumGet(data, 0, "short") != 1 ; Prolog is always 0x0001
        throw ValueError("Invalid attribute data")
    p := data.ptr + 2
    if (flags := NumGet(sig, "uchar")) != 0x20 ; HASTHIS
        throw ValueError("Unexpected flags for attribute constructor",, flags)
    paramCount := CorSigUncompressData(&psig := sig.ptr + 1)
    elType := NumGet(psig++, "uchar")
    if elType != 1 ; VOID
        throw ValueError("Unexpected return type for attribute constructor",, elType)
    Loop paramCount {
        elType := NumGet(psig++, "uchar")
        try
            v.Push(readers[elType](&p, &psig))
        catch UnsetItemError
            throw Error("Element type not handled",, elType)
    }
    namedCount := NumGet(p, "ushort"), p += 2
    Loop namedCount {
        nkind := NumGet(p++, "uchar")
        if nkind != 0x53 && nkind != 0x54 ; FIELD or PROPERTY (we don't care which)
            throw ValueError("Invalid attribute data",, nkind)
        elType := NumGet(p++, "uchar")
        name := readString(&p)
        try
            v.%name% := readers[elType](&p, unset)
        catch UnsetItemError
            throw Error("Element type not handled",, elType)
    }
    if p != data.ptr + data.size
        throw Error("Error decoding attribute data",, p - (data.ptr + data.size))
    return v
}