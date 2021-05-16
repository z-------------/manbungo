import json
import strutils

type
  CommandKind* = enum
    ckInvalid
    ckError
    ckHello
    ckJoinRoom
    ckLeaveRoom
    ckMessage
  Command* = object
    kind*: CommandKind
    data*: string  # The main data of the Command
    data2*: string # Any secondary data
    flag*: bool    # Any additional flag data

func newCommand*(kind: CommandKind; data: string; data2 = ""; flag = false): Command =
  Command(
    kind: kind,
    data: data,
    data2: data2,
    flag: flag)

func toJson*(cmd: Command): string =
  var jNode = newJObject()
  jNode["kind"] = %cmd.kind
  jNode["data"] = %cmd.data
  jNode["data2"] = %cmd.data2
  jNode["flag"] = %cmd.flag
  $jNode

proc fromJson*(cmdSer: string): Command =
  ## Deserializes a Command from JSON.
  ## Does not raise on invalid data.
  let node = parseJson(cmdSer)

  if node.contains("kind"):
    try:
      result.kind = parseEnum[CommandKind](node["kind"].getStr)
    except ValueError:
      result.kind = ckInvalid
      
  if node.contains("data"):
    result.data = node["data"].getStr
  
  if node.contains("data2"):
    result.data2 = node["data2"].getStr
  
  if node.contains("flag"):
    result.flag = node["flag"].getBool
