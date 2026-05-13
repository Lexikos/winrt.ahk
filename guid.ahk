struct GUID {
    ptr : 16
    
    static Call(a?) {
        if !IsSet(a)
            return super.Call()
        if a is Integer
            return a ? this.at(a) : throw(ValueError("Null pointer"))
        return (g := super.Call(), g.__value := a, g)
    }
    
    __value {
        set {
            if value is String
                DllCall("ole32.dll\IIDFromString", 'wstr', value, 'ptr', this, 'hresult')
            else if value is GUID
                DllCall("RtlMoveMemory", 'ptr', this, 'ptr', value, 'ptr', 4)
            else
                throw TypeError("Type not convertible to GUID", -1, Type(value))
        }
    }
    
    static __new() {
        DefineProp this.Prototype, 'ToString', {call: GuidToString}
    }
}

GuidToString(guid) {
    buf := Buffer(78)
    DllCall("ole32.dll\StringFromGUID2", "ptr", guid, "ptr", buf, "int", 39)
    return StrGet(buf, "UTF-16")
}