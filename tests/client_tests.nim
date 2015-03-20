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

    check(c.openFiles.len() == 0)

    let cc = waitFor(c.future)
    check(cc == c)
    check(flag == true)

    c.close()
    check(c.openFiles.len() == 0)
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
    check(c.openFiles.len() == 1)
    check(c.openFiles[0] == f)

    f.close()
    check(c.openFiles.len() == 0)

    removeFile("testOpenFile.dummy")


proc doTests*() =
    testNewClient()
    testOpenFile()


when isMainModule:
    doTests()
