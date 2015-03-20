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
        openFiles*: seq[ClientOpenFile]

    Client* = ref TClient

    ClientHandler* = proc(c: Client): Future[Client]

    TClientOpenFile* = object of RootObj
        client*: Client
        afile: AsyncFile

    ClientOpenFile* = ref TClientOpenFile


proc newClient*(socket: AsyncSocket, handler: ClientHandler): Client =
    new(result)
    result.socket = socket
    result.reader = Reader(newAsyncSocketReader(socket))
    result.writer = Writer(newAsyncSocketWriter(socket))
    result.openFiles = @[]
    result.future = handler(result)


proc id*(c: Client): int =
    return ord(c.socket.getFd())


proc closeOpenFiles*(c: Client) =
    for f in c.openFiles:
        f.afile.close()
    c.openFiles = @[]


proc close*(c: Client) =
    c.closeOpenFiles()
    c.socket.close()


proc isClosed*(c: Client): bool =
    return (c.socket.isClosed())


proc openFile*(c: Client, filename: string, mode: FileMode = fmRead): ClientOpenFile =
    new(result)
    result.client = c
    result.afile = openAsync(filename, mode)
    c.openFiles.add(result)


proc read*(f: ClientOpenFile, size: int): Future[string] {.async.} =
    return (await f.afile.read(size))


proc close*(f: ClientOpenFile) =
    for i, ff in pairs(f.client.openFiles):
        if f == ff:
            f.client.openFiles.del(i)
            break
    f.afile.close()
