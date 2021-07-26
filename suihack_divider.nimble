# Package

version       = "0.1.0"
author        = "suihakei"
description   = "WAVファイルの無音部分でカットするソフトウェア"
license       = "suihakei license"
srcDir        = "src"
bin           = @["suihack_divider"]
binDir        = "bin"
installExt    = @["nim"]


# Dependencies

requires "nim >= 1.4.8"
requires "wnim"