
GetPropDescProp(a, aProp, descProp) {
    b := a
    while b && !(ObjHasOwnProp(b, aProp) && (r := b.GetOwnPropDesc(aProp).%descProp%?, IsSet(r)))
        b := b.base
    return (r?)
}

GetPropGet(a, name) => (GetPropDescProp(a, name, 'get')?)
