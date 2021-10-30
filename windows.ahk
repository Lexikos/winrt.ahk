class RtNamespace {
    static __new() {
        this.DefineProp '__set', {call: RtAny.__set}
        this.prototype.DefineProp '__set', {call: RtAny.__set}
    }
    __new(name) {
        this.DefineProp '_name', {value: name}
    }
    __call(name, params) => this.__get(name, [])(params*)
    __get(name, params) {
        this._populate()
        if this.HasOwnProp(name)
            return params.Length ? this.%name%[params*] : this.%name%
        try
            cls := WinRT(typename := this._name "." name)
        catch OSError as e {
            throw (e.number != 0x80073D54 || e.extra != typename) ? e
                : PropertyError("Unknown property, class or namespace", -1, typename)
        }
        this.DefineProp name, {get: this => cls, call: (this, p*) => cls(p*)}
        return params.Length ? cls[params*] : cls
    }
    __enum(n:=1) => (
        this._populate(),
        this.__enum(n)
    )
    _populate() {
        ; Subclass should override this and call super._populate().
        enum_ns_props(this, n:=1) {
            next_prop := this.OwnProps()
            next_namespace(&name:=unset, &value:=unset) {
                loop
                    if !next_prop(&name, &value)
                        return false
                until value is RtNamespace
                return true
            }
            return next_namespace
        }
        ; Subsequent calls to __enum() should enumerate the populated properties.
        this.DefineProp '__enum', {call: enum_ns_props}
        ; Subsequent calls to _populate() should have no effect.
        this.DefineProp '_populate', {call: IsObject}
        ; Find any direct child namespaces defined in files (for Windows and Windows.UI).
        Loop Files A_WinDir "\System32\WinMetadata\" this._name ".*.winmd", "F" {
            name := SubStr(A_LoopFileName, StrLen(this._name) + 2)
            name := SubStr(name, 1, InStr(name, ".") - 1)
            if !this.HasOwnProp(name)
                this.DefineProp name, {value: RtNamespace(this._name "." name)}
        }
        ; Find namespaces in winmd files.
        this._populateFromModule()
    }
    _populateFromModule() {
        if this.HasOwnProp('_m')
            return
        this.DefineProp '_m', {
            value: m := RtMetaDataModule.Open(RtNamespace.GetPath(this._name))
        }
        prefix := this._name "."
        ; Find all namespaces in this module by enumerating typedefs.
        for td in m.EnumTypeDefs() {
            name := m.GetTypeDefProps(td)
            if SubStr(name, 1, StrLen(prefix)) = prefix {
                x := this, p2 := StrLen(prefix)
                ; For each child namespace in this type name...
                while p2 := InStr(name, ".",, p1 := p2 + 1) {
                    name_part := SubStr(name, p1, p2 - p1)
                    if !x.HasOwnProp(name_part) {
                        ns := RtNamespace(SubStr(name, 1, p2 - 1))
                        ; Since this namespace hasn't already been discovered as a *.winmd,
                        ; it must only be defined in this module.
                        ns.DefineProp '_m', {value: m}
                        x.DefineProp name_part, {value: ns}
                    }
                    x := x.%name_part%
                }
            }
            else {
                D 'unexpected typedef ' name
            }
        }
    }
    static GetPath(name) => A_WinDir "\System32\WinMetadata\" name ".winmd"
}

class Windows {
    static __new() {
        ; Transform this static class into an instance of RtNamespace.
        this._name := "Windows"
        this.DeleteProp 'Prototype'
        this.base := RtNamespace.Prototype
    }
    static __get(name, params) {
        if !FileExist(RtNamespace.GetPath(fname := this._name "." name))
            throw Error("Non-existent namespace or missing winmd file.", -1, name)
        this.DefineProp name, {value: n := RtNamespace(fname)}
        return n
    }
    static _populateFromModule() => 0
}
