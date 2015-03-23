import
    asyncnet,
    asyncdispatch,
    tables,
    rawsockets,
    strutils,
    nyxpkg/client,
    nyxpkg/logging


type
    TServer = object of RootObj
        listener*: AsyncSocket
        clients*: TableRef[int, Client]
        alive*: bool

    Server* = ref TServer


proc newServer*(socket: AsyncSocket): Server =
    new(result)
    result.listener = socket
    result.clients = newTable[int, Client]()
    result.alive = false


proc newServer*(address: string, port: uint16): Server =
    var serverSocket = newAsyncSocket(
            domain=rawsockets.AF_INET,
            typ=rawsockets.SOCK_STREAM,
            protocol=rawsockets.IPPROTO_TCP,
            buffered=true)
    serverSocket.setSockOpt(OptReuseAddr, true)
    serverSocket.bindAddr(port=Port(port), address=address)
    serverSocket.listen(backlog=SOMAXCONN)

    result = newServer(serverSocket)


proc purgeClient*(server: Server, clientId: int) =
    debug("removing cid = $#" % [$clientId])

    var client = server.clients[clientId]
    server.clients.del(clientId)

    debug("new client number: $#" % [$(server.clients.len())])
    debug("closing cid = $#, resources.len() = $#" % [$clientId, $client.resources.len()])

    client.close()


proc accept(server: Server): Future[AsyncSocket] {.async.} =
    return (await server.listener.accept())


proc serve*(server: Server, handler: ClientHandler) {.async.} =
    # TODO: the `alive` flag here won't work when this proc is
    #       suspended by server.accept()
    server.alive = true
    while server.alive:
        var clientSocket = await server.accept()

        var client = newClient(clientSocket, handler)
        var cid = client.id()
        server.clients[cid] = client
        debug("serve: new client: $#" % [$cid])

        client.future.callback =
            proc(f: Future[Client]) =
                if f.failed():
                    if not isNil(f.errorStackTrace) and f.errorStackTrace != "":
                        debug("$#" % [f.errorStackTrace])
                    for fd, c in pairs(server.clients):
                        if c.future == f:
                            server.purgeClient(fd)
                            break
                else:
                    var c = f.read()
                    server.purgeClient(c.id())
