import
    asyncdispatch,
    strutils,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/urldispatch,
    nyxpkg/io,
    nyxpkg/logging


proc handleHttpRequest(client: Client, req: HttpReq, rootFactory: (proc(): UrlResource)): Future[void] {.async.} =
    when not defined(nolog):
        var cid = client.id()

    var dstRes: UrlResource = nil
    try:
        var res = rootFactory()
        dstRes = res.dispatch(req.path)
    except PathNotFoundError:
        discard

    if isNil(dstRes):
        when not defined(nolog):
            debug("cid = $#, status = $#" % [$cid, $404])

        var resp = newHttpResp(404)
        resp.headers.add((key: "Content-Length", value: "0"))
        await client.writer.write($resp)
        return

    var excFlag = false
    try:
        await dstRes.handle(client, req)
    except:
        client.closeResources()

        var msg = getCurrentExceptionMsg()
        debug("method handler failed, msg = $#" % [msg])

        var
            exc = getCurrentException()
            trace = exc.getStackTrace()
        if not isNil(trace) and trace != "":
            debug(exc.getStackTrace())

        excFlag = true

    if excFlag:
        when not defined(nolog):
            debug("cid = $#, status = $#" % [$cid, $500])

        var resp = newHttpResp(500)
        resp.headers.add((key: "Content-Length", value: "0"))
        await client.writer.write($resp)


proc handleHttpClient*(client: Client, rootFactory: (proc(): UrlResource)): Future[Client] {.async, procvar.} =
    while not client.isClosed():
        var req = await newHttpReq(client.reader)

        if not isNil(req.meth):
            await handleHttpRequest(client, req, rootFactory)

            var connVal = req.getFirstHeader("Connection")
            if isNil(connVal) or connVal.toUpper() == "KEEP-ALIVE":
                continue
            else:
                client.close()
        else:
            client.close()

    return client
