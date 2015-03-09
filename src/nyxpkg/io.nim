import
    asyncnet,
    asyncdispatch


type
    TReader* = object of RootObj
        readLineImpl: proc(r: Reader): Future[string]
        readImpl: proc(r: Reader, size: int): Future[string]

    Reader* = ref TReader


proc read*(r: Reader, size: int): Future[string] {.async.} =
    return (await r.readImpl(r, size))


proc readLine*(r: Reader): Future[string] {.async.} =
    return (await r.readLineImpl(r))


type
    TWriter* = object of RootObj
        writeImpl: proc(w: Writer, buf: string): Future[void]

    Writer* = ref TWriter


proc write*(w: Writer, buf: string): Future[void] {.async.} =
    await w.writeImpl(w, buf)


type
    TAsyncSocketReader* = object of TReader
        socket*: AsyncSocket

    AsyncSocketReader* = ref TAsyncSocketReader


proc asRead*(r: Reader, size: int): Future[string] {.async.} =
    var sr = AsyncSocketReader(r)
    return (await sr.socket.recv(size))


proc asReadLine*(r: Reader): Future[string] {.async.} =
    var sr = AsyncSocketReader(r)
    return (await sr.socket.recvLine())


proc newAsyncSocketReader*(socket: AsyncSocket): AsyncSocketReader =
    new(result)
    result.socket = socket
    result.readImpl = asRead
    result.readLineImpl = asReadLine


type
    TAsyncSocketWriter* = object of TWriter
        socket*: AsyncSocket

    AsyncSocketWriter* = ref TAsyncSocketWriter


proc asWrite*(w: Writer, buf: string): Future[void] {.async.} =
    var sw = AsyncSocketWriter(w)
    await sw.socket.send(buf)


proc newAsyncSocketWriter*(socket: AsyncSocket): AsyncSocketWriter =
    new(result)
    result.socket = socket
    result.writeImpl = asWrite
