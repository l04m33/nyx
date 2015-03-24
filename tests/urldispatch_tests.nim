import
    asyncdispatch,
    os,
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


proc doTests*() =
    testDefaultDispatch()
    testStaticDispatch()


when isMainModule:
    doTests()
