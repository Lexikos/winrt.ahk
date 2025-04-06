#include hstring.ahk

class FFITypes {
    static NumTypeSize := Map()
    static __new() {
        for t in [
            [1,  'Int8' ,  'char' ,  'i8'],  ; Int8 is not used in WinRT, but maybe Win32metadata.
            [1, 'UInt8' , 'uchar' ,  'u8'],
            [2,  'Int16',  'short', 'i16'],
            [2, 'UInt16', 'ushort', 'u16'],
            [4,  'Int32',  'int'  , 'i32'],
            [4, 'UInt32', 'uint'  , 'u32'],
            [8,  'Int64',  'int64', 'i64'],
            [8, 'UInt64', 'uint64', 'u64'],
            [4, 'Single', 'float' , 'f32'],
            [8, 'Double', 'double', 'f64'],
            [A_PtrSize, 'IntPtr', 'ptr', 'iptr'],
            [A_PtrSize, 'UIntPtr', 'uptr', 'uptr'],
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
    static prototype.ReadWriteInfo := false
}

class NumberTypeInfo extends BasicTypeInfo {
    __new(size, name, nt, pt) {
        this.Name := name
        this.Size := size
        this.ReadWriteInfo := ReadWriteInfo.FromArgPassInfo(
            this.ArgPassInfo := ArgPassInfo(nt, false, false)
        )
        this.PropType := pt
        this.ArgType := nt
    }
}

class RtBoolean {
    v : u8
    __value {
        get => this.v
        set => this.v := !!value
    }
}

class RtChar16 {
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

class ReadWriteInfo {
    /*
    GetReader(offset:=0)
    GetWriter(offset:=0)
    GetDeleter(offset:=0)
    Size => Integer
    */
    
    static ForType(typeinfo) {
        return typeinfo.ReadWriteInfo
            || (api := typeinfo.ArgPassInfo) && this.FromArgPassInfo(api)
            || throw(Error("No ReadWriteInfo for type " typeinfo.Name))
    }
    
    class FromArgPassInfo extends ReadWriteInfo {
        __new(api) {
            this.api := api
            this.Size := FFITypes.NumTypeSize[api.NativeType]
        }
        
        GetReader(offset:=0) => (
            f := this.api.NativeToScript,
            nt := this.api.NativeType,
            f ? (ptr) => f(NumGet(ptr, offset, nt))
              : (ptr) =>  (NumGet(ptr, offset, nt))
        )
        
        GetWriter(offset:=0) => (
            f := this.api.ScriptToNative,
            nt := this.api.NativeType,
            f ? (ptr, value) => NumPut(nt, f(value), ptr, offset)
              : (ptr, value) => NumPut(nt,  (value), ptr, offset)
        )
        
        GetDeleter(offset:=0) => false
    }
}
