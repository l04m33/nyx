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


proc handleRequest(client: Client, req: HttpReq): Future[int] {.async.} =
    when not defined(nolog):
        var cid = client.id()

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
        return 500

    when not defined(nolog):
        debug("cid = $#, status = $#" % [$cid, $status])

    return status


proc handleClient(client: Client): Future[Client] {.async.} =
    while not client.isClosed():
        var req = await newHttpReq(client.reader)

        if not isNil(req.meth):
            discard (await handleRequest(client, req))

            var connectionHeader = req.getHeader("Connection")
            if connectionHeader.len() <= 0 or connectionHeader[0].toUpper() == "KEEP-ALIVE":
                continue
            else:
                client.close()
        else:
            client.close()

    return client


when isMainModule:
    setLogLevel(lvlDebug)

    debug("Nyx running on port 8080")
    var s = newServer("", 8080)
    waitFor(s.serve(handleClient))
