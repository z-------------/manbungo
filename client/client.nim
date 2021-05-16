import jswebsockets
import dom
import tables
import strformat

import ../common/command

type
  AcceptKind = enum
    akSpecific
    akAny
  Accept = object
    case kind: AcceptKind
    of akSpecific:
      ck: CommandKind
    of akAny: discard
  StateObj = object
    accept: Accept
    handler: (proc (cmd: Command): void)
    handlers: Table[CommandKind, (proc (cmd: Command): void)]
  State = ref StateObj

func acceptAny(s: State): bool =
  s.accept.kind == akAny

func newState(): State =
  State(
    accept: Accept(kind: akAny),
    handlers: initTable[CommandKind, (proc (cmd: Command): void)]()
  )

func newAccept(ck: CommandKind): Accept =
  result.kind = akSpecific
  result.ck = ck

func newAccept(): Accept =
  result.kind = akAny

# procs #

proc send(sock: WebSocket; cmd: Command) =
  send(sock, cmd.toJson())

proc getCommand(evtData: cstring): Command =
  ($evtData).fromJson()

proc createCommandElem(cmd: Command): Element =
  var el = document.createElement("div")
  case cmd.kind
    of ckMessage:
      el.textContent = &"{cmd.data2}: {cmd.data}"
    of ckJoinRoom:
      el.textContent = &"{cmd.data2} joined the room."
    of ckLeaveRoom:
      el.textContent = &"{cmd.data2} left the room."
    else:
      raise newException(ValueError, &"Unexpected command kind {cmd.kind}.")
  el

# globals #

var
  state = newState()
  wsUrl = "ws://" & $window.location.hostname & ":9001/ws"
  sock = newWebSocket(wsUrl)
  isOpened = false

let
  userForm = document.getElementById("form")
  usernameInput = document.getElementById("form-username")
  roomnameInput = document.getElementById("form-roomname")
  formSubmitBtn = document.getElementById("form-submit")
  chatLogContainer = document.getElementById("chat-log")
  chatMsgForm = document.getElementById("chat-msgform")
  chatMsgbox = document.getElementById("chat-msgbox")

# sock handlers #

sock.onOpen = proc (e: Event) =
  isOpened = true
  formSubmitBtn.disabled = false

sock.onClose = proc (e: CloseEvent) =
  echo "close. reason: '", e.reason, "'"
  if not isOpened:
    window.alert "WebSocket closed without opening."

sock.addEventListener("message") do (e: MessageEvent):
  let cmd = getCommand(e.data)
  echo "received: ", cmd
  case cmd.kind
  of ckError, ckInvalid:
    window.alert($cmd)
  else:
    if state.acceptAny:
      state.handler(cmd)
    elif cmd.kind != state.accept.ck:
      window.alert("Unexpected command kind: " & $cmd.kind)
    else:
      if not state.handlers.hasKey(cmd.kind):
        echo &"No handler for command kind {cmd.kind}."
      else:
        state.handlers[cmd.kind](cmd)

# command handlers #

state.handlers[ckHello] = proc (cmd: Command) =
  state.accept = newAccept(ckJoinRoom)
  sock.send(newCommand(ckJoinRoom, $roomnameInput.value))

state.handlers[ckJoinRoom] = proc (cmd: Command) =
  state.accept = newAccept()
  chatMsgbox.disabled = false

state.handler = proc (cmd: Command) =
  echo "handler get: ", cmd
  try:
    let msgEl = createCommandElem(cmd)
    chatLogContainer.appendChild(msgEl)
  except ValueError:
    echo "error"
    discard

# dom handlers #

userForm.onsubmit = proc (e: Event) =
  e.preventDefault()

chatMsgForm.onsubmit = proc (e: Event) =
  e.preventDefault()
  let cmd = newCommand(ckMessage, $chatMsgbox.value)
  sock.send(cmd)
  chatMsgbox.value = ""

formSubmitBtn.addEventListener("click") do (e: Event):
  state.accept = newAccept(ckHello)
  sock.send(newCommand(ckHello, $usernameInput.value))
