import
    asyncdispatch,
    nyxpkg/server,
    nyxpkg/client,
    nyxpkg/httphandlers,
    nyxpkg/urldispatch,
    nyxpkg/logging


when isMainModule:
    setLogLevel(lvlDebug)

    debug("Nyx running on port 8080")
    var s = newServer("", 8080)

    proc rootFactory(): UrlResource =
        return newStaticRoot(".")

    proc handler(c: Client): Future[Client] {.async.} =
        return (await handleHttpClient(c, rootFactory))

    waitFor(s.serve(handler))
