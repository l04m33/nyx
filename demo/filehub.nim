import
    asyncdispatch,
    strutils,
    tables,
    json,
    nyxpkg/server,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/httphandlers,
    nyxpkg/urldispatch,
    nyxpkg/io,
    nyxpkg/logging


type
    TRootResource = object of TUrlResource
    RootResource = ref TRootResource

    CmdResource = ref object of TUrlResource
        recvId: int
        recvName: string

    TransEntry = ref object of RootObj
        name: string
        contentType: string
        contentLength: int
        tag: string
        reader: Reader
        done: Future[void]


include "pages.tmpl"


var
    shelf = newTable[int, TransEntry]()


proc newTransEntry(name: string, contentType: string, tag: string, reader: Reader): TransEntry =
    new(result)
    result.name = name
    result.contentType = contentType
    result.contentLength = -1
    result.tag = tag
    result.reader = reader
    result.done = newFuture[void]("filehub.newTransEntry")


proc waitForTransfer(c: Client, t: TransEntry): Future[void] {.async.} =
    var doneFuture = t.done
    shelf[c.id()] = t
    await doneFuture    # XXX: can't say `await t.done` here, why?
    # XXX: Why doesn't the `await` statement raise this exception?
    if doneFuture.failed():
        raise (doneFuture.error)


proc showErrorPage(resp: HttpResp, c: Client): Future[void] {.async.} =
    var pageContent = pageError(resp.status)
    resp.headers.add((key: "Content-Length", value: $(pageContent.len())))
    resp.headers.add((key: "Content-Type", value: "text/html"))
    await c.writer.write($resp)
    await c.writer.write(pageContent)


proc parseBoundary(ct: string): string =
    const ctPrefix = "multipart/form-data;"
    const bdPrefix = "boundary="

    if isNil(ct):
        return nil

    var lowerCT = ct.toLower()
    if not lowerCT.startsWith(ctPrefix):
        return nil

    var bIdx = lowerCT.find(bdPrefix, ctPrefix.len())
    if bIdx < 0:
        return nil

    bIdx += (bdPrefix.len())
    return ct[bIdx..(ct.len()-1)].strip()


proc parseFileInfo(partHeaders: seq[HttpHeader], reader: Reader): TransEntry =
    let disp = partHeaders.getFirstValue("Content-Disposition")
    let ct = partHeaders.getFirstValue("Content-Type")  # may be nil

    if isNil(disp):
        return nil

    var dispList = disp.split(';')
    if dispList.len() < 1:
        return nil

    if dispList[0].strip() != "form-data":
        return nil

    var fieldName: string = nil
    var fileName:string = nil
    for d in items(dispList[1..(dispList.len()-1)]):
        let sd = d.strip()
        if sd.startsWith("name="):
            fieldName = sd[5..(sd.len()-1)]
        elif sd.startsWith("filename="):
            fileName = sd[9..(sd.len()-1)]
            if fileName.len() >= 2 and fileName[0] == '"' and fileName[fileName.len() - 1] == '"':
                fileName = fileName[1..(fileName.len() - 2)]
                if fileName.len() <= 0:
                    fileName = "Anonymous File"

    if isNil(fieldName) or fieldName != "\"userfile\"":
        return nil

    if isNil(fileName):
        fileName = "Anonymous File"

    return newTransEntry(fileName, ct, nil, reader)


proc rootResourceHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    var resp: HttpResp

    if req.meth != "GET":
        raise newHttpError(400, "only GET method is accepted")

    resp = newHttpResp(200)
    var pageContent = pageList(shelf)
    resp.headers.add((key: "Content-Length", value: $(pageContent.len())))
    resp.headers.add((key: "Content-Type", value: "text/html"))
    await c.writer.write($resp)
    await c.writer.write(pageContent)


proc rootFactory(): UrlResource =
    var root: RootResource
    new(root)
    root.handler = rootResourceHandler
    return root


proc cmdSendHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    var resp: HttpResp

    if req.meth != "POST":
        raise newHttpError(400, "only POST method is accepted")

    var contentType = req.getFirstHeader("Content-Type")
    var boundary = parseBoundary(contentType)
    if isNil(boundary) or boundary.len() == 0:
        raise newHttpError(400, "no boundary found for multipart data")

    debug("send: boundary = '$#'" % [boundary])

    var contentLengthStr = req.getFirstHeader("Content-Length")
    if isNil(contentLengthStr):
        raise newHttpError(400, "no CONTENT-LENGTH header")

    var contentLength = parseInt(contentLengthStr)

    debug("send: contentLength = '$#'" % [$contentLength])

    resp = newHttpResp(200)
    resp.headers.add((key: "Content-Length", value: $5))
    resp.headers.add((key: "Content-Type", value: "text/plain"))
    await c.writer.write($resp)

    var reader = Reader(newLengthReader(c.reader, contentLength))

    var data = await reader.readLine()
    debug("send: data = '$#'" % [data])
    if data != ("--" & boundary):
        raise newHttpError(400, "first line is not the boundary")

    data = await reader.readLine()
    debug("send: data = '$#'" % [data])
    while data.len() > 0:
        var partHeaders: seq[HttpHeader] = @[]
        while data != "\r\L" and data.len() > 0:
            parseHeader(data, partHeaders)
            data = await reader.readLine()
            debug("send: data = '$#'" % [data])

        var boundaryReader = Reader(newBoundaryReader(reader, boundary))
        var t = parseFileInfo(partHeaders, boundaryReader)
        if isNil(t):
            break

        var transCL = LengthReader(reader).remaining - (boundary.len() + "--".len() * 2 + "\r\L".len() * 2)
        t.contentLength = transCL

        try:
            await waitForTransfer(c, t)
        except:
            debug("transfer failed, closing sender connection")
            c.close()
            return

        data = await reader.readLine()
        debug("send: data = '$#'" % [data])

    await c.writer.write("Done.")


proc cmdRecvHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    var resp: HttpResp

    if req.meth != "GET":
        raise newHttpError(400, "only GET method is accepted")

    if isNil(req.query):
        raise newHttpError(400, "no query string")

    var entryIdxStr = parseQuery(req.query).getFirstValue("e")
    if isNil(entryIdxStr):
        raise newHttpError(400, "no entry parameter")

    var entryIdx: int = -1
    try:
        entryIdx = parseInt(entryIdxStr)
    except ValueError:
        discard

    if entryIdx < 0:
        raise newHttpError(400, "failed to parse entry idx")

    debug("recv: entryIdx = $#" % [$entryIdx])

    if not shelf.hasKey(entryIdx):
        raise newHttpError(404, "entry not found")

    resp = newHttpResp(303)
    resp.headers.add((key: "Location", value: "r/$#/$#" % [$entryIdx, UrlEscape(shelf[entryIdx].name)]))
    await showErrorPage(resp, c)


proc cmdNamedRecvHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    var resp: HttpResp
    var d = CmdResource(res)

    if req.meth != "GET":
        raise newHttpError(400, "only GET method is accepted")

    var entryIdx = d.recvId

    debug("recv: entryIdx = $#" % [$entryIdx])

    if not shelf.hasKey(entryIdx):
        raise newHttpError(404, "entry not found")

    resp = newHttpResp(200)

    var transfer = shelf[entryIdx]
    shelf.del(entryIdx)

    resp.headers.add((key: "Content-Length", value: $(transfer.contentLength)))
    if not isNil(transfer.contentType):
        resp.headers.add((key: "Content-Type", value: transfer.contentType))
    await c.writer.write($resp)

    var totalLen = 0
    var fileContent = await transfer.reader.read(8192)
    while fileContent.len() > 0:
        totalLen += fileContent.len()

        try:
            await c.writer.write(fileContent)
        except:
            var exc = getCurrentException()
            debug("transfer failed, exc.msg = `$#`" % [exc.msg])
            transfer.done.fail(exc)
            c.close()
            return

        fileContent = await transfer.reader.read(8192)

    transfer.done.complete()
    debug("recv: entryIdx = $#, transfer completed, totalLen = $#, content-length = $#" % [$entryIdx, $totalLen, $(transfer.contentLength)])
    if totalLen < transfer.contentLength:
        # The transfer was canceled on the sender side, we tell the receiver then.
        c.close()


proc cmdListHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    var resp: HttpResp

    if req.meth != "GET":
        raise newHttpError(400, "only GET method is accepted")

    var jsonArray = newJArray()
    for i, t in pairs(shelf):
        var jsonObj = %[
            (key: "id", val: %(i)),
            (key: "name", val: %(t.name)),
            (key: "size", val: %(t.contentLength)),
            #(key: "tag", val: %(t.tag)),   # TODO
            (key: "url", val: %("recv?e=$#" % [$i]))
        ]
        jsonArray.add(jsonObj)

    var retObj = %[(key: "fileList", val: jsonArray)]

    var content = retObj.pretty()
    resp = newHttpResp(200)
    resp.headers.add((key: "Content-Length", value: $(content.len())))
    resp.headers.add((key: "Content-Type", value: "application/json"))
    await c.writer.write($resp)
    await c.writer.write(content)


proc newCmdResource(handler: ResourceHandler): CmdResource =
    new(result)
    result.handler = handler
    result.recvId = -1
    result.recvName = nil


method `[]`(res: RootResource, subRes: string): UrlResource =
    case subRes
        of "send":
            return newCmdResource(cmdSendHandler)
        of "recv":
            return newCmdResource(cmdRecvHandler)
        of "list":
            return newCmdResource(cmdListHandler)
        of "r":
            return newCmdResource(cmdNamedRecvHandler)
        else:
            raise newHttpError(404, "'$#' not found" % [subRes])


method `[]`(res: CmdResource, subRes: string): UrlResource =
    if res.handler == cmdNamedRecvHandler:
        if res.recvId < 0:
            try:
                res.recvId = parseInt(subRes)
            except ValueError:
                raise newHttpError(404, "'$#' not found" % [subRes])
        elif isNil(res.recvName):
            res.recvName = UrlUnescape(subRes)
        else:
            raise newHttpError(404, "'$#' not found" % [subRes])

        return res

    else:
        raise newHttpError(404, "'$#' not found" % [subRes])


when isMainModule:
    setLogLevel(lvlDebug)

    debug("Nyx running on port 8080")
    var s = newServer("", 8080)

    proc handler(c: Client): Future[Client] {.async.} =
        return (await handleHttpClient(c, rootFactory))

    waitFor(s.serve(handler))
