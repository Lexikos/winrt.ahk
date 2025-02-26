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

TestCase "RT Classes", () {
    ; Static method
    equals Windows.Data.Html.HtmlUtilities.ConvertToText("<b>Hello</b>, <i>world</i>!")
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
    ; PropertyValue has all of the fundamental types, so is a good candidate for
    ; testing the automatic wrapping of runtime classes.  The first step (wrapping
    ; the class) requires minimally dealing with all fundamental types as [in] args.
    wfPV := WinRT('Windows.Foundation.PropertyValue')
    ; Char16 is marshalled as a string of one character.
    pv := wfPV.CreateChar16("X") ; Returns a "reference" to a Char16.
    equals Type(pv), 'Windows.Foundation.IReference``1<Char16>'
    equals pv.Value, "X"
    ; IPropertyValue.Type : PropertyType
    pt := pv.Type
    equals Type(pt), 'Windows.Foundation.PropertyType' ; Enum type
    equals String(pt), 'Char16' ; Enum name
    equals pt.n, 10 ; Enum value
    ; Boolean is marshalled as 0 or 1.
    pv := wfPV.CreateBoolean(42)
    equals pv.Value, true
    equals pv.Type, WinRT('Windows.Foundation.PropertyType').Boolean ; Enum reference equal for canonical values.
    equals String(pv.Type), 'Boolean' ; Enum name
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
    ; Struct passing/return.
    rect := Windows.Foundation.Rect(), rect.Width := 1920, rect.Height := 1080
    pv := wfPV.CreateRect(rect)
    new_rect := pv.Value
    assert new_rect is Windows.Foundation.Rect
    assert new_rect != rect && new_rect.ptr != rect.ptr ; Struct return is different struct
    rect.Width += 1
    equals new_rect.Width, 1920
    equals new_rect.Height, 1080
    ; Guid (it's a fundamental type, not defined as a struct in the metadata).
    pv := wfPV.CreateGuid(GUID("{af86E2E0-B12D-4c6a-9C5A-D7AA65101E90}"))
    assert pv.Value is GUID
    equals String(pv.Value), '{AF86E2E0-B12D-4C6A-9C5A-D7AA65101E90}'
    ; Strings.
    pv := wfPV.CreateString("Hello, world!")
    equals pv.Value, "Hello, world!"
    
    ; TODO: test Int32Array, RectArray
}

TestCase "RT Json (out object, ComObj)", () {
    ; Out parameters returning objects.
    Json := Windows.Data.Json
    Json.JsonArray.TryParse('["a", "b"]', &jarr)
    assert jarr is Json.JsonArray
    equals String(jarr), '["a","b"]'
    Json.JsonValue.TryParse('"b"', &jval)
    equals jval.ValueType, Json.JsonValueType.String
    jarr.IndexOf(jval, &index := 42) ; "Searches for a JsonValue object", not a value, so doesn't find it.
    equals index, 0
    ; Querying underlying COM interface (GUID is our internal property; a pointer).
    iid := GuidToString(WinRT.GetType('Windows.Data.Json.IJsonValue').GUID)
    ijval := ComObjQuery(jval, iid)
    jarr.SetAt(0, ijval) ; Can pass a raw ComValue.
    equals String(jarr), '["b","b"]'
}

TestCase "RT out Char16", () {
    Windows.Data.Text.UnicodeCharacters.GetSurrogatePairFromCodepoint(0x10000, &high, &low)
    equals Ord(high), 0xD800
    equals Ord(low), 0xDC00
}

TestCase "RT StorageFile (async, DateTimeOffset)", () {
    StorageFile := Windows.Storage.StorageFile
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
    assert date is Windows.Foundation.DateTime
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

TestCase "RT Delegate", () {
    dir := ""
    async := Windows.Storage.StorageFile.GetFileFromPathAsync(A_ScriptFullPath)
    async.Completed := (async, status) => dir := async.GetResults().Path
    ; The wait is done this way to avoid looping infinitely in the case
    ; of the operation failing or an error being raised by the callback.
    Loop
        sleep 10
    until async.status.n != 0 ; i.e. not Completed, Canceled or Error.
    equals dir, A_ScriptFullPath
}

; TODO: tests for interfaces, delegates, arrays
