class ValueType extends RtAny {
    static __new() {
        this.DefineProp('Call', Object.GetOwnPropDesc('Call'))
        this.Prototype.DefineProp('Ptr', {get: ObjGetDataPtr})
    }
    CopyToPtr(ptr) {
        DllCall('msvcrt\memcpy', 'ptr', ptr, 'ptr', this, 'ptr', this.Size, 'cdecl')
    }
}

_rt_StructSetValuePOD(this, value) {
    if !HasBase(value, this.base)
        throw TypeError(Format('{} cannot be assigned to {}', Type(value), Type(this)))
    DllCall("RtlMoveMemory", 'ptr', ObjGetDataPtr(this), 'ptr', ObjGetDataPtr(value), 'ptr', ObjGetDataSize(this))
}

class EnumValue extends RtAny {
    static Call(n?) {
        static new := Object.Call
        if !IsSet(n)
            return new(this) ; Always a new (mutable) instance.
        if e := this.__item.get(n, 0)
            return e
        e := new(this), e.n := n
        return e
    }
    static Parse(v) { ; TODO: parse space-delimited strings for flag enums
        if v is this
            return v.n
        if v is Integer
            return v ; this[v].n would only permit explicitly defined values, but Parse is currently used for all enum args, so this isn't suitable for flag enums.
        if v is String
            return this.%v%.n
        throw TypeError(Format('Value of type "{}" cannot be converted to {}.', type(v), this.prototype.__class), -1)
    }
    __value {
        set {
            if value is EnumValue
                this.n := value.n
            else if value is Integer
                this.n := value
            else if value is String
                this.n := this.__map[value].n
            else
                throw TypeError(Format('{} cannot be assigned to {}', Type(value), Type(this)))
        }
    }
    ; TODO: Projections for flag enums (perhaps space delimited string or method to test for flags by name)
    s => this.__map[this.n]?.s ?? String(this.n)
    ToString() => this.s
}

_rt_CreateEnumWrapper(t) {
    static new := Object.Call
    w := _rt_CreateClass(t.Name, EnumValue)
    t.DefineProp 'Class', {value: w}
    def(n, v) => w.DefineProp(n, {value: v})
    def '__item', items := Map()
    items.CaseSense := 0
    fields := [t.Fields()*]
    ; "The underlying integer type of the enum appears as the first row in the Field table"
    if (valueField := fields.RemoveAt(1)).flags != 0x601 ; Private | SpecialName | RTSpecialName
        throw Error("Unexpected field #1 for " t.Name)
    def '__basicType', valueField.Type
    static validTypeMap := Map('Int32', 'i32', 'UInt32', 'u32')
    ; n is the actual value of the enum (must be defined before constructing any).
    w.Prototype.DefineProp 'n', {type: validTypeMap[valueField.Type.Name]}
    w.Prototype.DefineProp '__map', {value: items}
    w.Prototype.DefineProp '__value', {get: get_enum_value(this) {
        ; Never return this; its structured data might be stack-allocated.
        return this.__map[this.n] ?? (e := new(w), e.n := this.n, e)
    }}
    ; Define and map enum constants.
    for f in fields {
        if f.flags != 0x8056 { ; public | static | literal | hasdefault
            ; @Debug-Output => Unexpected field flags {f.flags} in enum {t.Name}
            continue
        }
        e := new(w), e.n := f.value
        e.DefineProp 's', {value: f.name}
        def f.name, items[f.name] := items[f.value] := e
    }
    return w
}
