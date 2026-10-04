local toastToken = 0
local function sweepToastGlint(token: number)
    toastGlintGradient.Offset = Vector2.new(-1.4, 0)
    task.delay(0.2, function()
        if token ~= toastToken or not toast.Parent then return end
        tween(toastGlintGradient, 1.1, { Offset = Vector2.new(1.4, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    end)
end
-- With the liquid morph the rendered card IS the notification's body, so the
-- toast frame only carries the text; its own background is for the fallback.
local function setToastChrome(on: boolean)
    for _, child in toast:GetChildren() do
        if child:IsA("UIStroke") then child.Enabled = on
        elseif child:IsA("GuiObject") and not child:IsA("TextLabel") and child ~= toastBadge and child ~= toastGlint then child.Visible = on end
    end
end
local function showToast(title: string, content: string?, duration: number?, kind: string?)
    toastToken += 1
    local token = toastToken
    toastTitle.Text = tostring(title or "")
    toastContent.Text = tostring(content or "")
    setToastStatus(kind)

    local viewportSize = screenGui.AbsoluteSize
    local rightEdge = root.AbsolutePosition.X + root.AbsoluteSize.X + Layout.gap + TOAST_SIZE.X
    local onRight = rightEdge <= viewportSize.X - 6
    local finalX = if onRight then UDim.new(1, Layout.gap) else UDim.new(0, -Layout.gap - TOAST_SIZE.X)
    local startX = UDim.new(finalX.Scale, finalX.Offset + (if onRight then -14 else 14))
    local y = UDim.new(1, -TOAST_SIZE.Y)

    -- Liquid morph: the card grows out of the panel edge as a blob, then the real
    -- notification fades in over it; on the way out it melts back into the panel.
    local morph = Resize.liquidToast
    -- parallel-worker liquid when the executor supports actors; otherwise the plain slide-in
    if morph and morph.ready() and Layout.performance ~= "Low" and not Resize.minimized then
        playFade(toastFade, false, 0)
        toast.Visible = false
        setToastChrome(false)
        toast.Position = UDim2.new(finalX, y)
        morph.open(onRight, function()
            if token ~= toastToken or not toast.Parent then return end
            toast.Visible = true
            playFade(toastFade, true, 0.25)
            sweepToastGlint(token)
            task.delay(duration or 2.4, function()
                if token ~= toastToken or not toast.Parent then return end
                playFade(toastFade, false, 0.2)
                morph.close(onRight, function()
                    if token == toastToken and toast.Parent then toast.Visible = false end
                end)
            end)
        end)
        return
    end

    setToastChrome(true)
    toast.Visible = true
    toast.Position = UDim2.new(startX, y)
    playFade(toastFade, true, 0.25)
    sweepToastGlint(token)
    tween(toast, 0.45, { Position = UDim2.new(finalX, y) }, Enum.EasingStyle.Back)

    task.delay(duration or 2.4, function()
        if token ~= toastToken or not toast.Parent then
            return
        end
        playFade(toastFade, false, 0.25)
        tween(toast, 0.3, { Position = UDim2.new(startX, y) })
        task.delay(0.3, function()
            if token == toastToken and toast.Parent then
                toast.Visible = false
            end
        end)
    end)
end


local panelFadeSkip = { [backdrop] = true, [toast] = true }

local function shutdown()
    if state.destroyed then return end
    state.destroyed = true
    state.closing = true
    runCleanup()
end
local function close()
    if state.closing then
        return
    end
    state.closing = true
    tween(panelScale, 0.22, { Scale = Layout.uiScale * 0.88 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
    tween(backdrop, 0.2, { GroupTransparency = 1 })
    playFade(collectFade(panel, panelFadeSkip), false, 0.2)
    if toast.Visible then
        playFade(toastFade, false, 0.2)
    end
    task.delay(0.24, shutdown)
end
-- CanvasGroups cache a render of their contents and can keep a mid-tween frame
-- once the open fade stops changing things (e.g. filter chips looked unselected
-- until clicked). Nudging each faded value forces one fresh, final render.
local function refreshCanvasRenders(entries: { FadeEntry })
    local nudged = {}
    for _, entry in entries do
        if entry.instance.Parent and entry.instance:FindFirstAncestorWhichIsA("CanvasGroup") then
            local value = (entry.instance :: any)[entry.property]
            local bumped = if value >= 0.999 then value - 0.001 else value + 0.001
            (entry.instance :: any)[entry.property] = bumped
            table.insert(nudged, { entry.instance, entry.property, value, bumped })
        end
    end
    RunService.Heartbeat:Wait()
    for _, item in nudged do
        local instance, property, value, bumped = item[1], item[2], item[3], item[4]
        -- Skip anything a hover/toggle already moved during the nudge frame.
        if instance.Parent and math.abs((instance :: any)[property] - bumped) < 1e-4 then
            (instance :: any)[property] = value
        end
    end
end

local function open()
    local entries = collectFade(panel, panelFadeSkip)
    playFade(entries, true, 0.35)
    tween(backdrop, 0.35, { GroupTransparency = 0 })
    tween(panelScale, 0.5, { Scale = Layout.uiScale }, Enum.EasingStyle.Back)
    task.delay(0.55, refreshCanvasRenders, entries)
end

-- Wiring -----------------------------------------------------------------------
track(closeButton.MouseEnter:Connect(function()
    closeHovered = true
    tween(closeButton, 0.18, { BackgroundColor3 = Theme.danger, BackgroundTransparency = 0.8 })
end))
track(closeButton.MouseLeave:Connect(function()
    closeHovered = false
    tween(closeButton, 0.25, { BackgroundColor3 = Theme.mist, BackgroundTransparency = 0.93 })
end))
track(closeButton.MouseButton1Click:Connect(close))

