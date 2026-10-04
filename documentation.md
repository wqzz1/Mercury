# Mercury documentation

Mercury is a single-file Roblox Luau UI library. It provides the liquid glass window, tabs, sections, controls, notifications, a minimized bubble, and monochrome icons. Your script owns its feature logic; the library calls the functions you give it.

## Contents

- [Requirements and setup](#requirements-and-setup)
- [Your first script](#your-first-script)
- [Windows and tabs](#windows-and-tabs)
- [Controls](#controls)
- [Control objects and callbacks](#control-objects-and-callbacks)
- [Icons](#icons)
- [Notifications and lifecycle](#notifications-and-lifecycle)
- [Connecting your own features](#connecting-your-own-features)
- [Source and rebuilding](#source-and-rebuilding)

## Requirements and setup

The library runs on the Roblox **client**. It was tested with Potassium, where `loadstring` and `game:HttpGet` are available. Its liquid renderer uses Roblox `EditableImage`; embedded PNG assets use executor custom-asset functions when available. It does not save settings or run any game feature on its own.

1. Load the published library in your script:

   ```lua
   local Mercury = loadstring(game:HttpGet("https://raw.githubusercontent.com/wqzz1/Mercury/main/Mercury.lua"))()
   ```

2. Create a window and add tabs and controls. Loading the file alone does not display a window.

   ```lua
   local window = Mercury:CreateWindow()
   local main = window:CreateTab("Main", "home")
   ```

The examples below use `Mercury` for the returned library table.

**Keep your feature script separate from the library source.** The loader line above returns Mercury's library table; it does not create a global variable. See [MyScriptExample.lua](./MyScriptExample.lua) for a complete feature script.

## Your first script

The example below adds your feature logic to Mercury. The Settings tab already exists and is reserved for UI settings. The header shows the current game's name.

```lua
local Mercury = loadstring(game:HttpGet("https://raw.githubusercontent.com/wqzz1/Mercury/main/Mercury.lua"))()

local window = Mercury:CreateWindow({
    Name = "MyScriptUI",
    Footer = "made by ego",
    MinimizeKey = Enum.KeyCode.RightShift,
})

local main = window:CreateTab("Main", "home")
local feature = main:CreateSection("Feature")

local featureToggle = feature:CreateToggle({
    Name = "Enable feature",
    Flag = "featureEnabled",
    CurrentValue = false,
})

featureToggle:OnChanged(function(enabled)
    featureToggle:SetSubtitle(if enabled then "Feature is on" else nil)
end)

local amountSlider = feature:CreateSlider({
    Name = "Amount",
    Flag = "featureAmount",
    Min = 0,
    Max = 100,
    Increment = 1,
    CurrentValue = 25,
})

feature:CreateButton({
    Name = "Run once",
    Icon = "sparkles",
    Callback = function()
        window:Notify({
            Title = "Run once",
            Content = string.format("Enabled: %s · Amount: %d", tostring(featureToggle.Value), amountSlider.Value),
            Duration = 2.4,
        })
    end,
})

return window
```

Mercury stores each control's current value in its `.Value` property. The notification reads the toggle and slider directly; your feature code can do the same.

## Windows and tabs

Create a window with `Mercury:CreateWindow(options)`. Each call returns a separate window object. Only one window stays open at a time: creating a new one closes the window that is already open (with the same animation as its close button), so re-running your script replaces the old UI instead of stacking a second copy. Pass `AllowMultiple = true` to keep existing windows open.

| Window option | Type | Purpose |
| --- | --- | --- |
| `Name` | `string` | `ScreenGui` name. Default: `Mercury`. |
| `Parent` | `Instance` | GUI parent. Default: local player's `PlayerGui`. |
| `Footer` | `string` | Text at the bottom left. Default: `made by ego`. |
| `FooterButtonText` | `string` or `false` | Bottom-right button label. Default: `Biolink`. Set to `false` to hide it. |
| `FooterButtonUrl` | `string` | Link opened and copied by the default Biolink action. Default: `https://alo.ne/egowho`. |
| `FooterButtonCallback` | `function` | Replaces the default Biolink action when the footer button is pressed. |
| `MinimizeKey` | `Enum.KeyCode` | Keyboard shortcut. Default: `RightShift`. |
| `MinimizedIcon` | image ID or path | Optional image in the minimized bubble. Omit for the animated logo. |
| `Performance` | `string` | `"Smooth"`, `"Balanced"`, or `"Low"`. Default: `"Smooth"`. |

The window opens centered at its default size. It can be dragged and resized; its minimized bubble can be moved. No position, size, or control value is persisted between runs.

Create tabs with `window:CreateTab(name, iconName)` or `window:AddTab(name, iconName)`. Tab names must be nonempty and unique within a window. A built-in `Settings` tab is always last; access it through `window.SettingsTab`. Calling `CreateTab("Settings")` returns that tab. The icon name is optional. Tabs have the existing sliding page transition.

```lua
local main = window:CreateTab("Main", "home")
local extras = window:CreateTab("Extras", "sparkles")

window:SelectTab("Extras") -- returns true when the tab exists
main:Select()
```

Add controls directly to a tab, or group them inside a section. Sections use the same control methods as tabs.

```lua
main:CreateButton({Name = "A tab-level button", Callback = function() end})

local section = main:CreateSection("Actions")
section:CreateButton({Name = "A section button", Callback = function() end})
```

Click a section's title to collapse or expand its controls. Pass `{Collapsed = true}` as the second argument to start collapsed (`main:CreateSection("Actions", {Collapsed = true})`), call `section:SetCollapsed(true/false)` or `section:Toggle()` from code, and read `section.Collapsed` for the current state.

`tab:AddSection(title)` is an alias for `tab:CreateSection(title)`. Each control also has an `Add...` alias: for example, `section:AddToggle(...)` equals `section:CreateToggle(...)`.

## Controls

Pass an options table to controls unless a string form is shown below. `Name` is the visible control title. `Flag` stores the returned control object in `window.Flags[flag]` and must be unique within that window. A control's `Callback` runs when its value changes; buttons run their callback when pressed.

### Button

```lua
local button = main:CreateButton({
    Name = "Run",
    Icon = "sparkles", -- use a name from the supported list below
    Flag = "runButton",
    Callback = function()
        -- Your action.
    end,
})

button:SetText("Run again")
button:Fire() -- invokes its callback unless disabled
```

`CreateButton("Run")` also works when no options are needed. Supported icon names are listed in [Icons](#icons).

### Toggle

```lua
local toggle = main:CreateToggle({
    Name = "Enabled",
    Flag = "enabled",
    CurrentValue = false,
    Callback = function(value)
        -- value is a boolean
    end,
})

toggle:Set(true)
toggle:Set(false, true) -- set without dispatching callbacks
toggle:SetSubtitle("Waiting for input")
toggle:SetSubtitle(nil) -- remove subtitle
```

`toggle:Set(value, silent, instant)` takes an optional third argument to update the switch without a tween.

### Slider

```lua
local slider = main:CreateSlider({
    Name = "Speed",
    Flag = "speed",
    Min = 0,
    Max = 10,
    Increment = 0.5,
    CurrentValue = 2,
    Suffix = "x",
    Callback = function(value)
        -- value is a number, clamped and rounded to Increment
    end,
})

slider:Set(3.5)
```

`Range = {min, max}` can be used in place of `Min` and `Max`. The default range is 0–100 and the default increment is 1.

### Dropdown

```lua
local dropdown = main:CreateDropdown({
    Name = "Mode",
    Options = {"A", "B", "C"},
    CurrentValue = "A",
    Callback = function(value)
        -- value is the selected option
    end,
})

dropdown:Set("B")
dropdown:Refresh({"B", "D"})
```

`Set` requires a value present in `Options`. `Refresh` replaces the visible choices; set a new value afterwards if the previous one is no longer present.

### Text input

```lua
local input = main:CreateInput({
    Name = "Search",
    PlaceholderText = "Type a name",
    CurrentValue = "",
    OnlyEnter = true,
    Callback = function(text)
        -- text is a string
    end,
})

input:Set("example")
```

With `OnlyEnter = true`, the text box dispatches when Enter is pressed. Otherwise it dispatches when focus leaves the box.

### Keybind

```lua
local keybind = main:CreateKeybind({
    Name = "Open key",
    CurrentKeybind = Enum.KeyCode.K,
    Callback = function(key)
        -- called when the bound key changes
    end,
    OnTriggered = function()
        -- called when the bound key is pressed
    end,
})

keybind:Set(Enum.KeyCode.L)
```

Click the keybind control, then press a key to rebind it. `Callback` reports a binding change; `OnTriggered` handles the bound key being pressed while game input has not already processed it.

### Color picker

```lua
local color = main:CreateColorPicker({
    Name = "Tint",
    CurrentValue = Color3.fromRGB(255, 255, 255),
    CurrentTransparency = 0.25,
    Callback = function(value, transparency)
        -- value is a Color3; transparency is a number from 0 to 1
    end,
})

color:Set(Color3.fromRGB(160, 120, 240))
color:SetTransparency(0.5)
```

Click the control to expand the picker. Drag in the shade square to set saturation and value, use **HUE** to choose a color, **BRIGHTNESS** to blend it toward white or black, and **TRANSPARENCY** to choose a value from 0 (opaque) to 1 (invisible). The header shows the current hex color. Enter a six-digit hex value in the **HEX** field (or a three-digit shorthand and leave the field). `Set` changes the `Color3` without changing transparency. Read `color.Transparency` or call `color:SetTransparency(value)`. `Callback` and `OnChanged` receive the `Color3` and transparency whenever either value changes. Double-click the **BRIGHTNESS** track to snap back to the pure color. Pass `Open = true` to start expanded, or call `color:SetOpen(true/false)` / `color:Toggle()`; `color.Open` tells you the current state.

### Labels, paragraphs, and dividers

```lua
local label = main:CreateLabel({Text = "Ready"})
label:Set("Running")

local paragraph = main:CreateParagraph({Title = "Help", Content = "Longer explanatory text."})
paragraph:Set("Updated text")
paragraph:SetTitle("Updated heading")

main:CreateDivider()
```

`CreateLabel("Ready")` also works. Labels, paragraphs, and dividers display information and do not dispatch value callbacks.

## Control objects and callbacks

Interactive controls return an object with `Value`, `Instance`, `Type`, `Visible`, and `Disabled`. They support the following methods:

| Method | Result |
| --- | --- |
| `:Set(value)` | Updates the value and dispatches callbacks for value controls. |
| `:OnChanged(function(value) ... end)` | Adds another value-change listener and returns the control. |
| `:SetVisible(boolean)` | Shows or hides the control. |
| `:SetDisabled(boolean)` | Blocks interaction. This does not visually dim the control. |
| `:SetAttribute(name, value)` / `:GetAttribute(name)` | Stores and reads a custom attribute. |
| `:Destroy()` | Removes the control and its own listeners. |

Value controls accept `:Set(value, true)` to update without dispatching callbacks. Initial `CurrentValue` settings do not invoke callbacks. `OnChanged` adds a listener; it does not call that listener immediately. To run feature setup for a default value, call your setup function explicitly.

```lua
local toggle = main:CreateToggle({Name = "Enabled", Flag = "enabled"})

toggle:OnChanged(function(value)
    print("Changed to", value)
end)

toggle:Set(true)
assert(window.Flags.enabled == toggle)
```

The library runs user callbacks inside `pcall`. An error produces a warning and leaves the UI running. Handle feature errors inside your own code if you need custom recovery or status messages.

Flags, custom attributes, and UI values live only for the current run. `window.Flags` is an object lookup table, not a save file.

## Icons

This bundle includes a small white icon set. Pass a name to `CreateTab(name, iconName)` or use `Icon = iconName` in a button. Icons render from atlas images at UI size; an unknown name simply shows no icon.

`activity`, `bell`, `check`, `chevron-down`, `chevron-up`, `circle-help`, `copy`, `download`, `eye`, `globe`, `heart`, `home`, `info`, `menu`, `minus`, `plus`, `search`, `settings`, `sliders-horizontal`, `sparkles`, `x`.

For the minimized bubble, `MinimizedIcon` is separate from the tab/button icon set. It accepts a Roblox asset ID or supported executor asset path. Omit it to keep the animated default logo.

Icon names come from [Lucide](https://lucide.dev/icons/) and the bundled atlas metadata comes from [Rayfield's icon atlas](https://github.com/SiriusSoftwareLtd/Rayfield/blob/main/icons.lua). License texts are in [LICENSES](./LICENSES).

## Notifications and lifecycle

```lua
window:Notify({Title = "Saved", Content = "Your changes are ready", Duration = 3})

-- optional status badge on the right: "Success" (check) or "Error" (x)
window:Notify({Title = "Saved", Content = "Your changes are ready", Type = "Success"})
window:Notify({Title = "Failed", Content = "Could not save", Type = "Error"})

window:Minimize()
window:Unminimize()
window:SetTitle("New title")
window:SetFooter("version 1.0")

window:Close()   -- plays the close animation, then cleans up
-- window:Destroy() -- immediate cleanup, without the close animation
```

`window.Unload` is an alias for `window.Destroy`. `window.ScreenGui` exposes the created `ScreenGui`; `window.Tabs` is the ordered tab array; `window.Icons` exposes bundled icon metadata. Windows and tabs also support `:SetAttribute(name, value)` and `:GetAttribute(name)`.

Destroy a window when your script is finished or before replacing it. Do not keep calling its controls after `Close` or `Destroy`.

## Connecting your own features

Keep the feature functions in your script, and give the UI callbacks that call those functions. That keeps the reusable library free of game-specific behavior.

```lua
local Feature = {enabled = false}

function Feature:setEnabled(enabled)
    self.enabled = enabled
    -- Start or stop your own feature here.
end

local toggle = main:CreateToggle({
    Name = "Enable feature",
    CurrentValue = Feature.enabled,
    Callback = function(enabled)
        Feature:setEnabled(enabled)
    end,
})

-- If you change the feature from elsewhere, sync its UI without re-running
-- the UI callback:
Feature:setEnabled(true)
toggle:Set(true, true)
```

Use `window.Flags["yourFlag"]` when another part of your script needs an existing control. Use `:OnChanged(...)` when more than one part of your script needs the same value change.

## Source and rebuilding

Editable source is in [src](./src), with a [build script](./build.py). From the repository root, run:

```text
python build.py
```

The generated single-file library appears at `Mercury.lua`. Edit the source sections and rebuild rather than editing the generated file by hand. The renderer, animations, and material are contained in the library. Game feature logic belongs in a separate script.
