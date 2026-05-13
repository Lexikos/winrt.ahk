
GetPropDescProp(a, aProp, descProp) {
    static GetOwnPropDesc := Object.Prototype.GetOwnPropDesc
    b := a
    while IsSet(b) && !IsSet(r := GetOwnPropDesc(b, aProp)?.%descProp%?)
        b := (b.base?)
    return (r?)
}

GetPropGet(a, name) => (GetPropDescProp(a, name, 'get')?)
