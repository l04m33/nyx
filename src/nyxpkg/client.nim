import
    asyncnet,
    asyncdispatch,
    nyxpkg/io


type
    TClient* = object of RootObj
        socket: AsyncSocket
        future*: Future[Client]
        reader*: Reader
        writer*: Writer

    Client* = ref TClient

    ClientHandler* = proc(c: Client): Future[Client]


proc newClient*(socket: AsyncSocket, handler: ClientHandler): Client =
    new(result)
    result.socket = socket
    result.reader = Reader(newAsyncSocketReader(socket))
    result.writer = Writer(newAsyncSocketWriter(socket))
    result.future = handler(result)


proc id*(c: Client): int =
    return ord(c.socket.getFd())


proc close*(c: Client) =
    c.socket.close()
