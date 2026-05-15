#include winmd.ahk

#include guid.ahk
#include hstring.ahk
#include overload.ahk
#include util.ahk

class MetaDataModule extends mdModule {
    StaticAttr => _rt_CacheAttributeCtors(this, this, 'StaticAttr')
    FactoryAttr => _rt_CacheAttributeCtors(this, this, 'FactoryAttr')
    ActivatableAttr => _rt_CacheAttributeCtors(this, this, 'ActivatableAttr')
    ComposableAttr => _rt_CacheAttributeCtors(this, this, 'ComposableAttr')
    
    AddFactoriesToWrapper(w, t) {
        if t.HasIActivationFactory {
            this.AddIActivationFactoryToWrapper(w, t)
        }
        for f in t.Factories() {
            this.AddInterfaceToWrapper(w, f, false, "Call")
        }
        for f in t.Composers() {
            this.AddInterfaceToWrapper(w, f, false, "Call", true)
            ; Base classes are required to be [Composable], but the corresponding interface
            ; can be entirely empty if consumers of the API aren't supposed to subclass it.
            if w.HasOwnProp("Call")
                AddMethodOverloadTo(w, "Call", w => w(unset, unset), w.prototype.__class ".")
        }
    }
    
    AddIActivationFactoryToWrapper(w, t) {
        ActivateInstance(iid, cls) {
            ; cls.ptr is IActivationFactory*; this calls ActivateInstance.
            static new := Struct.Call
            ComCall(6, cls, 'ptr*', insp := ComValue(13, 0))
            ; insp is not necessarily the default interface of the class.
            ComCall(0, insp, 'ptr', iid, 'ptr*', inst := new(cls))
            return inst
        }
        AddMethodOverloadTo(w, "Call", ActivateInstance.Bind(t.GUID), w.prototype.__class ".")
    }
    
    CreateInterfaceWrapper(t) {
        w := _rt_CreateClass(t_name := t.Name, RtObject)
        DefineProp t, 'Class', {value: w}
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
        DefineProp t, 'Class', {value: w}
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
        addRequiredInterfaces(wp, t, isSealedClass) {
            for ti, impl in t.Implements() {
                if wrapped.has(ti_name := ti.Name)
                    continue
                wrapped[ti_name] := true
                ; Skip ComObjQuery only for the default interface on a sealed class.
                ; For a composable class, the method needs to handle `this.ptr` being
                ; the default interface of a derived class.
                isdefault := isSealedClass && this.GetCustomAttributeByName(impl
                    , 'Windows.Foundation.Metadata.DefaultAttribute')
                ti.m.AddInterfaceToWrapper(wp, ti, isdefault)
                ; Interfaces "required" by ti are also implemented by the class
                ; even if it doesn't "require" them directly (sometimes it does).
                addRequiredInterfaces(wp, ti, false)
            }
        }
        ; Add instance interfaces:
        addRequiredInterfaces(w.prototype, t, t.IsSealed)
        if wrapped.Count
            this.AddInterfaceCoercion(w.prototype, t)
        return w
    }
    
    AddInterfaceToWrapper(w, t, isdefault:=false, nameoverride:=false, isComposer:=false) {
        if isdefault
            iid := "" ; Skip QueryInterface calls for the default interface.
        else if pguid := t.GUID
            iid := GuidToString(pguid)
        else
            ; @Debug-Output => Interface {t.Name} can't be added because it has no GUID
            return
        name_prefix := (w.prototype?.__class ?? w.__class) "."
        for method in t.Methods() {
            name := nameoverride ? nameoverride : method.name
            types := t.MethodArgTypes(method.sig)
            if isComposer {
                ; The last parameter of a composition factory method is always
                ; the "the non-delegating IInspectable** [out] parameter".
                ; Normal handling would QueryInterface for the class' default interface,
                ; which would give an external interface instead of the non-delegating one
                ; which is used inside subclasses.
                types[-1] := {Class: RtObject.Ref}
            }
            wrapper := MethodWrapper(5 + A_Index, iid, types, name_prefix name)
            if method.flags & 0x400 { ; tdSpecialName
                switch SubStr(name, 1, 4) {
                case "get_":
                    DefineProp w, SubStr(name, 5), {Get: wrapper}
                    continue
                case "put_":
                    DefineProp w, SubStr(name, 5), {Set: wrapper}
                    continue
                }
            }
            AddMethodOverloadTo(w, name, wrapper, name_prefix)
        }
    }
    
    AddInterfaceCoercion(w, t) {
        DefineProp(w, '__value', {
            ; Coerce assigned object/interface pointer to the right interface.
            set: _rt_ObjectSetValue.Bind(t.GUID),
            ; Wrap according to runtime class, if it can vary from t.Class.
            get: (t.typeArgs ? _rt_GenericGetValue : _rt_ObjectGetValue).Bind(t.Class)
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
            DefineProp o, names[A_Index], {value: mrs[A_Index] ?? -1}
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
    cca := []
    for t in types {
        if IsSet(tcls := t.Class?)
            cca.Push( , tcls)
        else {
            ; TODO: Array arg support
            return ((ts, *) => throw(Error("Unsupported arg type " ts, -1))).Bind(String(t))
        }
    }
    ; rettype from metadata translates to a ref out parameter at the end.
    if rettype != FFITypes.Void {
        if rettype is NumberTypeInfo {
            fri := [0]
            cca.Push( , rettype.ArgType '*') ; Instruct ComCall to pass the value by address.
        } else if IsSet(rc := rettype.Class?) {
            fri := [unset]
            cca.Push( , rettype.Class.Ref ?? rettype.Class.Ptr)
        } else
            return (*) => throw(Error("Unhandled return type " String(rettype)))
    }
    else {
        fri := false
    }
    ; Build the core ComCall function with predetermined type parameters.
    fc := ComCall.Bind(idx, cca*)
    ; Define internal properties for use by _rt_call.
    if IsSet(name)
        DefineProp fc, 'Name', {value: name}  ; For our use debugging; has no effect on any built-in stuff.
    DefineProp fc, 'MinParams', pv := {value: 1 + types.Length}  ; +1 for `this`
    DefineProp fc, 'MaxParams', pv
    ; Compose the ComCall and parameter filters into a function.
    fc := _rt_call.Bind(fc, iid, fri)
    ; Define external properties for use by OverloadedFunc and others.
    DefineProp fc, 'MinParams', pv
    DefineProp fc, 'MaxParams', pv
    return fc
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

_rt_call(fc, iid, fri, args*) {
    try {
        if args.Length != fc.MinParams
            throw Error(Format('Too {} parameters passed to function {}.', args.Length < fc.MinParams ? 'few' : 'many', fc.Name), -1)
        (iid) && args[1] := ComObjQuery(args[1], iid)
        (fri) && args.Push(&retval := fri[1]?)
        fc(args*)
        if fri
            return (retval?)
    } catch OSError as e {
        _rt_rethrow(fc, e)
    }
}


struct RtAny {
    static __new() {
        if this = RtAny ; Subclasses will inherit it anyway.
            DefineProp(this, '__set', {call: this.prototype.__set})
    }
    static Call(*) {
        throw Error("This class is abstract and cannot be constructed.", -1, this.prototype.__class)
    }
    __set(name, *) {
        throw PropertyError(Format('This value of type "{}" has no property named "{}".', type(this), name), -1)
    }
    static Ref => super.Ptr
}

struct RtObject extends RtAny {
    ptr : IntPtr
    __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
    static __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
    struct Dynamic extends RtObject {
        static __new() {
            DefineProp(this.Prototype, '__value', {
                get: _rt_ObjectGetValue.Bind(this),
                set: _rt_ObjectSetValueObject
            })
        }
    }
}

_rt_CreateClass(classname, baseclass) {
    w := Class(classname, baseclass)
    DefineProp(w, 'ptr', {value: 0}) ; Block unintentional use of baseclass.ptr via inheritence.
    return w
}

_rt_CreateStructWrapper(t) {
    w := _rt_CreateClass(t.Name, ValueType)
    DefineProp t, 'Class', {value: w}
    wp := w.prototype
    pod := true
    for f in t.Fields() {
        ft := f.type
        DefineProp wp, f.name, {type: ft.Class}
        if !(ft is NumberTypeInfo)
            pod := false
    }
    ; FIXME: assignment to non-POD struct
    ; FIXME: assignment to POD struct with nested struct
    if pod
        DefineProp wp, '__value', {set: _rt_StructSetValuePOD}
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
