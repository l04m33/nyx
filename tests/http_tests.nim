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


proc testParseQuery() =
    check(parseQuery("a=1") == @[(key: "a", value: "1")])
    check(parseQuery("a=1&b=2") == @[(key: "a", value: "1"), (key: "b", value: "2")])
    check(parseQuery("a&b=2") == @[(key: "a", value: ""), (key: "b", value: "2")])
    check(parseQuery("=1&b=2") == @[(key: "b", value: "2")])
    check(parseQuery("b=%E6%B5%8B%E8%AF%95&a=1") == @[(key: "b", value: "测试"), (key: "a", value: "1")])


proc testWriteHttpResp() =
    var resp = newHttpResp(200)
    resp.headers = @[
        (key: "Server", value: "nyx"),
        (key: "Connection", value: "keep-alive")
    ]

    check(resp.write() == @["HTTP/1.1 200 OK", "Server: nyx", "Connection: keep-alive", "\r\L"])
    check($resp == "HTTP/1.1 200 OK\r\LServer: nyx\r\LConnection: keep-alive\r\L\r\L")


proc testUrlUnescape() =
    check(UrlUnescape("%61%62%63") == "abc")
    check(UrlUnescape("/some/path/%E6%B5%8B%E8%AF%95") == "/some/path/测试")
    check(UrlUnescape("%E6%B5%8B%E8%AF%95/content") == "测试/content")
    check(UrlUnescape("/some/path/%E6%B5%8B%E8%AF%95/content") == "/some/path/测试/content")
    check(UrlUnescape("%%%%%%") == "%%%%%%")
    check(UrlUnescape("") == "")


proc doTests*() =
    testGetHeader()
    testWriteHeaders()
    testParseRequestLine()
    testParseHeader()
    testParseQuery()
    testWriteHttpResp()
    testUrlUnescape()


when isMainModule:
    doTests()
