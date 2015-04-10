import
    asyncdispatch,
    strutils,
    tables,
    nyxpkg/server,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/httphandlers,
    nyxpkg/urldispatch,
    nyxpkg/io,
    nyxpkg/logging


type
    TDynResource = object of TUrlResource
        op: string
        recvId: int
        recvName: string

    DynResource = ref TDynResource

    TTransEntry = object of RootObj
        name: string
        contentType: string
        contentLength: int
        tag: string
        reader: Reader
        done: Future[void]

    TransEntry = ref TTransEntry


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


proc showErrorPage(code: int, c: Client): Future[void] {.async.} =
    var resp = newHttpResp(code)
    var pageContent = pageError(code)
    resp.headers.add((key: "Content-Length", value: $(pageContent.len())))
    resp.headers.add((key: "Content-Type", value: "text/html"))
    await c.writer.write($resp)
    await c.writer.write(pageContent)


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


proc dynResourceHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    var d = DynResource(res)

    debug("dynResourceHandler: d.op = $#" % [d.op])

    var resp: HttpResp

    case d.op
        of "/":
            if req.meth != "GET":
                await showErrorPage(400, c)
                return

            resp = newHttpResp(200)
            var pageContent = pageList(shelf)
            resp.headers.add((key: "Content-Length", value: $(pageContent.len())))
            resp.headers.add((key: "Content-Type", value: "text/html"))
            await c.writer.write($resp)
            await c.writer.write(pageContent)

        of "/send":
            if req.meth != "POST":
                await showErrorPage(400, c)
                return

            var contentType = req.getFirstHeader("Content-Type")
            var boundary = parseBoundary(contentType)
            if isNil(boundary) or boundary.len() == 0:
                await showErrorPage(400, c)
                return

            debug("send: boundary = '$#'" % [boundary])

            var contentLengthStr = req.getFirstHeader("Content-Length")
            if isNil(contentLengthStr):
                await showErrorPage(400, c)
                return

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
                await showErrorPage(400, c)
                return

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

                await waitForTransfer(c, t)
                data = await reader.readLine()
                debug("send: data = '$#'" % [data])

            await c.writer.write("Done.")

        of "/recv":
            if req.meth != "GET":
                await showErrorPage(400, c)
                return

            if isNil(req.query):
                await showErrorPage(400, c)
                return

            var entryIdxStr = parseQuery(req.query).getFirstValue("e")
            if isNil(entryIdxStr):
                await showErrorPage(400, c)
                return

            var entryIdx: int = -1
            try:
                entryIdx = parseInt(entryIdxStr)
            except ValueError:
                discard

            if entryIdx < 0:
                await showErrorPage(400, c)
                return

            debug("recv: entryIdx = $#" % [$entryIdx])

            if not shelf.hasKey(entryIdx):
                await showErrorPage(404, c)
                return

            resp = newHttpResp(303)
            resp.headers.add((key: "Location", value: "r/$#/$#" % [$entryIdx, UrlEscape(shelf[entryIdx].name)]))
            await showErrorPage(resp, c)

        of "/r":
            if req.meth != "GET":
                await showErrorPage(400, c)
                return

            var entryIdx = d.recvId

            debug("recv: entryIdx = $#" % [$entryIdx])

            if not shelf.hasKey(entryIdx):
                await showErrorPage(404, c)
                return

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
                await c.writer.write(fileContent)
                fileContent = await transfer.reader.read(8192)

            transfer.done.complete()
            debug("recv: entryIdx = $#, transfer completed, totalLen = $#, content-length = $#" % [$entryIdx, $totalLen, $(transfer.contentLength)])
            if totalLen < transfer.contentLength:
                # The transfer was canceled on the sender side, we tell the receiver then.
                c.close()

        else:
            await showErrorPage(500, c)


proc dynamicRootFactory(): UrlResource =
    var root: DynResource
    new(root)
    root.handler = dynResourceHandler
    root.op = "/"
    root.recvId = -1
    root.recvName = nil
    return root


method `[]`(res: DynResource, subRes: string): UrlResource =
    if res.op == "/":
        case subRes
            of "send":
                res.op = "/send"
                return res
            of "recv":
                res.op = "/recv"
                return res
            of "list":
                res.op = "/list"    # TODO
                return res
            of "r":
                res.op = "/r"
                return res
            else:
                raise newException(PathNotFoundError, "$#" % [subRes])

    elif res.op == "/r":
        if res.recvId < 0:
            try:
                res.recvId = parseInt(subRes)
            except ValueError:
                raise newException(PathNotFoundError, "$#" % [subRes])
        elif isNil(res.recvName):
            res.recvName = UrlUnescape(subRes)
        else:
            raise newException(PathNotFoundError, "$#" % [subRes])

        return res

    else:
        raise newException(PathNotFoundError, "$#" % [subRes])


when isMainModule:
    setLogLevel(lvlDebug)

    debug("Nyx running on port 8080")
    var s = newServer("", 8080)

    proc handler(c: Client): Future[Client] {.async.} =
        return (await handleHttpClient(c, dynamicRootFactory))

    waitFor(s.serve(handler))
