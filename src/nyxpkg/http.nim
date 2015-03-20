import
    asyncnet,
    asyncdispatch,
    strutils,
    sequtils,
    tables,
    nyxpkg/io,
    nyxpkg/logging


type
    HttpHeader* = tuple[key: string, value: string]

    HttpVersion* = tuple[major: int, minor: int]


type
    THttpBase* = object of RootObj
        headers*: seq[HttpHeader]

    HttpBase* = ref THttpBase


method getHeader*(r: HttpBase, key: string): seq[string] =
    result = @[]
    if not isNil(r.headers):
        let upperKey = key.toUpper()
        for h in items(r.headers):
            if h.key.toUpper() == upperKey:
                result.add(h.value)


method getFirstHeader*(r: HttpBase, key: string): string =
    if not isNil(r.headers):
        let upperKey = key.toUpper()
        for h in items(r.headers):
            if h.key.toUpper() == upperKey:
                return h.value
    return nil


method writeHeaders*(r: HttpBase): seq[string] =
    result = @[]
    for h in items(r.headers):
        result.add("$#: $#" % [h.key, h.value])


type
    THttpReq* = object of THttpBase
        meth*: string
        path*: string
        query*: string
        protocol*: string
        version*: HttpVersion

    HttpReq* = ref THttpReq


proc parseRequestLine*(reqLine: string, req: var HttpReq) =
    var reqSeq = reqLine.split(' ')

    if reqSeq.len() != 3:
        return

    req.meth = reqSeq[0]

    var pathAndQuery = reqSeq[1].split('?')
    req.path = pathAndQuery[0]
    if pathAndQuery.len() == 2:
        req.query = pathAndQuery[1]

    var protocolAndVersion = reqSeq[2].split('/')
    req.protocol = protocolAndVersion[0]
    if protocolAndVersion.len() != 2:
        return

    var pVersion = protocolAndVersion[1].split('.')
    var minorVersion: int
    if pVersion.len() > 1:
        minorVersion = pVersion[1].parseInt()
    else:
        minorVersion = 0
    req.version = (major: pVersion[0].parseInt(), minor: minorVersion)


proc parseHeader*(headerLine: string, headers: var seq[HttpHeader]) =
    var firstCol = headerLine.find(':')
    if firstCol < 1:
        debug("bad header line: \"$#\"" % [headerLine])
        return

    var key = headerLine[0..(firstCol-1)].strip()
    if key == "":
        debug("bad header line: \"$#\"" % [headerLine])
        return

    var value = headerLine[(firstCol+1)..(headerLine.len())].strip()
    headers.add((key: key, value: value))


proc newHttpReq*(r: Reader): Future[HttpReq] {.async.} =
    new(result)

    when not defined(nolog):
        var fd = $ord(AsyncSocketReader(r).socket.getFd())

    var reqLine = await r.readLine()
    reqLine = reqLine.strip()

    when not defined(nolog):
        debug("fd = $#, reqLine = \"$#\"" % [fd, reqLine])

    parseRequestLine(reqLine, result)
    if isNil(result.meth) or isNil(result.path):
        result.meth = nil
        return

    var headers: seq[HttpHeader] = @[]
    var headerLine = await r.readLine()
    # TODO: Limit the number of header lines
    while headerLine.len() > 0 and headerLine != "\r\L":
        when not defined(nolog):
            debug("fd = $#, headerLine = \"$#\"" % [fd, headerLine])

        parseHeader(headerLine, headers)
        headerLine = await r.readLine()

    result.headers = headers


type
    THttpResp* = object of THttpBase
        protocol*: string
        version*: HttpVersion
        status*: int

    HttpResp* = ref THttpResp


proc newHttpResp*(status: int): HttpResp =
    new(result)
    result.protocol = "HTTP"
    result.version = (major: 1, minor: 1)
    result.status = status
    result.headers = @[
        (key: "Server", value: "Nyx 0.1.0")
    ]


proc getStatusCode*(status: int): string =
    case status
        of 200:
            return "OK"
        of 400:
            return "Bad Request"
        of 404:
            return "Not Found"
        of 500:
            return "Internal Error"
        of 501:
            return "Not Implemented"
        else:
            return nil


proc write*(r: HttpResp): seq[string] =
    result = @[]
    result.add("$#/$#.$# $# $#" %
            [r.protocol, $r.version.major, $r.version.minor,
             $r.status, getStatusCode(r.status)])
    result = concat(result, r.writeHeaders(), @["\r\L"])

proc `$`*(r: HttpResp): string =
    return r.write().join("\r\L")
