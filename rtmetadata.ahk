#include winmd.ahk
#include util.ahk

class MetaDataModule extends mdModule {
    StaticAttr => _rt_CacheAttributeCtors(this, this, 'StaticAttr')
    FactoryAttr => _rt_CacheAttributeCtors(this, this, 'FactoryAttr')
    ActivatableAttr => _rt_CacheAttributeCtors(this, this, 'ActivatableAttr')
    ComposableAttr => _rt_CacheAttributeCtors(this, this, 'ComposableAttr')
    
    AddFactoriesToWrapper(w, t) {
        if t.HasIActivationFactory {
            this.AddIActivationFactoryToWrapper(w)
        }
        for f in t.Factories() {
            this.AddInterfaceToWrapper(w, f, false, "Call")
        }
        for f in t.Composers() {
            this.AddInterfaceToWrapper(w, f, false, "Call")
            ; Base classes are required to be [Composable], but the corresponding interface
            ; can be entirely empty if consumers of the API aren't supposed to subclass it.
            if w.HasOwnProp("Call")
                AddMethodOverloadTo(w, "Call", w => w(0, 0), w.prototype.__class ".")
        }
    }
    
    AddIActivationFactoryToWrapper(w) {
        ActivateInstance(cls) {
            ; cls.ptr is IActivationFactory*; this calls ActivateInstance.
            static new := Object.Call
            ComCall(6, cls, "ptr*", inst := new(cls))
            return inst
        }
        AddMethodOverloadTo(w, "Call", ActivateInstance, w.prototype.__class ".")
    }
    
    CreateInterfaceWrapper(t) {
        w := _rt_CreateClass(t_name := t.Name, RtObject)
        t.DefineProp 'Class', {value: w}
        this.AddInterfaceToWrapper(w.prototype, t, true)
        this.AddInterfaceCoercion(w.prototype, t)
        wrapped := Map()
        addreq(w.prototype, t)
        addreq(w, t) {
            for ti in t.Implements() {
                if wrapped.Has(ti_name := ti.Name)
                    continue
                wrapped[ti_name] := true
                ti.m.AddInterfaceToWrapper(w, ti, false)
                addreq(w, ti)
            }
        }
        return w
    }
    
    CreateClassWrapper(t) {
        w := _rt_CreateClass(classname := t.Name, t.SuperType.Class)
        t.DefineProp 'Class', {value: w}
        internalPropCount := ObjOwnPropCount(w)
        ; Add any constructors:
        this.AddFactoriesToWrapper(w, t)
        ; Add static interfaces to the class:
        for ti in t.Statics() {
            this.AddInterfaceToWrapper(w, ti)
        }
        ; Need a factory?
        if ObjOwnPropCount(w) > internalPropCount {
            ; "Activation Factories must implement the IActivationFactory interface."
            ; Using IActivationFactory here avoids the need to ComObjQuery for it later
            ; (and works even if the class does not support direct activation).
            ; Using any other IID likely causes an internal QueryInterface,
            ; since DllGetActivationFactory can only return IActivationFactory*.
            static oiid := GUID("{00000035-0000-0000-C000-000000000046}")
            hr := DllCall("combase.dll\RoGetActivationFactory"
                , 'ptr', hclassname := HStringFromString(classname)
                , 'ptr', oiid
                , 'ptr*', w, 'int')
            if hr < 0 {
                ; C++/WinRT falls back to locating the DLL by relying on a naming convention.
                ; Some runtime classes in the Windows App SDK don't follow this convention,
                ; but this does work for Microsoft.UI.Xaml.TriggerBase, which fails above.
                ; https://learn.microsoft.com/windows/uwp/winrt-components/create-a-windows-runtime-component-in-cppwinrt
                dllname := classname
                while i := InStr(dllname, '.', true, -2) {
                    dllname := SubStr(dllname, 1, i)
                    ; Explicitly call LoadLibrary to avoid Error() overhead on failure and ensure
                    ; the DLL is unloaded only if DllGetActivationFactory fails.  The proc address
                    ; could be cached, but there might not be a 1:1 relation between WINMD and DLL,
                    ; and this executes only once per unique runtime class anyway.
                    if hmod := DllCall("LoadLibrary", 'str', dllname "dll", 'ptr') {
                        try
                            if gaf := DllCall("GetProcAddress", 'ptr', hmod, 'astr', "DllGetActivationFactory", 'ptr') {
                                hr := DllCall(gaf, 'ptr', hclassname, 'ptr*', w, 'int')
                                if hr >= 0
                                    break
                            }
                        if hr < 0
                            DllCall("FreeLibrary", 'ptr', hmod)
                    }
                }
            }
            if hr < 0
                throw OSError(hr)
        }
        wrapped := Map()
        addRequiredInterfaces(wp, t, isclass) {
            for ti, impl in t.Implements() {
                isdefault := isclass && this.GetCustomAttributeByName(impl
                    , 'Windows.Foundation.Metadata.DefaultAttribute')
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
        if wrapped.Count
            this.AddInterfaceCoercion(w.prototype, t)
        return w
    }
    
    AddInterfaceToWrapper(w, t, isdefault:=false, nameoverride:=false) {
        if isdefault
            iid := "" ; Skip QueryInterface calls for the default interface.
        else if pguid := t.GUID
            iid := GuidToString(pguid)
        else
            ; @Debug-Output => Interface {t.Name} can't be added because it has no GUID
            return
        name_prefix := w.HasOwnProp('prototype') ? w.prototype.__class "." : w.__class ".Prototype."
        for method in t.Methods() {
            name := nameoverride ? nameoverride : method.name
            types := t.MethodArgTypes(method.sig)
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
    
    AddInterfaceCoercion(w, t) {
        w.DefineProp('__value', {
            ; Coerce assigned object/interface pointer to the right interface.
            set: _rt_ObjectSetValue.Bind(t.GUID),
            ; Wrap according to runtime class, if it can vary from t.Class.
            get: _rt_ObjectGetValue.Bind(Object.Call.Bind({Prototype: w}))
        })
    }
    
    GetGuidPtr(td) {
        guidattr := this.GetCustomAttributeByName(td, 'Windows.Foundation.Metadata.GuidAttribute')
        if !guidattr
            throw Error("TypeDef has no GuidAttribute",, this.GetTypeDefProps(td).name)
        ; Attribute is serialized with leading 16-bit version (1) and trailing 16-bit number of named args (0).
        if guidattr.size != 20
            throw Error("Unexpected GuidAttribute data length: " guidattr.size)
        return guidattr.ptr + 2
    }
}

_rt_FindAssemblyRef(mdai, target_name) {
    namebuf := mdNameBuffer()
    ; EnumAssemblyRefs
    for asm in mdEnumerator_f(false, 8, mdai) {
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
    ; Within a SINGLE version of WindowsAppRuntime, a module's reference
    ; to ActivatableAttribute may be scoped to any of these three...
    asm := _rt_FindAssemblyRef(mdai, "Windows.Foundation")
        || _rt_FindAssemblyRef(mdai, "Windows.Foundation.FoundationContract")
        || _rt_FindAssemblyRef(mdai, "Windows")
        || 1 ; Allow for when mdi is Windows.Foundation itself (FindTypeRef will fail for any others).
    
    searchFor(attrType, names, indexForSig := psig => 1) {
        mrs := [], mrs.Length := names.Length
        ; FindTypeRef
        if ComCall(55, mdi, "uint", asm, "wstr", attrType, "uint*", &tr:=0, "int") = 0 {
            ; EnumMemberRefs
            for mr in mdEnumerator_f(false, 23, mdi, "uint", tr) {
                ; GetMemberRefProps
                ComCall(31, mdi, "uint", mr, "uint*", &ttype:=0
                    , "ptr", 0, "uint", 0, "ptr", 0
                    , "ptr*", &psig:=0, "uint*", &nsig:=0)
                i := indexForSig(psig)
                if mrs.Has(i) {
                    ; FIXME: handle all attribute constructor overloads
                    ; This ignores some applied to XamlControlsXamlMetaDataProvider
                    ; (and maybe others in modules other than Microsoft.UI.Xaml).
                    continue
                    ; throw Error("Conflicting constructor found for " names[i], -1)
                }
                mrs[i] := mr
            }
        }
        ; If there are no references to an attribute constructor in the module,
        ; that attribute isn't used, so set -1 (invalid) to avoid reentry.
        loop mrs.Length
            o.DefineProp names[A_Index], {value: mrs[A_Index] ?? -1}
    }
    
    searchFor("Windows.Foundation.Metadata.StaticAttribute"
        , ['StaticAttr'])
    
    searchFor("Windows.Foundation.Metadata.ActivatableAttribute"
        , ['ActivatableAttr', 'FactoryAttr']
        , psig => NumGet(psig, 3, "uchar") = 9 ? 1 : 2) ; 9 = uint (first arg is uint, not interface name)
    
    searchFor("Windows.Foundation.Metadata.ComposableAttribute"
        , ['ComposableAttr'])
    
    return o.%retprop%
}

MethodWrapper(idx, iid, types, name:=unset) {
    rettype := types.RemoveAt(1)
    cca := [] ;, cca.Length := 1 + 2*types.Length, ccac := 0
    stn := Map()
    if iid
        stn[1] := ComObjQuery.Bind( , iid)
    args_to_expand := Map()
    for t in types {
        if pass := t.ArgPassInfo {
            if pass.ScriptToNative
                stn[1 + A_Index] := pass.ScriptToNative
            cca.Push( , pass.NativeType)
        }
        else if ObjGetDataSize((tcls := t.Class).Prototype) {
            cca.Push( , tcls)
        }
        else {
            ; @Debug-Breakpoint => Unhandled arg type {t.name} for {name}
            return (*) => throw(Error("Unhandled arg type " String(t)))
        }
    }
    ; rettype from metadata translates to a ref out parameter at the end.
    if rettype != FFITypes.Void {
        if pass := rettype.ArgPassInfo {
            fri := () => &newvarref := 0 ; Construct a VarRef for ComCall to write into.
            cca.Push( , pass.NativeType '*') ; Instruct ComCall to pass the value by address.
            frr := ((nts, &ref) => nts(ref)).Bind(pass.NativeToScript || Number) ; &ref parameter derefs the VarRef.
        }
        else {
            fri := rettype.Class, proto := fri.Prototype
            fri := Object.Call.Bind(fri)
            if !ObjGetDataSize(proto)
                ; @Debug-Breakpoint => Unhandled return type {rettype.name} for {name}
                return (*) => throw(Error("Unhandled return type " String(t)))
            ; Use 'ptr*' for classes where 'ptr' property is the value itself, otherwise
            ; the function will write to the wrong place (e.g. corrupt the HSTRING).
            ; This currently assumes 'ptr' is either the ONLY field or not a field.
            ; Integer check allows `ptr : 16` and similar (e.g. for GUID).
            ptrtype := GetPropDescProp(proto, 'ptr', 'type') ?? 0
            cca.Push( , !(ptrtype is Integer) ? 'ptr*' : 'ptr')
            frr := GetPropGet(proto, '__value') ?? false
        }
    }
    else {
        frr := fri := false
    }
    ; Build the core ComCall function with predetermined type parameters.
    fc := ComCall.Bind(idx, cca*)
    if args_to_expand.Count
        fc := _rt_get_struct_expander(args_to_expand, fc)
    ; Define internal properties for use by _rt_call.
    if IsSet(name)
        fc.DefineProp 'Name', {value: name}  ; For our use debugging; has no effect on any built-in stuff.
    fc.DefineProp 'MinParams', pv := {value: 1 + types.Length}  ; +1 for `this`
    fc.DefineProp 'MaxParams', pv
    ; Compose the ComCall and parameter filters into a function.
    fc := _rt_call.Bind(fc, stn, fri, frr)
    ; Define external properties for use by OverloadedFunc and others.
    fc.DefineProp 'MinParams', pv
    fc.DefineProp 'MaxParams', pv
    return fc
}


_rt_get_struct_expander(sizes, fc) {
    ; Map the incoming parameter index and size to outgoing parameter index and size.
    ismap := Map(), offset := 0
    for i, size in sizes {
        ismap[i + offset] := size
        offset += Ceil(size / A_PtrSize) - 1
    }
    return _rt_expand_struct_args.Bind(ismap, fc)
}

_rt_expand_struct_args(ismap, fc, args*) {
    for i, size in ismap {
        ; Removing struct from args shouldn't cause its destructor to be called (when this
        ; function returns) because it should still be on the caller's stack.  For simple
        ; structs it doesn't matter either way, because their values are copied here.
        struct := args.RemoveAt(i), new_args := []
        ; This specifically allows NumGet to read past the end of the struct when the size
        ; is not a multiple of A_PtrSize, with the additional bytes being "undefined".
        ptr := struct.ptr, endptr := ptr + struct.size
        while ptr < endptr
            new_args.Push(NumGet(ptr, 'ptr')), ptr += A_PtrSize
        args.InsertAt(i, new_args*)
    }
    return fc(args*)
}

_rt_rethrow(fc, e) {
    if DllCall("combase.dll\GetRestrictedErrorInfo", 'ptr*', rer := ComValue(13, 0), 'int') = 0 {
        ComCall(3, rer, 'ptr*', &pmsg1:=0, 'uint*', &hr:=0, 'ptr*', &pmsg2:=0, 'ptr*', &pjunk:=0)
        e.Extra := StrGet(pmsg2)
        DllCall("oleaut32.dll\SysFreeString", 'ptr', pmsg1)
        DllCall("oleaut32.dll\SysFreeString", 'ptr', pmsg2)
        DllCall("oleaut32.dll\SysFreeString", 'ptr', pjunk)
    }
    e.Stack := RegExReplace(e.Stack, 'm)^\Q' StrReplace(A_LineFile, '\E', '\E\\E\Q') '\E \(\d+\) :.*\R',, &count)
    if count && RegExMatch(e.Stack, '^(?<File>.*) \((?<Line>\d+)\) :', &m) {
        e.Stack := StrReplace(e.Stack, '[Func.Prototype.Call]', '[' fc.Name ']')
        e.File := m.File, e.Line := m.Line
    }
    throw
}

_rt_call(fc, fa, fri, frr, args*) {
    try {
        if args.Length != fc.MinParams
            throw Error(Format('Too {} parameters passed to function {}.', args.Length < fc.MinParams ? 'few' : 'many', fc.Name), -1)
        for i, f in fa
            args[i] := f(args[i])
        (fri) && args.Push(fri())
        fc(args*)
        return frr ? (frr(args.Pop())?) : fri ? args.Pop() : ""
    } catch OSError as e {
        _rt_rethrow(fc, e)
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
    ptr : uptr
    __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
    static __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
    class Dynamic extends RtObject {
        static __new() {
            this.Prototype.DefineProp('__value', {
                get: _rt_ObjectGetValue.Bind(Object.Call.Bind(this)),
                set: _rt_ObjectSetValueObject
            })
        }
    }
}

_rt_CreateClass(classname, baseclass) {
    w := Class(classname, baseclass)
    w.DefineProp('ptr', {value: 0}) ; Block unintentional use of baseclass.ptr via inheritence.
    return w
}

_rt_CreateStructWrapper(t) {
    w := _rt_CreateClass(t.Name, ValueType)
    t.DefineProp 'Class', {value: w}
    wp := w.prototype
    pod := true
    readwriters := Map(), destructors := []
    for f in t.Fields() {
        ft := f.type
        if ft is NumberTypeInfo
            wp.DefineProp f.name, {type: ft.PropType}
        else if IsSet(fc := ft.Class?) && ObjGetDataSize(fc.Prototype) {
            wp.DefineProp f.name, {type: fc}
            pod := false
        }
        else {
            rwi := ReadWriteInfo.ForType(ft)
            fsize := rwi.Size
            wp.DefineProp f.name, {type: fsize}
            offset := wp.GetOwnPropDesc(f.name).offset
            wp.DefineProp f.name, {
                get: reader := rwi.GetReader(offset),
                set: writer := rwi.GetWriter(offset)
            }
            readwriters[reader] := writer
            if fd := rwi.GetDeleter(offset)
                destructors.Push(fd)
        }
    }
    size_before := ObjGetDataSize(wp)
    (Object.Call)(w) ; FIXME: verify need to instantiate to finalize structure/size?
    wp.DefineProp 'Size', {value: ObjGetDataSize(wp)}
    size_after := wp.Size
    if destructors.Length {
        struct_delete(destructors, this) {
            for d in destructors
                try
                    d(this)
                catch as e ; Ensure all destructors are called ...
                    thrown := e
            if IsSet(thrown)
                throw thrown ; ... and the last error is reported.
        }
        struct_copy(readwriters, this, ptr) {
            for reader, writer in readwriters
                writer(ptr, reader(this))
            ; FIXME: doesn't copy new-struct-based properties
        }
        wp.DefineProp 'CopyToPtr', {call: struct_copy.Bind(readwriters)}
        wp.DefineProp '__delete', {call: struct_delete.Bind(destructors)}
    }
    ; FIXME: assignment to non-POD struct
    ; FIXME: assignment to POD struct with nested struct
    if pod
        wp.DefineProp '__value', {set: _rt_StructSetValuePOD}
    return w
}

_rt_stringPointerArray(strings) {
    chars := 0
    for s in strings
        chars += StrLen(s) + 1
    b := Buffer((strings.Length * A_PtrSize) + (chars * 2))
    p := b.ptr + strings.Length * A_PtrSize
    for s in strings {
        NumPut('ptr', p, b, (A_Index - 1) * A_PtrSize)
        p += StrPut(s, p)
    }
    return b
}

_rt_GetParameterizedIID(name, types) {
    static vt := Buffer(A_PtrSize)
    static pvt := NumPut("ptr", CallbackCreate(_rt_MetaDataLocate, "F"), vt) - A_PtrSize
    ; Make an array of pointers to the names.  StrPtr(names[1]) would return
    ; the address of a temporary string, so make more direct copies.
    names := [name]
    makeNames(types)
    makeNames(types) {
        for t in types {
            if t.HasProp('typeArgs') && t.typeArgs {
                ; Need the individual names of base type and each type arg.
                names.Push(t.m.GetTypeDefProps(t.t).name)
                makeNames(t.typeArgs)
            }
            else {
                names.Push(String(t))
            }
        }
    }
    namePtrArr := _rt_stringPointerArray(names)
    hr := DllCall("combase.dll\RoGetParameterizedTypeInstanceIID"
        , "uint", names.Length, "ptr", namePtrArr
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
        switch String(t.FundamentalType) {
        case "Interface":
            if !(pguid := t.GUID)
                throw Error("GUID not found for " name)
            if p := InStr(name, "``") {
                ; SetParameterizedInterface
                if A_PtrSize = 8 ; x64
                    ComCall(8, mdb, "ptr", pguid, "uint", SubStr(name, p + 1))
                else
                    ComCall(8, mdb, "int64", NumGet(pguid, "int64"), "int64", NumGet(pguid + 8, "int64"), "uint", SubStr(name, p + 1))
            }
            else {
                ; SetWinRtInterface
                if A_PtrSize = 8 ; x64
                    ComCall(0, mdb, "ptr", pguid)
                else
                    ComCall(0, mdb, "int64", NumGet(pguid, "int64"), "int64", NumGet(pguid + 8, "int64"))
            }
        case "Object":
            ; SetRuntimeClassSimpleDefault
            ComCall(4, mdb, "ptr", pname, "wstr", t.Name, "ptr", t.GUID)
        case "Delegate":
            if !(pguid := t.GUID)
                throw Error("GUID not found for " name)
            if p := InStr(name, "``") {
                ; SetParameterizedDelete
                if A_PtrSize = 8 ; x64
                    ComCall(9, mdb, "ptr", pguid, "uint", SubStr(name, p + 1))
                else
                    ComCall(9, mdb, "int64", NumGet(pguid, "int64"), "int64", NumGet(pguid + 8, "int64"), "uint", SubStr(name, p + 1))
            }
            else {
                ; SetDelegate
                if A_PtrSize = 8 ; x64
                    ComCall(1, mdb, "ptr", pguid)
                else
                    ComCall(1, mdb, "int64", NumGet(pguid, "int64"), "int64", NumGet(pguid + 8, "int64"))
            }
        case "Struct":
            names := []
            for field in t.Fields()
                names.Push(String(field.type))
            namePtrArr := _rt_stringPointerArray(names)
            ; SetStruct
            ComCall(6, mdb, "ptr", pname, "uint", names.Length, "ptr", namePtrArr)
        case "Enum":
            ; SetEnum
            ComCall(7, mdb, "ptr", pname, "wstr", t.Class.__basicType.Name)
        default:
            throw Error('Unsupported fundamental type')
        }
    }
    catch as e {
        ; @Debug-Output => {e.__class} locating metadata for {name}: {e.message}
        ; @Debug-Breakpoint
        return 0x80004005 ; E_FAIL
    }
    return 0
}
