import
    asyncnet,
    asyncdispatch,
    rawsockets,
    strutils,
    nyxpkg/io,
    testutils


proc getDummyListener(): AsyncSocket =
    result = newAsyncSocket()

    result.setSockOpt(OptReuseAddr, true)
    result.bindAddr(port=Port(7357), address="127.0.0.1")
    result.listen(backlog=SOMAXCONN)


proc testReaderPutAndRead() =
    var s = newAsyncSocket()
    var r = Reader(newAsyncSocketReader(s))

    r.put("dummy data")
    check(AsyncSocketReader(r).buffer == @["dummy data"])
    r.put("dummy data 2")
    check(AsyncSocketReader(r).buffer == @["dummy data 2", "dummy data"])

    var data = waitFor(r.read(5))
    check(data == "dummy")
    check(AsyncSocketReader(r).buffer == @[" data 2", "dummy data"])

    data = waitFor(r.read(7))
    check(data == " data 2")
    check(AsyncSocketReader(r).buffer == @["dummy data"])

    r.put("data 3")
    check(AsyncSocketReader(r).buffer == @["data 3", "dummy data"])

    data = waitFor(r.read(7))
    check(data == "data 3d")
    check(AsyncSocketReader(r).buffer == @["ummy data"])

    data = waitFor(r.read(9))
    check(data == "ummy data")
    check(AsyncSocketReader(r).buffer == @[])

    r.put("a")
    r.put("b")
    check(AsyncSocketReader(r).buffer == @["b", "a"])
    data = waitFor(r.read(2))
    check(data == "ba")
    check(AsyncSocketReader(r).buffer == @[])


proc testReaderPutAndReadLine() =
    var s = newAsyncSocket()
    var r = Reader(newAsyncSocketReader(s))

    r.put("dummy data")
    r.put("dummy\r\Ldata 2")
    check(AsyncSocketReader(r).buffer == @["dummy\r\Ldata 2", "dummy data"])

    var data = waitFor(r.readLine())
    check(data == "dummy")
    check(AsyncSocketReader(r).buffer == @["data 2dummy data"])

    r = Reader(newAsyncSocketReader(s))
    r.put("dummy data")
    r.put("dummy data 2\r\L")
    data = waitFor(r.readLine())
    check(data == "dummy data 2")
    check(AsyncSocketReader(r).buffer == @["dummy data"])

    r = Reader(newAsyncSocketReader(s))
    r.put("dummy\r\Ldata")
    r.put("dummy data 2")
    data = waitFor(r.readLine())
    check(data == "dummy data 2dummy")
    check(AsyncSocketReader(r).buffer == @["data"])

    r = Reader(newAsyncSocketReader(s))
    r.put("dummy data\r\L")
    r.put("dummy data 2")
    data = waitFor(r.readLine())
    check(data == "dummy data 2dummy data")
    check(AsyncSocketReader(r).buffer == @[])


proc testLengthReader() =
    var s = newAsyncSocket()

    var r = Reader(newLengthReader(newAsyncSocketReader(s), 0))
    r.put("dummy data 1")
    var data = waitFor(r.read(9))
    check(data == "dummy dat")
    data = waitFor(r.read(4))
    check(data == "a 1")
    data = waitFor(r.read(1))
    check(data == "")

    r = Reader(newLengthReader(newAsyncSocketReader(s), -6))    # XXX
    r.put("dummy data 1")
    r.put("dummy data 2")
    data = waitFor(r.read(13))
    check(data == "dummy data 2d")
    data = waitFor(r.read(13))
    check(data == "ummy ")
    data = waitFor(r.read(13))
    check(data == "")

    r = Reader(newLengthReader(newAsyncSocketReader(s), -6))    # XXX
    r.put("dummy data 1")
    r.put("dummy data 2")
    data = waitFor(r.read(18))
    check(data == "dummy data 2dummy ")
    data = waitFor(r.read(1))
    check(data == "")

    r = Reader(newLengthReader(newAsyncSocketReader(s), -6))    # XXX
    r.put("dummy data 1")
    r.put("dummy data 2")
    data = waitFor(r.read(19))
    check(data == "dummy data 2dummy ")
    data = waitFor(r.read(1))
    check(data == "")


proc testAsyncSocketReader() =
    var ls = getDummyListener()

    var s = newAsyncSocket()
    waitFor(s.connect("127.0.0.1", Port(7357)))
    var ps = waitFor(ls.accept())

    var r = Reader(newAsyncSocketReader(s))

    waitFor(ps.send("abcd\r\L\r\L1234"))
    var data = waitFor(r.readLine())
    check(data == "abcd")

    data = waitFor(r.readLine())
    check(data == "\r\L")

    data = waitFor(r.read(4))
    check(data == "1234")

    ps.close()
    data = waitFor(r.read(4))
    check(data == "")

    r.put("321")
    data = waitFor(r.read(4))
    check(data == "321")

    s.close()
    ls.close()


proc testLengthReader2() =
    var ls = getDummyListener()

    var s = newAsyncSocket()
    waitFor(s.connect("127.0.0.1", Port(7357)))
    var ps = waitFor(ls.accept())

    var r = Reader(newLengthReader(newAsyncSocketReader(s), 10))
    waitFor(ps.send("abcd\r\L\r\L1234"))
    var data = waitFor(r.read(11))
    check(data == "abcd\r\L\r\L12")

    discard waitFor(s.recv(2))

    r = Reader(newLengthReader(newAsyncSocketReader(s), 10))
    waitFor(ps.send("abcd\r\L\r\L1234"))
    data = waitFor(r.readLine())
    check(data == "abcd")
    data = waitFor(r.readLine())
    check(data == "\r\L")

    ps.close()
    data = waitFor(r.readLine())
    check(data == "")

    s.close()
    ls.close()


proc testBoundaryReader2() =
    var ls = getDummyListener()

    var s = newAsyncSocket()
    waitFor(s.connect("127.0.0.1", Port(7357)))
    var ps = waitFor(ls.accept())

    var boundary = "--thisisboundary"
    var payload = "abcd\r\L\r\L1234\r\L--" & boundary & "--\r\L"
    var lr = newLengthReader(newAsyncSocketReader(s), payload.len())
    var r = Reader(newBoundaryReader(lr, boundary))
    waitFor(ps.send(payload))

    var data = waitFor(r.read(8))
    check(data == "abcd\r\L\r\L")

    data = waitFor(r.read(8))
    check(data == "1234")

    data = waitFor(r.read(8))
    check(data == "")

    data = waitFor(lr.read(8))
    check(data == "")

    payload = "abcd1234"
    lr = newLengthReader(newAsyncSocketReader(s), payload.len())
    r = Reader(newBoundaryReader(lr, boundary))
    waitFor(ps.send(payload))

    ps.close()
    data = waitFor(r.read(9))
    check(data == "abcd1234")
    data = waitFor(r.read(9))
    check(data == "")

    s.close()
    ls.close()

proc testBoundaryReader() =
    var s = newAsyncSocket()
    var boundary = "--thisisboundary"

    var rr = Reader(newAsyncSocketReader(s))
    var r = Reader(newBoundaryReader(rr, boundary))
    rr.put("\r\L--" & boundary & "--padding")
    rr.put("dummy data 1")
    var data = waitFor(r.read(13))
    check(data == "dummy data 1")

    rr = Reader(newAsyncSocketReader(s))
    r = Reader(newBoundaryReader(rr, boundary))
    rr.put("dummy data 2\r\L--" & boundary & "--\r\Lpadding")
    rr.put("dummy data 1")
    data = waitFor(r.read(18))
    check(data == "dummy data 1dummy ")
    data = waitFor(r.read(8))
    check(data == "data 2")

    data = waitFor(rr.read(7))
    check(data == "padding")


proc doTests*() =
    testReaderPutAndRead()
    testReaderPutAndReadLine()
    testLengthReader()
    testAsyncSocketReader()
    testLengthReader2()
    testBoundaryReader()
    testBoundaryReader2()


when isMainModule:
    doTests()
