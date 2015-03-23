import
    asyncdispatch,
    strutils,
    tables,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/httpmethods,
    nyxpkg/io,
    nyxpkg/logging


proc handleHttpRequest(client: Client, req: HttpReq): Future[int] {.async.} =
    when not defined(nolog):
        var cid = client.id()

    var status: int
    try:
        status = await methodHandlers[req.meth.toUpper()](client, req)
    except:
        status = -1
        client.closeResources()

        var msg = getCurrentExceptionMsg()
        debug("method handler failed, msg = $#" % [msg])

        var
            exc = getCurrentException()
            trace = exc.getStackTrace()
        if not isNil(trace) and trace != "":
            debug(exc.getStackTrace())

    if status < 0:
        status = 500
        var resp = newHttpResp(500)
        resp.headers.add((key: "Content-Length", value: "0"))
        await client.writer.write($resp)
        return 500

    when not defined(nolog):
        debug("cid = $#, status = $#" % [$cid, $status])

    return status


proc handleHttpClient*(client: Client): Future[Client] {.async, procvar.} =
    while not client.isClosed():
        var req = await newHttpReq(client.reader)

        if not isNil(req.meth):
            discard (await handleHttpRequest(client, req))

            var connVal = req.getFirstHeader("Connection")
            if isNil(connVal) or connVal.toUpper() == "KEEP-ALIVE":
                continue
            else:
                client.close()
        else:
            client.close()

    return client
