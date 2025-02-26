
GetPropDescProp(a, aProp, descProp) {
    b := a
    while b && !(ObjHasOwnProp(b, aProp) && IsSet(r := b.GetOwnPropDesc(aProp).%descProp%?))
        b := b.base
    return (r?)
}

GetPropGet(a, name) => (GetPropDescProp(a, name, 'get')?)
