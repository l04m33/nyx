import
    asyncdispatch,
    strutils,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/urldispatch,
    nyxpkg/io,
    nyxpkg/logging


type
    RootFactory = proc(): UrlResource

    HttpErrorHandler = proc(e: HttpErrorRef, c: Client, r: HttpReq): Future[void]


include "defaultpages.tmpl"


proc defaultHttpErrorHandler(exc: HttpErrorRef, c: Client, r: HttpReq): Future[void] {.async, procvar.} =
    var resp = newHttpResp(exc.code)
    var pageContent = defaultErrorPage(exc.code)
    resp.headers.add((key: "Content-Length", value: $(pageContent.len())))
    resp.headers.add((key: "Content-Type", value: "text/html"))
    await c.writer.write($resp)
    await c.writer.write(pageContent)


proc handleHttpRequest(client: Client, req: HttpReq, rootFactory: RootFactory, errorHandler: HttpErrorHandler = defaultHttpErrorHandler): Future[void] {.async.} =
    when not defined(nolog):
        var cid = client.id()

    var
        dstRes: UrlResource = nil
        httpExc: HttpErrorRef = nil

    try:
        var res = rootFactory()
        dstRes = res.dispatch(req.path)
    except HttpError:
        httpExc = HttpErrorRef(getCurrentException())

    if not isNil(httpExc):
        when not defined(nolog):
            debug("cid = $#, status = $#" % [$cid, $(httpExc.code)])

        await errorHandler(httpExc, client, req)
        return

    var exc: ref Exception = nil

    try:
        await dstRes.handle(client, req)
    except HttpError:
        exc = getCurrentException()
        httpExc = HttpErrorRef(exc)
    except:
        exc = getCurrentException()

    if not isNil(exc):
        client.closeResources()

        when not defined(nolog):
            if isNil(httpExc):
                debug("cid = $#, status = $#" % [$cid, $500])
            else:
                debug("cid = $#, status = $#" % [$cid, $(httpExc.code)])

        if not isNil(exc.msg) and exc.msg != "":
            debug("exc.msg = `$#`" % [exc.msg])
        var trace = exc.getStackTrace()
        if not isNil(trace) and trace != "":
            debug(trace)

        if isNil(httpExc):
            debug("handleHttpRequest: runtime error, closing client")
            client.close()
        else:
            await errorHandler(httpExc, client, req)


proc handleHttpClient*(client: Client, rootFactory: RootFactory, errorHandler: HttpErrorHandler = defaultHttpErrorHandler): Future[Client] {.async, procvar.} =
    while not client.isClosed():
        var req = await newHttpReq(client.reader)

        if not isNil(req.meth):
            await handleHttpRequest(client, req, rootFactory, errorHandler)

            var connVal = req.getFirstHeader("Connection")
            if isNil(connVal) or connVal.toUpper() == "KEEP-ALIVE":
                continue
            else:
                client.close()
        else:
            client.close()

    return client
