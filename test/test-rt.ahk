#include testcase.ahk
#include ..\winrt.ahk
#include ..\windows.ahk

TestCase "RT struct.integers", () {
    wfRect := WinRT('Windows.Foundation.Rect')
    rect := wfRect()
    assert rect is wfRect
    equals rect.Size, 16
    rect.Width := 1920, rect.Height := 1080
    equals rect.X, 0 ; Zero-init
    equals rect.Width, 1920
    equals rect.Height, 1080
}

TestCase "RT struct.enum", () {
    GamepadReading := WinRT('Windows.Gaming.Input.GamepadReading')
    gr := GamepadReading()
    assert gr is GamepadReading
    equals gr.Size, 64 ; Size property is added by AutoHotkey for all structs.
    gr.LeftTrigger := 4.2
    equals String(gr.Buttons), "None"
    gr.Buttons := 1
    equals String(gr.Buttons), "Menu"
    gr.Buttons := "view" ; Set by name.
    equals String(gr.Buttons), "View"
    equals gr.LeftTrigger, 4.2
}

TestCase "RT struct.nested", () {
    p := WinRT('Windows.Foundation.Numerics.Plane')()
    p.Normal.X := 1
    p.Normal.Y := 2
    p.Normal.Z := 3
    p.D := 4
    equals p.Normal.X, 1
    equals p.Normal.Z, 3
    equals p.D, 4

    v3 := WinRT('Windows.Foundation.Numerics.Vector3')()
    v3.X := -1
    v3.Y := -2
    v3.Z := -3
    p.Normal := v3 ; Set nested struct by value.
    equals p.Normal.X, -1
    assert p.Normal != v3
}

TestCase "RT struct.string", () {
    ale := WinRT('Windows.Storage.AccessCache.AccessListEntry')()
    ale.token := "hello"
    ale.metadata := "world"
    equals ale.token ", " ale.metadata, "hello, world"
}

TestCase "RT statics", () {
    ; Static method
    equals WinRT('Windows.Data.Html.HtmlUtilities').ConvertToText("<b>Hello</b>, <i>world</i>!")
        , "Hello, world!"
    ; Static property
    MusicLib := WinRT("Windows.Storage.KnownFolders").MusicLibrary
    ; Wrapped runtime object
    equals Type(MusicLib), 'Windows.Storage.StorageFolder'
    ; Might fail on non-English systems:
    equals MusicLib.Name, "Music"
    equals MusicLib.DisplayType, "Library"
}

TestCase "RT PropertyValue", () {
    ; These tests cover:
    ;  - Static methods (no direct factory activation)
    ;  - Parameter values: Char16, Boolean, U?Int\d+, Double, Single, Rect, String
    ;  - Return values: as above, IReference<T>, enum
    ;  - Wrapping IReference<T> where object has no proper runtime class
    wfPV := WinRT('Windows.Foundation.PropertyValue')
    
    TestCase "RT PropertyValue<Char16>", () {
        ; Char16 is marshalled as a string of one character.
        pv := wfPV.CreateChar16("X") ; Returns a "reference" to a Char16.
        equals Type(pv), 'Windows.Foundation.IReference``1<Char16>'
        equals pv.Value, "X"
        ; IPropertyValue.Type : PropertyType
        pt := pv.Type
        equals Type(pt), 'Windows.Foundation.PropertyType' ; Enum type
        equals String(pt), 'Char16' ; Enum name
        equals pt.n, 10 ; Enum value
    }
    
    TestCase "RT PropertyValue<Boolean>", () {
        ; Boolean is marshalled as 0 or 1.
        pv := wfPV.CreateBoolean(42)
        equals pv.Value, true
        equals pv.Type, WinRT('Windows.Foundation.PropertyType').Boolean ; Enum reference equal for canonical values.
        equals String(pv.Type), 'Boolean' ; Enum name
    }
    
    TestCase "RT PropertyValue<Number>", () {
        ; Numeric types.
        ntypes := [
            ['Double', 4.2],
            ['UInt8', 0x105, 5], ; Using lack of overflow checking to test whether it's actually UInt8.
            ['Int16', 65535, -1], ; As above. (Int8 apparently doesn't exist in WinRT.)
            ['UInt8', 255],
            ['Int16', 0x1010],
            ['Int32', 2**30],
            ['Int64', 2**60],
        ]
        for ntype in ntypes {
            pv := wfPV.Create%ntype[1]%(ntype[2])
            equals pv.Value, ntype.Length > 2 ? ntype[3] : ntype[2] ; Round-trip value of ntype[1]
            equals Type(pv.Value), Type(ntype[2]) ; Return type
        }
        pv := wfPV.CreateSingle(4.2)
        equals Round(pv.Value, 6), Round(4.2, 6) ; Approx. round-trip value of Single
        equals Type(pv.Value), 'Float' ; Return type of Single
    }
    
    TestCase "RT PropertyValue<Rect>", () {
        ; Struct passing/return.
        wfRect := WinRT('Windows.Foundation.Rect')
        rect := wfRect(), rect.Width := 1920, rect.Height := 1080
        pv := wfPV.CreateRect(rect)
        new_rect := pv.Value
        assert new_rect is wfRect
        assert new_rect != rect && new_rect.ptr != rect.ptr ; Struct return is different struct
        rect.Width += 1
        equals new_rect.Width, 1920
        equals new_rect.Height, 1080
    }
    
    TestCase "RT PropertyValue<String>", () {
        ; Strings.
        pv := wfPV.CreateString("Hello, world!")
        equals pv.Value, "Hello, world!"
    }
    
    TestCase "RT PropertyValue<GUID>", () {
        pv := wfPV.CreateGuid(GUID('{af86E2E0-B12D-4c6a-9C5A-D7AA65101E90}'))
        assert pv.Value is GUID
        equals String(pv.Value), '{AF86E2E0-B12D-4C6A-9C5A-D7AA65101E90}'
        
        pv := wfPV.CreateGuid('{00000035-0000-0000-c000-000000000046}')
        assert pv.Value is GUID
        equals String(pv.Value), '{00000035-0000-0000-C000-000000000046}'
    }
    
    ; TODO: test Int32Array, RectArray
}

TestCase "RT Json", () {
    JsonArray := WinRT('Windows.Data.Json.JsonArray')
    JsonValue := WinRT('Windows.Data.Json.JsonValue')
    
    TestCase "RT Json - class activation", () {
        local jarr := JsonArray()
        equals Type(jarr), 'Windows.Data.Json.JsonArray'
        equals jarr.Size, 0
        equals String(jarr), "[]"
    }

    TestCase "RT Json - out object, ComObj", () {
        ; Out parameters returning objects.
        JsonArray.TryParse('["a", "b"]', &jarr)
        assert jarr is JsonArray
        equals String(jarr), '["a","b"]'
        JsonValue.TryParse('"b"', &jval)
        equals jval.ValueType, WinRT('Windows.Data.Json.JsonValueType').String
        equals String(jval.ValueType), 'String'
        jarr.IndexOf(jval, &index := 42) ; "Searches for a JsonValue object", not a value, so doesn't find it.
        equals index, 0
        ; Querying underlying COM interface.
        iid := GuidToString(WinRT.GetType('Windows.Data.Json.IJsonValue').GUID)
        ijval := ComObjQuery(jval, iid)
        jarr.SetAt(0, ijval) ; Can pass a raw ComValue.
        equals String(jarr), '["b","b"]'
    }
}

TestCase "RT out Char16", () {
    WinRT('Windows.Data.Text.UnicodeCharacters').GetSurrogatePairFromCodepoint(0x10000, &high, &low)
    equals Ord(high), 0xD800
    equals Ord(low), 0xDC00
}

TestCase "RT StorageFile (async, DateTimeOffset)", () {
    StorageFile := WinRT('Windows.Storage.StorageFile')
    async := StorageFile.GetFileFromPathAsync(A_ScriptFullPath)
    Loop
        sleep 10
    until async.status.n != 0 ; i.e. not Completed, Canceled or Error.
    sfile := async.GetResults()
    
    SplitPath A_ScriptFullPath,,, &ext
    equals sfile.FileType, "." ext
    
    ; Microsoft's documentation is misleading, as it generally shows the .NET DateTimeOffset
    ; in place of the true type, due to how it is projected in C#.  As far as I've seen, only
    ; the specific page for W.F.DateTime itself clarifies this.  Unlike DateTimeOffset, this
    ; is relative to 1601-01-01 (compatible with FILETIME for positive values), not 0001-01-01.
    date := sfile.DateCreated
    assert date is WinRT('Windows.Foundation.DateTime')
    time := date.UniversalTime ; 100-nanosecond intervals since 1601-01-01 (or prior to, if negative).
    time //= 10000000                       ; Convert to seconds.
    time += DateDiff(A_Now, A_NowUTC, "S")  ; Convert to local time.
    time := DateAdd("16010101", time, "S")  ; Convert to YYYYMMDDHH24MISS.
    ; Testing shows that StorageFile returns inaccurate times, equivalent to the loss
    ; of precision that occurs when the int64 UniversalTime is cast to 32-bit float
    ; (e.g. 133568723702598626 becomes 133568723720000000, off by about 2 seconds).
    ; File system may also affect precision.  So this only compares minutes.
    equals DateDiff(time, FileGetTime(sfile.Path, "C"), "M"), 0
}

TestCase "RT Delegate parameters", () {
    arg_tests := [
        {   ; 1. Safe baseline.
            types: [], i: []
        },
        {   ; 2. All signed integer types, in range, positive.
            types: [RtRootTypes.Int8, RtRootTypes.Int16, RtRootTypes.Int32, RtRootTypes.Int64],
            i: ['char', 100, 'short', 32000, 'int', 1000000, 'int64', 1000000000000]
        },
        {   ; 3. All signed integer types, in range, negative.
            types: [RtRootTypes.Int8, RtRootTypes.Int16, RtRootTypes.Int32, RtRootTypes.Int64],
            i: ['char', -100, 'short', -32000, 'int', -1000000, 'int64', -1000000000000]
        },
        {   ; 4. All unsigned integer types, in range (accounting for AutoHotkey limitations).
            types: [RtRootTypes.UInt8, RtRootTypes.UInt16, RtRootTypes.UInt32, RtRootTypes.UInt64],
            i: ['uchar', 200, 'ushort', 65000, 'uint', 0xF00DCAFE, 'uint64', -9223372036854775808]
        },
        {   ; 5. All signed integer types, truncated.
            types: [RtRootTypes.Int8, RtRootTypes.Int16, RtRootTypes.Int32, RtRootTypes.Int64],
            i: ['char', 0x321, 'short', 0x54321, 'int', 0x987654321, 'int64', 0xfedcba9876543210],
            o: [0x21, 0x4321, -0x789ABCDF, -0x123456789ABCDF0]
        },
        {   ; 6. All unsigned integer types, truncated.
            types: [RtRootTypes.UInt8, RtRootTypes.UInt16, RtRootTypes.UInt32, RtRootTypes.UInt64],
            i: ['uchar', 0x1AA, 'ushort', 0x2BBBB, 'uint', 0x3CCCCCCCC, 'uint64', 0xfedcba9876543210],
            o: [0xAA, 0xBBBB, 0xCCCCCCCC, -0x123456789ABCDF0]
        },
        {   ; 7. Floating-point types.
            types: [RtRootTypes.Single, RtRootTypes.Double, RtRootTypes.Single, RtRootTypes.Double],
            i: ['float', 1.2, 'double', 1.2, 'float', 1234567.89012345, 'double', 1234567.89012345],
            o: [1.2000000476837158, 1.2, 1234567.875, 1234567.89012345]
        },
        {   ; 8. Pointer integer type aliases.
            types: [RtRootTypes.IntPtr, RtRootTypes.UIntPtr],
            i: ['ptr', 0x1ffffffff, 'uptr', 0x280808080],
            o: [A_PtrSize = 8 ? 0x1ffffffff : -1, A_PtrSize = 8 ? 0x280808080 : 0x80808080]
        },
        {   ; 9. Basic non-integer integral types.
            types: [RtRootTypes.Boolean, RtRootTypes.Char16],
            i: ['int', 0x100, 'int', 0x10002b24],
            o: [false, Chr(0x2b24)]
        },
        {   ; 10. Strings.
            types: [RtRootTypes.String],
            i: [HString, "This is a string."]
        },
        {   ; 11. Objects.
            types: [RtRootTypes.Object, JV := WinRT.GetType('Windows.Data.Json.JsonValue')],
            i: ['ptr', JV.Class.Parse("{}"), 'ptr', JV.Class.Parse("1")]
        },
        {   ; 12. Enum (Int32).
            types: [WinRT.GetType('Windows.Foundation.PropertyType')],
            i: ['int', 13],
            o: [WinRT('Windows.Foundation.PropertyType').Inspectable]
        },
        {   ; 13. Enum (UInt32, FlagsAttribute).
            types: [WinRT.GetType('Windows.Storage.FileAttributes')],
            i: ['int', 0x30],
            o: [WinRT('Windows.Storage.FileAttributes')(0x30)]
        },
    ]
    for test in arg_tests {
        test_index := A_Index
        try {
            ; DelegateFactory must not be freed prior to releasing all delegates it created.
            factory := DelegateFactory(GUID(), test.types)
            b := unset
            delegate := factory((a*) => b := a)
            ComCall(3, delegate, test.i*)
            delegate := unset
            if !IsSet(b)
                throw Error('args not received or function not called')
            arg_count := test.i.Length // 2
            if b.Length != arg_count
                throw Error(Format('arg count {}, expected {}', b.Length, arg_count))
            for actual in b {
                expected := test.HasProp('o') ? test.o[A_Index] : test.i[A_Index*2]
                if Type(actual) != Type(expected)
                    throw Error(Format('arg {} type {}, expected {}', A_Index, Type(actual), Type(expected)))
                switch {
                    case actual is Object && ObjGetDataSize(actual):
                        equal := structsEqual(actual, expected)
                    case actual is EnumValue && !expected.HasOwnProp('s'):
                        equal := actual.n == expected.n
                    default:
                        equal := actual == expected
                }
                if !equal {
                    throw Error(actual is Object
                        ? Format('arg {} value not equal ({})', A_Index, Type(actual))
                        : Format('arg {} value "{}", expected "{}"', A_Index, actual, expected))
                }
            }
        }
        catch as e {
            e.Message := "Arg test " test_index "; " e.Message
            throw e
        }
    }
    structsEqual(a, b) => (
        (az := ObjGetDataSize(a)) == ObjGetDataSize(b) &&
        DllCall("RtlCompareMemory", 'ptr', ObjGetDataPtr(a), 'ptr', ObjGetDataPtr(b), 'ptr', az) == az
    )
}

TestCase "RT Delegate return value", () {
    JsonArrayType := WinRT.GetType('Windows.Data.Json.JsonArray')
    JsonArray := JsonArrayType.Class
    jarr := JsonArray()
    return_tests := [
        [RtRootTypes.Int8, 42, 'char*'],
        [RtRootTypes.Int32, 0x12345678, 'int*'],
        [RtRootTypes.Int64, 2**60, 'int64*'],
        [RtRootTypes.Single, 1.2, 'float*', 1.2000000476837158],
        [RtRootTypes.Double, 1.2, 'double*'],
        [RtRootTypes.Boolean, 0, 'int*'],
        [RtRootTypes.Boolean, 1, 'int*'],
        [RtRootTypes.Boolean, 42, 'int*', 1],
        [RtRootTypes.Char16, "x", 'ushort*', Ord("x")],
        [RtRootTypes.String, "Hello, world!", RefArgStruct(HString)],
        [JsonArrayType, jarr, 'uptr*', jarr.ptr],
    ]
    for test in return_tests {
        test_index := A_Index
        try {
            ; DelegateFactory must not be freed prior to releasing all delegates it created.
            factory := DelegateFactory(GUID(), [], test[1])
            b := unset
            delegate := factory((r => r).Bind(test[2]))
            ComCall(3, delegate, test[3], &actual := 0)
            delegate := unset
            
            expected := test[test.Has(4) ? 4 : 2]
            if Type(actual) != Type(expected)
                throw Error(Format('return type {}, expected {}', A_Index, Type(actual), Type(expected)))
            if actual !== expected {
                throw Error(actual is Object
                    ? Format('return value not equal ({})', A_Index, Type(actual))
                    : Format('return value "{}", expected "{}"', A_Index, actual, expected))
            }
        }
        catch as e {
            test_name := test[1] is RtTypeInfo
            e.Message := "Return test " test_index " (" (test[1].Name ?? test[1].Prototype.__Class) "); " e.Message
            throw e
        }
    }
}

TestCase "RT Delegate", () {
    dir := ""
    async := WinRT('Windows.Storage.StorageFile').GetFileFromPathAsync(A_ScriptFullPath)
    async.Completed := (async, status) => dir := async.GetResults().Path
    ; The wait is done this way to avoid looping infinitely in the case
    ; of the operation failing or an error being raised by the callback.
    Loop
        sleep 10
    until async.status.n != 0 ; i.e. not Completed, Canceled or Error.
    equals dir, A_ScriptFullPath
}

TestCase "ValueSet", () {
    wfPV := WinRT('Windows.Foundation.PropertyValue')
    
    set := WinRT('Windows.Foundation.Collections.ValueSet')()
    
    local last
    set.add_MapChanged changed(sender, event) {
        last := String(event.CollectionChange) ':' String(event.Key)
    }
    item1 := wfPV.CreateInt32(1)
    set.Insert("first", item1)
    equals last, "ItemInserted:first"
    
    item2 := wfPV.CreateString("B")
    set.Insert("second", item2)
    equals last, "ItemInserted:second"
}

TestCase "Windows", () {
    ; Namespace discovery is slow and complicated, so other tests use WinRT() and this is done last.
    ; Struct classes
    equals Windows.Foundation.Rect, WinRT('Windows.Foundation.Rect')
    equals Windows.Gaming.Input.GamepadReading, WinRT('Windows.Gaming.Input.GamepadReading')
    ; Static classes
    equals Windows.Data.Html.HtmlUtilities, WinRT('Windows.Data.Html.HtmlUtilities')
    equals Windows.Storage.StorageFile, WinRT('Windows.Storage.StorageFile')
    ; Activatable classes
    equals Windows.Data.Json.JsonArray, WinRT('Windows.Data.Json.JsonArray')
    equals Windows.Data.Json.JsonObject, WinRT('Windows.Data.Json.JsonObject')
    ; Enum
    equals Windows.Data.Json.JsonValueType, WinRT('Windows.Data.Json.JsonValueType')
}

; TODO: tests for interfaces, arrays
