import
    asyncdispatch,
    os,
    strutils,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/mime,
    nyxpkg/io


type
    PathNotFoundError* = object of Exception


type
    TUrlResource* = object of RootObj
        handler: proc(res: UrlResource, c: Client, r: HttpReq): Future[void]

    UrlResource* = ref TUrlResource


proc urlResourceHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    if true:
        raise newException(PathNotFoundError, "`$#` not found" % [UrlUnescape(req.path)])


proc newUrlResource*(): UrlResource =
    new(result)
    result.handler = urlResourceHandler


method `[]`*(res: UrlResource, subResName: string): UrlResource =
    raise newException(PathNotFoundError, "`$#` not found" % [subResName])


proc handle*(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    await res.handler(res, c, req)


proc dispatch*(root: UrlResource, path: string): UrlResource =
    var segs = path.split('/')

    result = root
    for s in segs:
        result = result[s]


type
    TStaticUrlResource* = object of TUrlResource
        root*: string
        path*: string

    StaticUrlResource* = ref TStaticUrlResource


proc staticUrlResourceHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    var
        sRes = StaticUrlResource(res)
        path = UrlUnescape(joinPath(sRes.root, sRes.path))
        resp: HttpResp

    if existsFile(path):
        var fileSize = getFileSize(path)
        var f = c.openFile(path)

        resp = newHttpResp(200)
        resp.headers.add((key: "Content-Length", value: $fileSize))
        var mimetype = getMimetype(path)
        if mimetype.len() > 0:
            resp.headers.add((key: "Content-Type", value: mimetype))

        var fileBlock: string

        await c.writer.write($resp)
        fileBlock = await f.read(8192)

        while fileBlock != "":
            await c.writer.write(fileBlock)
            fileBlock = await f.read(8192)

        f.close()
    else:
        resp = newHttpResp(404)
        resp.headers.add((key: "Content-Length", value: $0))    # TODO
        await c.writer.write($resp)


proc newStaticRoot*(localPath: string): UrlResource =
    if existsDir(localPath):
        var sRoot: StaticUrlResource
        new(sRoot)
        sRoot.handler = staticUrlResourceHandler
        sRoot.root = localPath
        sRoot.path = ""
        return sRoot
    else:
        raise newException(PathNotFoundError, "`$#` not found" % [localPath])


method `[]`*(sRes: StaticUrlResource, subResName: string): UrlResource =
    sRes.path = joinPath(sRes.path, subResName)
    return sRes
