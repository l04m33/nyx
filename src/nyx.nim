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

    if isNil(req.meth):
        when not defined(nolog):
            var cid = client.id()
            debug("cid = $#, failed to parse request method" % [$cid])
        return client

    var status: int
    try:
        status = await methodHandlers[req.meth.toUpper()](client, req)
    except:
        status = -1
        client.closeOpenFiles()
        var msg = getCurrentExceptionMsg()
        debug("method handler failed, msg = $#" % [msg])

    if status < 0:
        status = 500
        var resp = newHttpResp(500)
        await client.writer.write($resp)

    when not defined(nolog):
        var cid = client.id()
        debug("cid = $#, status = $#" % [$cid, $status])

    return client


when isMainModule:
    setLogLevel(lvlDebug)

    debug("Nyx running on port 8080")
    var s = newServer("", 8080)
    waitFor(s.serve(handleClient))
