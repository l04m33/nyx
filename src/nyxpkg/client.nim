import
    asyncnet,
    asyncfile,
    asyncdispatch,
    nyxpkg/io


type
    TClient* = object of RootObj
        socket: AsyncSocket
        future*: Future[Client]
        reader*: Reader
        writer*: Writer
        resources*: seq[ClientResource]

    Client* = ref TClient

    ClientHandler* = proc(c: Client): Future[Client]

    TClientResource* = object of RootObj
        client*: Client

    ClientResource* = ref TClientResource

    TClientOpenFile* = object of TClientResource
        afile*: AsyncFile

    ClientOpenFile* = ref TClientOpenFile


proc newClient*(socket: AsyncSocket, handler: ClientHandler): Client =
    new(result)
    result.socket = socket
    result.reader = Reader(newAsyncSocketReader(socket))
    result.writer = Writer(newAsyncSocketWriter(socket))
    result.resources = @[]
    result.future = handler(result)


proc id*(c: Client): int =
    return ord(c.socket.getFd())


method close*(f: ClientResource, rm: bool = true) =
    raise newException(Exception, "ClientResource.close() not implemented")


proc closeResources*(c: Client) =
    for f in c.resources:
        f.close(rm=false)
    c.resources = @[]


proc close*(c: Client) =
    c.closeResources()
    c.socket.close()


proc isClosed*(c: Client): bool =
    return (c.socket.isClosed())


method remove(r: ClientResource): bool =
    for i, rr in pairs(r.client.resources):
        if r == rr:
            r.client.resources.del(i)
            return true
    return false


proc openFile*(c: Client, filename: string, mode: FileMode = fmRead): ClientOpenFile =
    new(result)
    result.client = c
    result.afile = openAsync(filename, mode)
    c.resources.add(result)


proc read*(f: ClientOpenFile, size: int): Future[string] {.async.} =
    return (await f.afile.read(size))


method close*(f: ClientOpenFile, rm: bool = true) =
    if rm:
        discard f.remove()
    f.afile.close()
