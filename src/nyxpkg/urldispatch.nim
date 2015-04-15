import
    asyncdispatch,
    os,
    strutils,
    nyxpkg/client,
    nyxpkg/http,
    nyxpkg/mime,
    nyxpkg/io,
    nyxpkg/logging


type
    ResourceHandler* = proc(res: UrlResource, c: Client, r: HttpReq): Future[void]

    TUrlResource* = object of RootObj
        handler*: ResourceHandler

    UrlResource* = ref TUrlResource


proc urlResourceHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    if true:
        raise newHttpError(404, "`$#` not found" % [UrlUnescape(req.path)])


proc newUrlResource*(): UrlResource =
    new(result)
    result.handler = urlResourceHandler


method `[]`*(res: UrlResource, subResName: string): UrlResource =
    raise newHttpError(404, "`$#` not found" % [subResName])


proc handle*(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    await res.handler(res, c, req)


proc dispatch*(root: UrlResource, path: string): UrlResource =
    var segs = path.split('/')

    result = root
    for s in segs:
        if s.len() > 0:
            debug("Dispatching to resource `$#`" % [s])
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
        raise newHttpError(404, "'$#' not found" % [path])


proc newStaticRoot*(localPath: string): UrlResource =
    if existsDir(localPath):
        var sRoot: StaticUrlResource
        new(sRoot)
        sRoot.handler = staticUrlResourceHandler
        sRoot.root = localPath
        sRoot.path = ""
        return sRoot
    else:
        raise newHttpError(404, "`$#` not found" % [localPath])


method `[]`*(sRes: StaticUrlResource, subResName: string): UrlResource =
    sRes.path = joinPath(sRes.path, subResName)
    return sRes
