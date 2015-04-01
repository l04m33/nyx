import
    asyncnet,
    asyncdispatch,
    strutils,
    nyxpkg/io,
    testutils


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
    testBoundaryReader()


when isMainModule:
    doTests()
