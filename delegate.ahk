/*
CreateTypedCallback(fn, opt, argTypes) {
    local readers := GetReadersForArgTypes(argTypes)
    typed_callback(argPtr) {
        args := []
        for r in readers {
            args.Push(r(argPtr))
        }
        return fn(args*)
    }
    return CallbackCreate(typed_callback, opt "&", readers.NativeSize // A_PtrSize)
}
*/

GetReadersForArgTypes(argTypes) {
    readers := [], offset := 0
    for argType in argTypes {
        rwi := ReadWriteInfo.ForType(argType)
        if rwi.Size > 8 && 8 = A_PtrSize {
            ; Structs larger than 8 bytes are passed by address on x64.
            deref_and_read(r, o, p) => r(NumGet(p, o, "ptr"))
            reader := deref_and_read.Bind(rwi.GetReader(0), offset)
            offset += A_PtrSize
        }
        else {
            reader := rwi.GetReader(offset)
            offset += A_PtrSize = 4 ? (rwi.Size + 3) // 4 * 4 : A_PtrSize
        }
        readers.Push(reader)
    }
    readers.NativeSize := offset
    return readers
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
    readers := GetReadersForArgTypes(argTypes)
    writeRet := retType && retType != FFITypes.Void
        && ReadWriteInfo.ForType(retType).GetWriter(0)
    retOffset := readers.NativeSize
    interface_method(argPtr) {
        try {
            obj := ObjFromPtrAddRef(NumGet(NumGet(argPtr, 'ptr'), A_PtrSize * 2, 'ptr'))
            argPtr += A_PtrSize
            args := []
            for readArg in readers
                args.Push(readArg(argPtr))
            retval := obj.%name%(args*)
            (writeRet) && writeRet(NumGet(argPtr, retOffset, 'ptr'), retval)
        }
        catch Any as e {
            ; @Debug-Breakpoint => {e.__Class} thrown in method {name}: {e.Message}
            return e is OSError ? e.number : 0x80004005
        }
        return 0
    }
    return CallbackCreate(interface_method, "&", retOffset // A_PtrSize + (retType ? 2 : 1))
}