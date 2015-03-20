import
    nyxpkg/http,
    testutils


proc getDummyHttpBase(): HttpBase =
    new(result)
    result.headers = @[
        (key: "Server", value: "nyx"),
        (key: "Cookie", value: "a"),
        (key: "Cookie", value: "b")
    ]


proc getEmptyHttpReq(): HttpReq =
    new(result)


proc testGetHeader() =
    let base = getDummyHttpBase()
    check(base.getHeader("server") == @["nyx"])
    check(base.getHeader("SERVER") == @["nyx"])

    check(base.getHeader("pragma") == @[])

    check(base.getHeader("cookie") == @["a", "b"])
    check(base.getFirstHeader("cookie") == "a")
    check(isNil(base.getFirstHeader("pragma")))


proc testWriteHeaders() =
    var base = getDummyHttpBase()
    check(base.writeHeaders() == @["Server: nyx", "Cookie: a", "Cookie: b"])

    base.headers = @[]
    check(base.writeHeaders() == @[])


proc testParseRequestLine() =
    var req = getEmptyHttpReq()
    parseRequestLine("POST / HTTP/1.1", req)
    check(req.meth == "POST")
    check(req.path == "/")
    check(isNil(req.query))
    check(req.protocol == "HTTP")
    check(req.version == (major: 1, minor: 1))

    parseRequestLine("GET /some/path?some=query&some_other=query HTTP/1.1", req)
    check(req.meth == "GET")
    check(req.path == "/some/path")
    check(req.query == "some=query&some_other=query")

    req = getEmptyHttpReq()
    parseRequestLine("", req)
    check(isNil(req.meth))


proc testParseHeader() =
    var headers: seq[HttpHeader] = @[]
    parseHeader("Server: nyx", headers)
    check(headers == @[(key: "Server", value: "nyx")])

    headers = @[]
    parseHeader("Server", headers)
    check(headers == @[])

    headers = @[]
    parseHeader("Server:", headers)
    check(headers == @[(key: "Server", value: "")])

    headers = @[]
    parseHeader("Server: ", headers)
    check(headers == @[(key: "Server", value: "")])

    headers = @[]
    parseHeader(": nyx", headers)
    check(headers == @[])

    headers = @[]
    parseHeader(" : nyx", headers)
    check(headers == @[])


proc testWriteHttpResp() =
    var resp = newHttpResp(200)
    resp.headers = @[
        (key: "Server", value: "nyx"),
        (key: "Connection", value: "keep-alive")
    ]

    check(resp.write() == @["HTTP/1.1 200 OK", "Server: nyx", "Connection: keep-alive", "\r\L"])
    check($resp == "HTTP/1.1 200 OK\r\LServer: nyx\r\LConnection: keep-alive\r\L\r\L")


proc doTests*() =
    testGetHeader()
    testWriteHeaders()
    testParseRequestLine()
    testParseHeader()
    testWriteHttpResp()


when isMainModule:
    doTests()
