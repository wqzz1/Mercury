-- Example script: add your own feature logic below the Mercury loader.
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
