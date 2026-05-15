#include guid.ahk
#include util.ahk

struct RtDelegate extends RtAny {
    ptr : IntPtr
    __delete() {
        (this.ptr) && ObjRelease(this.ptr)
    }
    __value {
        set {
            if value.base != this.base {
                if !HasMethod(value)
                    throw TypeError(Format("Value of type {} is not callable", Type(value)))
                value := this.Wrap(value)
            }
            old := this.ptr, ObjAddRef(this.ptr := value.ptr), old && ObjRelease(old)
        }
    }
    static __new() {
        ; delegate : Class(RtDelegate, typeinfo)
        DefineProp this, '__new', {call: createDelegateClass(this, typeinfo) {
            ; delegate.Wrap(value) -- first call
            static initialWrapDelegate(typeinfo, this, value) {
                methods := [typeinfo.Methods()*]
                if methods.Length != 2 || (methods[1].Name '|' methods[2].Name) != '.ctor|Invoke'
                    throw ValueError("Unexpected delegate typeinfo")
                method := methods[2] ; Invoke
                argTypes := typeinfo.MethodArgTypes(method.sig)
                retType := argTypes.RemoveAt(1)
                factory := DelegateFactory(typeinfo.GUID, argTypes, retType)
                DefineProp(this.base, 'Wrap', {call: wrapDelegate.Bind(factory)})
                return factory(value)
            }
            ; delegate.Wrap(value) -- subsequent calls
            static wrapDelegate(factory, this, value) {
                return factory(value)
            }
            this.Prototype.__Class := typeinfo.Name
            DefineProp this.Prototype, 'Wrap', {call: initialWrapDelegate.Bind(typeinfo)}
        }}
    }
}

class DelegateFactory {
    __new(iid, argTypes, retType:=false) {
        cb := CreateComMethodCallback('Call', argTypes, retType)
        this.mtbl := CreateComMethodTable([cb], iid)
    }
    Call(fn) {
        delegate := DllCall("msvcrt\malloc", "ptr", A_PtrSize * 3, "cdecl ptr")
        NumPut(
            "ptr", this.mtbl.ptr,       ; method table
            "ptr", 1,                   ; ref count
            "ptr", ObjPtrAddRef(fn),    ; target function
            delegate)
        return ComValue(13, delegate)
    }
}

CreateComMethodTable(callbacks, iid) {
    iunknown_addRef(this) {
        ; ++this.refCount
        NumPut("ptr", refCount := NumGet(this, A_PtrSize, "ptr") + 1, this, A_PtrSize)
        return refCount
    }
    iunknown_release(this) {
        ; if !--this.refCount
        NumPut("ptr", refCount := NumGet(this, A_PtrSize, "ptr") - 1, this, A_PtrSize)
        if !refCount {
            local obj
            ObjRelease(obj := NumGet(this, A_PtrSize * 2, "ptr"))
            DllCall("msvcrt\free", "ptr", this, "cdecl")
        }
        return refCount
    }
    iid := GuidToString(iid)
    iunknown_queryInterface(this, riid, ppvObject) {
        riid := GuidToString(riid)
        switch riid {
        case iid, "{00000000-0000-0000-C000-000000000046}":
            iunknown_addRef(this)
            NumPut("ptr", this, ppvObject)
            return 0
        }
        NumPut("ptr", 0, ppvObject)
        return 0x80004002
    }
    
    static p_addRef := CallbackCreate(iunknown_addRef, "F", 1)
    static p_release := CallbackCreate(iunknown_release, "F", 1)
    ; FIXME: for general use, free p_query when mtbl is freed (which never happens for WinRT)
    p_query := CallbackCreate(iunknown_queryInterface, "F", 3)
    
    mtbl := Buffer((3 + callbacks.Length) * A_PtrSize)
    NumPut("ptr", p_query, "ptr", p_addRef, "ptr", p_release, mtbl)
    for callback in callbacks {
        NumPut("ptr", callback, mtbl, (2 + A_Index) * A_PtrSize)
    }
    return mtbl
}

CreateComMethodCallback(name, argTypes, retType:=false) {
    types := [IntPtr]
    for t in argTypes
        types.Push(t.Class)
    if retType == FFITypes.Void
        retType := false
    if retType
        types.Push(retType.Class.Ref ?? retType.Class.Ptr)
    types.Push(UInt32)
    interface_method(thisPtr, args*) {
        try {
            obj := ObjFromPtrAddRef(NumGet(thisPtr, A_PtrSize * 2, 'ptr'))
            if retType
                args.Pop().__value := obj.%name%(args*)
            else
                obj.%name%(args*)
        }
        catch Any as e {
            ; @Debug-Output => {e.__Class} thrown in method {name}: {e.Message}
            ; @Debug-Output => {e.File}:{e.Line}    {e.Extra}
            return e is OSError ? e.number : 0x80004005
        }
        return 0
    }
    return CallbackCreate(interface_method,, types)
}