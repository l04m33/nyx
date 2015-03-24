import
    asyncdispatch,
    os,
    strutils,
    nyxpkg/urldispatch,
    nyxpkg/client,
    nyxpkg/http,
    testutils


proc getEmptyHttpReq(): HttpReq =
    new(result)


proc testDefaultDispatch() =
    var r = newUrlResource()

    var excFlag = false
    try:
        discard r.dispatch("/some/path")
    except PathNotFoundError:
        excFlag = true

    check(excFlag == true)

    var req = getEmptyHttpReq()
    req.path = "/some/path"
    var client: Client
    new(client)
    excFlag = false
    try:
        waitFor(r.handle(client, req))
    except PathNotFoundError:
        excFlag = true

    check(excFlag == true)


proc testStaticDispatch() =
    var excFlag = false
    var root: UrlResource

    try:
        root = newStaticRoot("doesNotExist.dir")
    except PathNotFoundError:
        excFlag = true

    check(excFlag == true)

    root = newStaticRoot(".")
    var res = root.dispatch("")
    check(StaticUrlResource(res).root == ".")
    check(StaticUrlResource(res).path == "")

    root = newStaticRoot(".")
    res = root.dispatch("/")
    check(StaticUrlResource(res).path == "")

    root = newStaticRoot(".")
    res = root.dispatch("/some/path")
    check(StaticUrlResource(res).path == "some/path")

    root = newStaticRoot(".")
    res = root.dispatch("some/other/path")
    check(StaticUrlResource(res).path == "some/other/path")


type
    DynResource = ref object of TUrlResource


proc dynResourceHandler(res: UrlResource, c: Client, req: HttpReq): Future[void] {.async.} =
    discard


proc dynamicRootFactory(): UrlResource =
    var root: DynResource
    new(root)
    root.handler = dynResourceHandler

    return root


method `[]`(res: DynResource, subRes: string): UrlResource =
    case subRes
        of "hello":
            return res
        of "static":
            return newStaticRoot(".")
        else:
            raise newException(PathNotFoundError, "$#" % [subRes])


proc testDynamicDispatch() =
    var res = dynamicRootFactory()
    check(res.dispatch("") == res)
    check(res.dispatch("/") == res)
    check(res.dispatch("/hello") == res)

    var excFlag = false
    try:
        discard res.dispatch("/does/not/exist")
    except PathNotFoundError:
        excFlag = true

    check(excFlag == true)

    var sRes = res.dispatch("/static")
    check(StaticUrlResource(sRes).root == ".")
    check(StaticUrlResource(sRes).path == "")

    sRes = res.dispatch("/static/")
    check(StaticUrlResource(sRes).path == "")

    sRes = res.dispatch("/static/some/path")
    check(StaticUrlResource(sRes).path == "some/path")


proc doTests*() =
    testDefaultDispatch()
    testStaticDispatch()
    testDynamicDispatch()


when isMainModule:
    doTests()
