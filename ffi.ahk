#include hstring.ahk

class FFITypes {
    static NumTypeSize := Map()
    static __new() {
        for t in [
            [1,  'Int8' ,  'char' , Int8],  ; Int8 is not used in WinRT, but maybe Win32metadata.
            [1, 'UInt8' , 'uchar' , UInt8],
            [2,  'Int16',  'short', Int16],
            [2, 'UInt16', 'ushort', UInt16],
            [4,  'Int32',  'int'  , Int32],
            [4, 'UInt32', 'uint'  , UInt32],
            [8,  'Int64',  'int64', Int64],
            [8, 'UInt64', 'uint64', Int64],
            [4, 'Single', 'float' , Float32],
            [8, 'Double', 'double', Float64],
            [A_PtrSize, 'IntPtr', 'ptr', IntPtr],
            [A_PtrSize, 'UIntPtr', 'ptr', IntPtr],
            ] {
            this.NumTypeSize[t[3]] := t[1]
            this.%t[2]% := NumberTypeInfo(t*)
        }
        for t in ['Attribute', 'Void'] {
            this.%t% := BasicTypeInfo(t)
        }
    }
}

class RtRootTypes extends FFITypes {
    static __new() {
        t := [
            ['Attribute', {
                TypeClass: RtTypeInfo.Attribute,
            }],
            ['Boolean', {
                Class: RtBoolean,
            }],
            ['Char16', {
                Class: RtChar16,
            }],
            ['Delegate', {
                TypeClass: RtTypeInfo.Delegate,
            }],
            ['Enum', {
                TypeClass: RtTypeInfo.Enum,
                Class: EnumValue,
            }],
            ['Guid', {
                Class: GUID, Size: 16
            }],
            ['Interface', {
                TypeClass: RtTypeInfo.Interface,
                Class: RtObject.Dynamic,
            }],
            ['Object', {
                TypeClass: RtTypeInfo.Object,
                Class: RtObject.Dynamic,
            }],
            ['String', {
                Class: HString,
            }],
            ['Struct', {
                TypeClass: RtTypeInfo.Struct,
            }],
            ['Type', {}], ; Only used in Attribute constructors (metadata, not runtime)
        ]
        for t in t {
            bti := this.%t[1]% := BasicTypeInfo(t*)
            if t[2].HasProp('TypeClass')
                t[2].TypeClass.Prototype.FundamentalType := bti
        }
    }
}

class BasicTypeInfo {
    __new(name, props:=unset) {
        this.Name := name
        if IsSet(props)
            for name, value in props.OwnProps()
                this.%name% := value
    }
    ToString() => this.Name
    FundamentalType => this
    static prototype.ArgPassInfo := false
}

class NumberTypeInfo extends BasicTypeInfo {
    __new(size, name, nt, pt) {
        this.Name := name
        this.Size := size
        this.ArgPassInfo := ArgPassInfo(nt, false, false)
        this.Class := pt
        this.ArgType := nt
    }
}

struct RtBoolean extends ValueType {
    v : u8
    __value {
        get => this.v
        set => this.v := !!value
    }
}

struct RtChar16 extends ValueType {
    v : u16
    __value {
        get => Chr(this.v)
        set => this.v := Ord(value)
    }
}

class ArgPassInfo {
    /*
    ScriptToNative := (scriptValue) => nativeValue
    NativeToScript := (nativeValue) => scriptValue
    NativeType := Ptr | Int | UInt | ...
    */
    __new(nt, stn, nts) {
        this.NativeType := nt
        this.ScriptToNative := stn
        this.NativeToScript := nts
    }
    
    static Unsupported := this('Unsupported', false, false)
}
