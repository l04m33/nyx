import macros


proc beginTest*(desc: string) =
    echo("Testing: " & desc)


proc failOne*(reason: string) =
    echo(reason)


proc fail*(reason: string) =
    echo("Aborting: " & reason)
    quit(1)


macro doCheck*(cond: expr, failProc): stmt =
    var
        lineInfo = cond.lineinfo()
        condstr = cond.toStrLit()

    result = quote do:
        if `cond`:
            discard
        else:
            `failProc`("Check failed: " & `lineInfo` & ": " & `condstr`)


template check*(cond: expr): stmt =
    doCheck(cond, failOne)


template require*(cond: expr): stmt =
    doCheck(cond, fail)
