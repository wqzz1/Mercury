-- Example game feature: the Mercury library itself remains UI-only.
local Mercury = loadstring(game:HttpGet("https://raw.githubusercontent.com/wqzz1/Mercury/main/Mercury.lua"))()
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local window = Mercury:CreateWindow({
    Name = "HighlightESPExample",
    Footer = "made by ego",
    MinimizeKey = Enum.KeyCode.RightShift,
})

local esp = window:CreateTab("ESP", "eye")
local section = esp:CreateSection("Highlight ESP")
local enabled = section:CreateToggle({Name = "Enable Highlight ESP", Flag = "HighlightESP", CurrentValue = false})
local includeLocal = section:CreateToggle({Name = "Include local player", Flag = "IncludeLocalPlayer", CurrentValue = false})
local outline = section:CreateColorPicker({
    Name = "Outline color",
    Flag = "ESPOutlineColor",
    CurrentValue = Color3.fromRGB(255, 255, 255),
    CurrentTransparency = 0,
})
local fill = section:CreateColorPicker({
    Name = "Fill color",
    Flag = "ESPFillColor",
    CurrentValue = Color3.fromRGB(160, 120, 240),
    CurrentTransparency = 0.5,
})

local highlights = {}
local characterConnections = {}

local function removeHighlight(player)
    local highlight = highlights[player]
    if highlight then highlight:Destroy(); highlights[player] = nil end
end

local function syncPlayer(player)
    local character = player.Character
    if not enabled.Value or (player == LocalPlayer and not includeLocal.Value) or not character then
        removeHighlight(player)
        return
    end

    local highlight = highlights[player]
    if highlight and highlight.Adornee ~= character then
        removeHighlight(player)
        highlight = nil
    end
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "MercuryHighlightESP"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = character
        highlight.Parent = character
        highlights[player] = highlight
    end
    highlight.OutlineColor = outline.Value
    highlight.OutlineTransparency = outline.Transparency
    highlight.FillColor = fill.Value
    highlight.FillTransparency = fill.Transparency
end

local function syncAll()
    for _, player in Players:GetPlayers() do syncPlayer(player) end
end

local function watchPlayer(player)
    characterConnections[player] = player.CharacterAdded:Connect(function()
        task.defer(syncPlayer, player)
    end)
    syncPlayer(player)
end

for _, player in Players:GetPlayers() do watchPlayer(player) end
local playerAdded = Players.PlayerAdded:Connect(watchPlayer)
local playerRemoving = Players.PlayerRemoving:Connect(function(player)
    removeHighlight(player)
    local connection = characterConnections[player]
    if connection then connection:Disconnect(); characterConnections[player] = nil end
end)

enabled:OnChanged(syncAll)
includeLocal:OnChanged(syncAll)
outline:OnChanged(syncAll)
fill:OnChanged(syncAll)

window.ScreenGui.Destroying:Connect(function()
    playerAdded:Disconnect()
    playerRemoving:Disconnect()
    for player, connection in characterConnections do
        connection:Disconnect()
        removeHighlight(player)
    end
end)

return window
