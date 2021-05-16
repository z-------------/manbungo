import strformat

# Package

version       = "0.1.0"
author        = "Zack Guard"
description   = "A new awesome nimble package"
license       = "MIT"
srcDir        = "."
bin           = @["client"]
backend       = "js"


# Dependencies

requires "nim >= 1.4.2"
requires "jswebsockets >= 0.1.3"
