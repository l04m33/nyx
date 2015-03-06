import
    asyncnet,
    asyncfile,
    asyncdispatch,
    os,
    strutils,
    tables,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/io,
    nyxpkg/mime,
    nyxpkg/logging


proc normalizePath(path: string): string =
    if path[0] == '/':
        result = path[1..(path.len())]
    else:
        result = path

    if result == "" or result[result.len() - 1] == '/':
        result = result & "index.html"


proc doGet(c: Client, r: HttpReq): Future[int] {.async.} =
    var path = normalizePath(r.path)
    var resp: HttpResp

    if existsFile(path):
        var fileSize = getFileSize(path)
        var f =
            try:
                openAsync(path)
            except:
                nil

        if isNil(f):
            resp = newHttpResp(500)
            await c.writer.write($resp)
            return 500

        resp = newHttpResp(200)
        resp.headers.add((key: "Content-Length", value: $fileSize))
        var mimetype = getMimetype(path)
        if mimetype.len() > 0:
            resp.headers.add((key: "Content-Type", value: mimetype))

        var fileBlock: string

        try:
            await c.writer.write($resp)
            fileBlock = await f.read(8192)
        except:
            debug("IO error: $#" % [getCurrentExceptionMsg()])
            f.close()
            raise

        while fileBlock != "":
            try:
                await c.writer.write(fileBlock)
                fileBlock = await f.read(8192)
            except:
                debug("IO error: $#" % [getCurrentExceptionMsg()])
                f.close()
                raise
        f.close()
        return 200
    else:
        resp = newHttpResp(404)
        await c.writer.write($resp)
        return 404


proc doNotImplemented(c: Client, r: HttpReq): Future[int] {.async.} =
    var resp = newHttpResp(501)
    await c.writer.write($resp)
    return 501


type
    MethodHandler* = proc(c: Client, r: HttpReq): Future[int]


var methodHandlers* = newTable[string, MethodHandler]()
methodHandlers["GET"]       = doGet
methodHandlers["POST"]      = doNotImplemented
methodHandlers["PUT"]       = doNotImplemented
methodHandlers["DELETE"]    = doNotImplemented
methodHandlers["OPTIONS"]   = doNotImplemented
methodHandlers["HEAD"]      = doNotImplemented
methodHandlers["TRACE"]     = doNotImplemented
methodHandlers["CONNECT"]   = doNotImplemented