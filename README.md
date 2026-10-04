# alt="Mercury bubble" width="48" height="48"> Mercury

Mercury is a standalone Roblox Luau UI library with a liquid glass window, tabs, controls, notifications, and monochrome icons. It contains UI code only; your script supplies its own game features.

## Quick start

Load the published library in your own client script:

```lua
local Mercury = loadstring(game:HttpGet("https://raw.githubusercontent.com/wqzz1/Mercury/main/Mercury.lua"))()
local window = Mercury:CreateWindow({Footer = "made by ego"})
local main = window:CreateTab("Main", "home")
main:CreateButton({Name = "Run", Callback = function() print("Run") end})
```

The header fetches the current game's title. A Settings tab is built in and reserved for UI settings. See [documentation.md](./documentation.md) for the full API, and [MyScriptExample.lua](./MyScriptExample.lua) for a basic script.

## Source

The editable source is in [src](./src). Run `python build.py` to rebuild the standalone `Mercury.lua`. Icon licensing is in [LICENSES](./LICENSES).
