TestCase(name, fn) {
    static count := (OnExit(summarize), 0), failed := 0
    summarize(*) {
        if failed
            MsgBox failed " test(s) failed of " count,, "IconX"
        else
            print "Ran " count " test(s); all passed"
    }
    count++
    try
        fn()
    catch as e
        OutputDebug("TEST FAILED: " name "`n" errline(e)), failed++
    errline(e) => e.File ;StrReplace(e.File, A_InitialWorkingDir "\") 
        . ":" e.Line " [" type(e) "]: " e.Message
        . (e.Extra != "" ? "`n`t" e.Extra : "") "`n"
    print(s) {
        ; Note: vscode-autohotkey-debug catches both of these, but prints them in different colours.
        try
            FileAppend s "`n", "*"
        catch
            OutputDebug s "`n"
    }
}

assert(condition, message:="FAIL", n:=-1) {
    if !condition
        throw Error(message, n)
}

equals(a, b) => assert(a == b, (a is Number ? a : a is String ? '"' a '"' : Type(a)) ' != ' (b is Number ? b : b is String ? '"' b '"' : Type(b)), -2)

throws(f, args*) {
    try f()
    catch Any as e {
        for a in args.Length ? args : [Error]
            if a is class and e is a
                return
        throw
    }
    m := "FAIL (didn't throw)"
    for a in args
        if a is string {
            m := a
            break
        }
    assert false, m, -2
}