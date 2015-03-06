import
    asyncdispatch,
    asyncnet,
    strutils,
    tables,
    nyxpkg/client,
    nyxpkg/server,
    nyxpkg/http,
    nyxpkg/httpmethods,
    nyxpkg/io,
    nyxpkg/logging


proc handleClient(client: Client): Future[Client] {.async.} =
    var req = await newHttpReq(client.reader)

    if req.meth == nil:
        when not defined(nolog):
            var cid = client.id()
            debug("cid = $#, failed to parse request method" % [$cid])
        return client

    var status = await methodHandlers[req.meth.toUpper()](client, req)
    when not defined(nolog):
        var cid = client.id()
        debug("cid = $#, status = $#" % [$cid, $status])

    return client


when isMainModule:
    setLogLevel(lvlDebug)

    debug("Nyx running on port 8080")
    var s = newServer("", 8080)
    waitFor(s.serve(handleClient))
