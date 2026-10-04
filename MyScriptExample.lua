-- Example script: add your own feature logic below the Mercury loader.
local Mercury = loadstring(game:HttpGet("https://raw.githubusercontent.com/wqzz1/Mercury/main/Mercury.lua"))()

local state = {
    enabled = false,
    amount = 25,
}

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
    state.enabled = enabled
    featureToggle:SetSubtitle(if enabled then "Feature is on" else nil)
end)

feature:CreateSlider({
    Name = "Amount",
    Flag = "featureAmount",
    Min = 0,
    Max = 100,
    Increment = 1,
    CurrentValue = state.amount,
    Callback = function(value)
        state.amount = value
    end,
})

feature:CreateButton({
    Name = "Run once",
    Icon = "sparkles",
    Callback = function()
        window:Notify({
            Title = "Run once",
            Content = string.format("Enabled: %s · Amount: %d", tostring(state.enabled), state.amount),
            Duration = 2.4,
        })
    end,
})

return window
