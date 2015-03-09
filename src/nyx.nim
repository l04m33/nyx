import
    asyncdispatch,
    nyxpkg/server,
    nyxpkg/httphandlers,
    nyxpkg/logging


when isMainModule:
    setLogLevel(lvlDebug)

    debug("Nyx running on port 8080")
    var s = newServer("", 8080)
    waitFor(s.serve(handleHttpClient))
