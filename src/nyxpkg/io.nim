import
    asyncnet,
    asyncdispatch,
    sequtils,
    strutils,
    nyxpkg/logging


type
    TReader* = object of RootObj
        readLineImpl: proc(r: Reader): Future[string]
        readImpl: proc(r: Reader, size: int): Future[string]
        putImpl: proc(r: Reader, data: string)

    Reader* = ref TReader


proc read*(r: Reader, size: int): Future[string] {.async.} =
    return (await r.readImpl(r, size))


proc readLine*(r: Reader): Future[string] {.async.} =
    return (await r.readLineImpl(r))


proc put*(r: Reader, data:string) =
    r.putImpl(r, data)


type
    TWriter* = object of RootObj
        writeImpl: proc(w: Writer, buf: string): Future[void]

    Writer* = ref TWriter


proc write*(w: Writer, buf: string): Future[void] {.async.} =
    await w.writeImpl(w, buf)


type
    TAsyncSocketReader* = object of TReader
        socket*: AsyncSocket
        buffer*: seq[string]

    AsyncSocketReader* = ref TAsyncSocketReader


proc asRead*(r: Reader, size: int): Future[string] {.async.} =
    var sr = AsyncSocketReader(r)

    if sr.buffer.len() > 0:
        var need = size
        var lastIdx = 0
        result = ""
        for idx, b in pairs(sr.buffer):
            if b.len() <= need:
                result.add(b)
                need -= b.len()
                if need <= 0:
                    lastIdx = idx + 1
            else:
                if need > 0:
                    sr.buffer[idx] = b[need..(b.len()-1)]
                    result.add(b[0..(need-1)])
                    need = 0
                lastIdx = idx
                break

        if need <= 0:
            if lastIdx > 0:
                sr.buffer.delete(0, lastIdx-1)
        else:
            sr.buffer = @[]
            var moreData = await sr.socket.recv(need)
            result.add(moreData)
    else:
        result = await sr.socket.recv(size)


proc asReadLine*(r: Reader): Future[string] {.async.} =
    var sr = AsyncSocketReader(r)

    if sr.buffer.len() > 0:
        var nb = sr.buffer.join()

        var nlIdx = nb.find("\r\L")
        if nlIdx >= 0:
            result = nb[0..(nlIdx-1)]
            if result == "":
                result = "\r\L"
            var remaining = nb[(nlIdx+2)..(nb.len()-1)]
            if remaining.len() > 0:
                sr.buffer = @[remaining]
            else:
                sr.buffer = @[]
        else:
            var moreData = await sr.socket.recvLine()
            if moreData.len() <= 0:
                result = ""
            elif moreData == "\r\L":
                result = nb
            else:
                result = nb & moreData
            sr.buffer = @[]
    else:
        result = await sr.socket.recvLine()


proc asPut*(r: Reader, data: string) =
    var sr = AsyncSocketReader(r)
    if data.len() > 0:
        sr.buffer.insert([data], 0)


proc newAsyncSocketReader*(socket: AsyncSocket): AsyncSocketReader =
    new(result)
    result.socket = socket
    result.buffer = @[]
    result.readImpl = asRead
    result.readLineImpl = asReadLine
    result.putImpl = asPut


type
    TAsyncSocketWriter* = object of TWriter
        socket*: AsyncSocket

    AsyncSocketWriter* = ref TAsyncSocketWriter


proc asWrite*(w: Writer, buf: string): Future[void] {.async.} =
    var sw = AsyncSocketWriter(w)
    await sw.socket.send(buf, flags={})


proc newAsyncSocketWriter*(socket: AsyncSocket): AsyncSocketWriter =
    new(result)
    result.socket = socket
    result.writeImpl = asWrite


type
    TLengthReader* = object of TReader
        reader*: Reader
        remaining*: int

    LengthReader* = ref TLengthReader


proc lRead*(r: Reader, size: int): Future[string] {.async.} =
    var lr = LengthReader(r)
    if lr.remaining <= 0:
        return ""

    result = await lr.reader.read(min(size, lr.remaining))
    lr.remaining -= (result.len())


proc lReadLine*(r: Reader): Future[string] {.async.} =
    var lr = LengthReader(r)
    if lr.remaining <= 0:
        return ""

    result = await lr.reader.readLine()
    if result.len() > 0:
        var realLen = result.len()
        var postfix = ""
        if result != "\r\L":
            realLen = realLen + "\r\L".len()
            postfix = "\r\L"

        if realLen <= lr.remaining:
            lr.remaining -= realLen
        else:
            result = result & postfix
            lr.reader.put(result[(lr.remaining)..(result.len()-1)])
            result = result[0..(lr.remaining)]


proc lPut*(r: Reader, data: string) =
    var lr = LengthReader(r)
    lr.remaining += data.len()
    lr.reader.put(data)


proc newLengthReader*(reader: Reader, length: int): LengthReader =
    new(result)
    result.reader = reader
    result.remaining = length
    result.readImpl = lRead
    result.readLineImpl = lReadLine
    result.putImpl = lPut


type
    TBoundaryReader* = object of TReader
        reader*: Reader
        boundary*: string
        hitBoundary*: bool

    BoundaryReader* = ref TBoundaryReader


proc bRead*(r: Reader, size: int): Future[string] {.async.} =
    var br = BoundaryReader(r)

    if br.hitBoundary:
        result = ""
    else:
        if size < br.boundary.len() * 2:
            result = await br.reader.read(size + br.boundary.len())
        else:
            result = await br.reader.read(size)

        #debug("bRead: result = '$#'" % [result])
        var boundaryIdx = result.find(br.boundary)
        if boundaryIdx >= 0:
            br.hitBoundary = true

            var padded: string
            # result.len() is ALWAYS larger than 4, since br.boundary.len() > 4
            if (boundaryIdx + br.boundary.len()) > (result.len() - 4):
                var padding = await br.reader.read(4)
                padded = result & padding
            else:
                padded = result

            #debug("bRead: padded = '$#'" % [padded])

            var paddingIdx = padded.find("--\r\L", result.len() - 4)
            #debug("bRead: paddingIdx = $#" % [$paddingIdx])
            if paddingIdx >= 0:
                br.reader.put(padded[(paddingIdx + 4)..(padded.len() - 1)])
            else:
                br.reader.put(padded[(boundaryIdx + br.boundary.len())..(padded.len() - 1)])
            result = result[0..(boundaryIdx-1)]
        else:
            if result.len() > size:
                br.reader.put(result[size..(result.len()-1)])
                result = result[0..(size-1)]


proc newBoundaryReader*(reader: Reader, boundary: string): BoundaryReader =
    new(result)
    result.reader = reader
    result.boundary = "\r\L--" & boundary
    result.hitBoundary = false
    result.readImpl = bRead
