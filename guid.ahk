class GUID {
    ptr : 16
    
    static Call(a?) {
        if !IsSet(a)
            return super.Call()
        if a is String {
            DllCall("ole32.dll\IIDFromString", "wstr", a, "ptr", g := super.Call(), "hresult")
            return g
        }
        if a is Integer
            return StructFromPtr(this, a)
        throw TypeError("Unexpected parameter type", -1, Type(a))
    }
    
    static __new() {
        this.Prototype.DefineProp 'ToString', {call: GuidToString}
    }
}

GuidToString(guid) {
    buf := Buffer(78)
    DllCall("ole32.dll\StringFromGUID2", "ptr", guid, "ptr", buf, "int", 39)
    return StrGet(buf, "UTF-16")
}