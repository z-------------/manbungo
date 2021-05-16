import ws
import asyncdispatch
import asynchttpserver
import tables
import sequtils
import strutils
import sugar

import ../common/command

const WsUrlPath = "/ws"

# types #

type
  RoomObj = object
    name: string
    users: seq[User]
  Room = ref RoomObj
  User = object
    name: string
    sock: WebSocket

# globals #

var
  rooms {.threadvar.}: Table[string, Room]  # Marked as threadvar to stop async from complaining about GC safeness. If we actually multithread this thing, we would probably get rid of global `rooms` and make each thread correspond to one room, thus each having a thread-local `room: Room`.
  # users = initTable[string, User]()

# procs #

proc send(sock: WebSocket; cmd: Command): Future[void] {.async.} =
  echo "send: ", cmd
  await send(sock, cmd.toJson())

proc send(room: Room; cmd: Command): Future[void] {.async.} =
  ## Send a Command to all users in room.
  await all(room.users.map(user => user.sock.send(cmd)))

# proc send(room: Room; cmd: Command; exceptUser: User): Future[void] {.async.} =
#   ## Send a Command to all users in room except `exceptUser`.
#   var futs: seq[Future[void]]
#   for user in room.users:
#     if user == exceptUser: continue
#     futs.add(user.sock.send(cmd))
#   await all(futs)

proc removeUser(room: Room; user: User): Future[void] {.async.} =
  ## Remove a user from the room and send leave command to remaining users
  room.users.del(room.users.find(user))
  let cmd = newCommand(ckLeaveRoom, room.name, user.name)
  await all(room.users.map(remainingUser => remainingUser.sock.send(cmd)))

proc receiveCommand(sock: WebSocket): Future[Command] {.async.} =
  let cmd = (await sock.receiveStrPacket()).fromJson()
  echo "received: ", cmd
  return cmd

proc receiveCommand(sock: WebSocket; requiredKind: CommandKind): Future[Command] {.async.} =
  ## Read a Command. If the received CommandKind is different from that specified, close the socket.
  let cmd = await receiveCommand(sock)
  if cmd.kind != requiredKind:
    sock.close()
  else:
    return cmd

proc handleReq(req: Request) {.async, gcsafe.} =
  var
    sock = await newWebSocket(req)
    cmd: Command

  cmd = await sock.receiveCommand(ckHello)
  if cmd.data.contains('\t'):
    sock.close()
    return
  let user = User(name: cmd.data, sock: sock)
  await sock.send(newCommand(ckHello, user.name))

  cmd = await sock.receiveCommand(ckJoinRoom)
  let roomName = cmd.data
  var roomFlag = false
  if rooms.hasKey(roomName):
    rooms[roomName].users.add(user)
  else:  # new room
    rooms[roomName] = Room(name: roomName, users: @[user])
    roomFlag = true
  var room = rooms[roomName]
  await room.send(newCommand(ckJoinRoom, roomName, data2 = user.name))  # includes the current user
  await user.sock.send(newCommand(ckUserList, roomName, room.users.map(user => user.name).join("\t")))

  try:
    while sock.readyState == ReadyState.Open:
      cmd = await sock.receiveCommand()
      if cmd.kind != ckMessage:
        await sock.send(newCommand(ckError, "Unexpected command kind " & $cmd.kind & "."))
        continue
      await room.send(newCommand(ckMessage, cmd.data, data2 = user.name))
  except WebSocketError:
    echo "socket closed."
    await room.removeUser(user)

when isMainModule:
  echo "Starting..."

  var server = newAsyncHttpServer()
  waitFor server.serve(Port(9001)) do (req: Request) {.async.}:
    if req.url.path != WsUrlPath:
      await req.respond(HttpCode(404), "Not found")
    else:
      try:
        await handleReq(req)
      except WebSocketError:
        echo "web socket error in outer loop"
