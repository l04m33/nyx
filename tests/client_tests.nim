import
    asyncnet,
    asyncdispatch,
    asyncfile,
    os,
    nyxpkg/client,
    testutils


proc testNewClient() =
    var flag = false
    proc handler(c:Client): Future[Client] {.async.} =
        await sleepAsync(1)
        flag = true
        return c

    let
        s = newAsyncSocket()
        c = newClient(s, handler)

    check(c.resources.len() == 0)

    let cc = waitFor(c.future)
    check(cc == c)
    check(flag == true)

    c.close()
    check(c.resources.len() == 0)
    check(c.isClosed() == true)


proc testOpenFile() =
    proc handler(c:Client): Future[Client] {.async.} =
        await sleepAsync(1)
        return c

    let
        s = newAsyncSocket()
        c = newClient(s, handler)

    var f = c.openFile("testOpenFile.dummy", fmWrite)
    check(f.client == c)
    check(c.resources.len() == 1)
    check(c.resources[0] == ClientResource(f))

    var f2 = c.openFile("testOpenFile2.dummy", fmWrite)
    check(f2.client == c)
    check(c.resources.len() == 2)
    check(c.resources[1] == ClientResource(f2))

    f.close()
    check(c.resources.len() == 1)
    f2.close()
    check(c.resources.len() == 0)

    removeFile("testOpenFile2.dummy")
    removeFile("testOpenFile.dummy")


proc doTests*() =
    testNewClient()
    testOpenFile()


when isMainModule:
    doTests()
