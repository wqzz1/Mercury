-- Public controls. Callbacks are guarded and receive only UI values.
local window = {Tabs = tabs, Flags = {}, Icons = LUCIDE, ScreenGui = screenGui}
local function safeCall(callback, ...)
    if typeof(callback) ~= "function" then return end
    local ok, err = pcall(callback, ...)
    if not ok then warn("[Mercury] callback failed: " .. tostring(err)) end
end
local function row(container, name, height)
    local frame = create("Frame", {
        Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height), LayoutOrder = #container:GetChildren(), Parent = container,
    })
    return frame
end
-- Rebuild the visible control grooves when dragging begins. Read screen bounds
-- so nested sections, disclosure wrappers and scroll offsets are all respected.
function Resize.syncBones()
    local tab = tabByName[state.currentTab]
    local used = 0
    local scale = root.AbsoluteSize.X / math.max(1, root.Size.X.Offset)
    if tab then
        for _, item in tab.content:GetDescendants() do
            if not item:GetAttribute("MercuryControl") or not item:IsA("GuiObject") then continue end
            local pos, size = item.AbsolutePosition, item.AbsoluteSize
            local x0, y0 = pos.X + Layout.padX * scale, pos.Y
            local x1, y1 = pos.X + size.X - Layout.padX * scale, pos.Y + size.Y
            local visible = true
            local ancestor = item
            while ancestor and ancestor ~= screenGui do
                if ancestor:IsA("GuiObject") then
                    if not ancestor.Visible or (ancestor:IsA("CanvasGroup") and ancestor.GroupTransparency > 0.98) then visible = false; break end
                    if ancestor.ClipsDescendants or ancestor:IsA("ScrollingFrame") then
                        local p, s = ancestor.AbsolutePosition, ancestor.AbsoluteSize
                        x0, y0 = math.max(x0, p.X), math.max(y0, p.Y)
                        x1, y1 = math.min(x1, p.X + s.X), math.min(y1, p.Y + s.Y)
                    end
                end
                ancestor = ancestor.Parent
            end
            if visible and x1 > x0 and y1 - y0 > 2 then
                used += 1
                local entry = Resize.pageBones[used]
                if not entry then entry = {bone = Resize.addBone(UDim2.new(), UDim2.fromOffset(20, 20)), bottom = 0}; Resize.pageBones[used] = entry end
                entry.bone.Position = UDim2.fromOffset((x0 - root.AbsolutePosition.X) / scale, (y0 - root.AbsolutePosition.Y) / scale)
                entry.bone.Size = UDim2.fromOffset((x1 - x0) / scale, (y1 - y0) / scale)
                entry.bottom = (y1 - root.AbsolutePosition.Y) / scale
                entry.bone.Visible = true
            end
        end
    end
    for index = used + 1, #Resize.pageBones do Resize.pageBones[index].bone.Visible = false end
end
local function controlBase(kind, frame, default, callback, flag)
    frame:SetAttribute("MercuryControl", kind)
    local object = {Type = kind, Instance = frame, Value = default, Disabled = false, Visible = true, Attributes = {}}
    local listeners = {}
    object._listeners = listeners
    object._connections = {}
    function object:Bind(connection)
        table.insert(self._connections, connection)
        track(connection)
        return connection
    end
    function object:SetAttribute(name, value)
        self.Attributes[name] = value
        frame:SetAttribute(name, value)
        return self
    end
    function object:GetAttribute(name) return self.Attributes[name] end
    function object:OnChanged(listener)
        assert(typeof(listener) == "function", "OnChanged needs a function")
        table.insert(listeners, listener)
        return self
    end
    function object:_emit(value, ...)
        safeCall(callback, value, ...)
        for _, listener in listeners do safeCall(listener, value, ...) end
    end
    function object:SetVisible(visible)
        self.Visible = visible == true
        frame.Visible = self.Visible
        return self
    end
    function object:SetDisabled(disabled)
        self.Disabled = disabled == true
        return self
    end
    function object:Destroy()
        if flag then window.Flags[flag] = nil end
        table.clear(listeners)
        for _, connection in self._connections do connection:Disconnect() end
        table.clear(self._connections)
        frame:Destroy()
    end
    if flag then
        assert(typeof(flag) == "string" and flag ~= "", "Flag must be a nonempty string")
        assert(not window.Flags[flag], "Duplicate flag: " .. flag)
        window.Flags[flag] = object
    end
    return object
end
-- Shared liquid disclosure for option lists, picker cards and collapsible sections.
-- A drop hangs from `top` and spreads into the card; contents fade in once the
-- liquid has reached its full shape. One tweened value drives both directions,
-- so a click mid-animation reverses smoothly from where it is.
-- opts: inset, zIndex, top (px below the host's top), gap (px the drip's neck
-- reaches up to the button above), height() -> card height,
-- paint(fill, reveal, active, full), persistent (keep a card once open).
local DISCLOSURE_GAP = 8 -- px between a header/button and the card it opens
local function liquidDisclosure(host, opts)
    local value = create("NumberValue", {Name = "LiquidProgress", Value = 0, Parent = host})
    local render = Resize.createDisclosure and Resize.createDisclosure(host, opts.inset, opts.zIndex, opts.persistent)
    local activeTween = nil
    local function smooth(t) t = math.clamp(t, 0, 1); return t * t * (3 - 2 * t) end
    -- opts.glass: the open card gets the same glass as the buttons (faint mist
    -- fill, moving water, top sheen) under the liquid rim. It fades in with the
    -- contents, once the drop has spread into its card shape.
    local glass = nil
    if opts.glass then
        glass = create("CanvasGroup", {Name = "Glass", BackgroundTransparency = 1, GroupTransparency = 1,
            Position = UDim2.fromOffset(opts.inset, opts.top), Size = UDim2.new(1, -opts.inset * 2, 0, 0),
            Visible = false, ZIndex = opts.zIndex - 1, Parent = host})
        passThrough(glass)
        corner(glass, 12)
        local face = create("Frame", {Name = "Face", BackgroundColor3 = Theme.mist, BackgroundTransparency = 0.94,
            BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = opts.zIndex - 1, Parent = glass})
        passThrough(face)
        corner(face, 12)
        liquidWave(face, Layout.width - opts.inset * 2, math.max(40, opts.height()), 12, opts.zIndex - 1)
        sheen(face, 12, opts.zIndex - 1)
    end
    local function draw()
        if not host.Parent then return end
        local p = math.clamp(value.Value, 0, 1)
        local fill = smooth(p / 0.65)
        local reveal = smooth((p - 0.78) / 0.22)
        if not render then reveal = fill end
        local full = opts.height()
        opts.paint(fill, reveal, p > 0 and p < 1, full)
        if glass then
            glass.Visible = reveal > 0
            -- half strength: over a card this size the full button glass read too bright
            glass.GroupTransparency = 1 - reveal * 0.5
            glass.Size = UDim2.new(1, -opts.inset * 2, 0, full)
        end
        if render then render(p, opts.top, full, opts.gap or 0) end
    end
    track(value:GetPropertyChangedSignal("Value"):Connect(draw))
    local function set(open, instant)
        if activeTween then local old = activeTween; activeTween = nil; old:Cancel() end
        local goal = if open then 1 else 0
        if instant or math.abs(goal - value.Value) < 0.001 then value.Value = goal; draw(); return end
        activeTween = tween(value, Layout.transitionTime * math.abs(goal - value.Value),
            {Value = goal}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        local handle = activeTween
        handle.Completed:Once(function()
            if activeTween == handle then activeTween = nil; value.Value = goal; draw() end
        end)
    end
    draw()
    return set, draw
end
-- Rotating chevron (two rounded bars) used by every disclosure header.
local function disclosureChevron(parent, position, size, zIndex)
    local chevron = create("Frame", {Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = position, Size = UDim2.fromOffset(size, size), ZIndex = zIndex, Parent = parent})
    passThrough(chevron)
    local bars = {}
    for _, side in {-1, 1} do
        local bar = create("Frame", {BackgroundColor3 = Theme.mistDim, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * size * 0.2, 0.5, 0),
            Size = UDim2.fromOffset(2, size * 0.66), Rotation = -side * 45, ZIndex = zIndex, Parent = chevron})
        corner(bar, UDim.new(0.5, 0))
        table.insert(bars, bar)
    end
    return chevron, bars
end
local function addLabel(container, config)
    config = if typeof(config) == "table" then config else {Text = tostring(config or "")}
    local frame = row(container, config.Name or "Label", 24)
    local label = create("TextLabel", {
        Name = "Text", BackgroundTransparency = 1, Size = UDim2.new(1, -Layout.padX * 2, 1, 0),
        Position = UDim2.fromOffset(Layout.padX, 0), FontFace = font(), Text = config.Text or "",
        TextColor3 = Theme.mistDim, TextSize = 12, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = frame,
    })
    local obj = controlBase("Label", frame, label.Text)
    function obj:Set(value)
        self.Value = tostring(value)
        label.Text = self.Value
        return self
    end
    obj.SetText = obj.Set
    return obj
end
local function addParagraph(container, config)
    assert(typeof(config) == "table", "Paragraph needs an options table")
    local frame = row(container, config.Title or "Paragraph", 54)
    local title = create("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(Layout.padX, 0),
        Size = UDim2.new(1, -Layout.padX * 2, 0, 18), FontFace = font(Enum.FontWeight.SemiBold),
        Text = config.Title or "", TextSize = 13, TextColor3 = Theme.mist,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = frame})
    local content = create("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(Layout.padX, 20),
        Size = UDim2.new(1, -Layout.padX * 2, 0, 34), AutomaticSize = Enum.AutomaticSize.Y,
        FontFace = font(), Text = config.Content or "", TextSize = 12, TextWrapped = true,
        TextColor3 = Theme.mistDim, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top, Parent = frame})
    local obj = controlBase("Paragraph", frame, content.Text)
    function obj:Set(value)
        self.Value = tostring(value)
        content.Text = self.Value
        task.defer(function()
            if frame.Parent then frame.Size = UDim2.new(1, 0, 0, 20 + math.max(34, content.TextBounds.Y) + 4) end
        end)
        return self
    end
    function obj:SetTitle(value) title.Text = tostring(value); return self end
    obj:Set(obj.Value)
    return obj
end
local function addDivider(container)
    local frame = row(container, "Divider", Layout.dividerHeight)
    taperedDivider(frame, Layout.dividerHeight / 2)
    return controlBase("Divider", frame)
end
local function addButton(container, config)
    config = if typeof(config) == "table" then config else {Name = tostring(config)}
    local frame = row(container, config.Name or "Button", Layout.buttonHeight)
    local button, label = glassButton(frame, config.Name or "Button", config.Name or config.Text or "Button", 0, Layout.buttonHeight)
    local obj = controlBase("Button", frame, nil, config.Callback, config.Flag)
    if config.Icon then
        local icon = makeIcon(button, config.Icon, 16)
        if icon then icon.Position = UDim2.new(0.5, -math.min(80, #label.Text * 4 + 12), 0.5, -8) end
    end
    function obj:SetText(value) label.Text = tostring(value); return self end
    function obj:Fire()
        if not self.Disabled then self:_emit() end
    end
    obj:Bind(button.MouseButton1Click:Connect(function() obj:Fire() end))
    return obj
end
local function addToggle(container, config)
    assert(typeof(config) == "table", "Toggle needs an options table")
    local frame = row(container, config.Name or "Toggle", Layout.rowHeight)
    local switch = switchRow(frame, config.Name or "Toggle", config.Name or "Toggle", 0)
    local obj = controlBase("Toggle", frame, config.CurrentValue == true, config.Callback, config.Flag)
    switch.set(obj.Value, true)
    function obj:Set(value, silent, instant)
        assert(typeof(value) == "boolean", "Toggle:Set expects a boolean")
        if self.Value == value then return self end
        self.Value = value
        switch.set(value, instant == true)
        if not silent then self:_emit(value) end
        return self
    end
    function obj:SetSubtitle(text, color) switch.setSubtitle(text, color); return self end
    obj:Bind(switch.button.MouseButton1Click:Connect(function()
        if not obj.Disabled then obj:Set(not obj.Value) end
    end))
    return obj
end
local function addInput(container, config)
    assert(typeof(config) == "table", "Input needs an options table")
    local frame = row(container, config.Name or "Input", Layout.buttonHeight)
    local holder = glassButton(frame, config.Name or "Input", "", 0, Layout.buttonHeight)
    local box = create("TextBox", {
        Name = "Input", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 0),
        Size = UDim2.new(1, -40, 1, 0), ClearTextOnFocus = false, FontFace = font(),
        Text = config.CurrentValue or "", PlaceholderText = config.PlaceholderText or config.Name or "",
        TextColor3 = Theme.mist, PlaceholderColor3 = Theme.mistDim, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5, Parent = holder,
    })
    local obj = controlBase("Input", frame, box.Text, config.Callback, config.Flag)
    function obj:Set(value, silent)
        self.Value = tostring(value)
        box.Text = self.Value
        if not silent then self:_emit(self.Value) end
        return self
    end
    obj:Bind(box.FocusLost:Connect(function(enterPressed)
        if not obj.Disabled and (enterPressed or not config.OnlyEnter) then obj:Set(box.Text) end
    end))
    return obj
end
local function addSlider(container, config)
    assert(typeof(config) == "table", "Slider needs an options table")
    local low, high = config.Range and config.Range[1] or config.Min or 0, config.Range and config.Range[2] or config.Max or 100
    assert(typeof(low) == "number" and typeof(high) == "number" and high > low, "Slider needs Min < Max")
    local step = config.Increment or 1
    local frame = row(container, config.Name or "Slider", 54)
    local button, label = glassButton(frame, config.Name or "Slider", config.Name or "Slider", 0, 54)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Position = UDim2.fromOffset(20, -7)
    label.Size = UDim2.new(1, -40, 1, 0)
    local valueLabel = create("TextLabel", {BackgroundTransparency = 1, Position = UDim2.new(1, -75, 0, 4),
        Size = UDim2.fromOffset(55, 20), FontFace = font(), TextSize = 12, TextColor3 = Theme.mist,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = button})
    local trackFrame = create("Frame", {BackgroundColor3 = Theme.mist, BackgroundTransparency = 0.85,
        BorderSizePixel = 0, Position = UDim2.new(0, 20, 1, -13), Size = UDim2.new(1, -40, 0, 4), ZIndex = 5, Parent = button})
    corner(trackFrame, UDim.new(0.5, 0))
    local fill = create("Frame", {BackgroundColor3 = Theme.lilac, BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1), ZIndex = 6, Parent = trackFrame})
    corner(fill, UDim.new(0.5, 0))
    local obj = controlBase("Slider", frame, low, config.Callback, config.Flag)
    function obj:Set(value, silent)
        assert(typeof(value) == "number", "Slider:Set expects a number")
        value = math.clamp(math.round((value - low) / step) * step + low, low, high)
        if value == self.Value and valueLabel.Text ~= "" then return self end
        self.Value = value
        valueLabel.Text = tostring(value) .. (config.Suffix or "")
        fill.Size = UDim2.fromScale((value - low) / (high - low), 1)
        if not silent then self:_emit(value) end
        return self
    end
    obj:Set(config.CurrentValue or low, true)
    local dragging = false
    local function fromPointer(x)
        local start, width = trackFrame.AbsolutePosition.X, math.max(1, trackFrame.AbsoluteSize.X)
        obj:Set(low + math.clamp((x - start) / width, 0, 1) * (high - low))
    end
    obj:Bind(button.InputBegan:Connect(function(input)
        if obj.Disabled then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; fromPointer(input.Position.X)
        end
    end))
    obj:Bind(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then fromPointer(input.Position.X) end
    end))
    obj:Bind(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end))
    return obj
end
local function addDropdown(container, config)
    assert(typeof(config) == "table", "Dropdown needs an options table")
    local choices = config.Options or {}
    local OPTION_H, OPTION_GAP, LIST_PAD = 30, 2, 6
    local frame = row(container, config.Name or "Dropdown", Layout.buttonHeight)
    local button, label = glassButton(frame, config.Name or "Dropdown", config.Name or "Dropdown", 0, Layout.buttonHeight)
    local chevron, chevronBars = disclosureChevron(button, UDim2.new(1, -24, 0.5, 0), 12, 5)
    local listTop = Layout.buttonHeight + DISCLOSURE_GAP
    -- The list fills the liquid card exactly; the pills sit LIST_PAD inside it.
    local list = create("CanvasGroup", {Name = "Options", BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.fromOffset(Layout.padX, listTop), Size = UDim2.new(1, -Layout.padX * 2, 0, 0),
        GroupTransparency = 1, Visible = false, ZIndex = 11, Parent = frame})
    corner(list, 12)
    create("UIPadding", {PaddingTop = UDim.new(0, LIST_PAD), PaddingBottom = UDim.new(0, LIST_PAD),
        PaddingLeft = UDim.new(0, LIST_PAD), PaddingRight = UDim.new(0, LIST_PAD), Parent = list})
    create("UIListLayout", {Padding = UDim.new(0, OPTION_GAP), SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list})
    local obj = controlBase("Dropdown", frame, nil, config.Callback, config.Flag)
    obj.Open = false
    local function listHeight()
        local n = #choices
        return if n > 0 then LIST_PAD * 2 + n * OPTION_H + (n - 1) * OPTION_GAP else 0
    end
    local animate, redraw = liquidDisclosure(frame, {inset = Layout.padX, zIndex = 10, top = listTop, gap = DISCLOSURE_GAP,
        persistent = true, glass = true, height = listHeight,
        paint = function(fill, reveal, active, full)
            list.Visible = (active or obj.Open) and reveal > 0
            list.GroupTransparency = 1 - reveal
            list.Interactable = obj.Open and reveal > 0.95
            list.Size = UDim2.new(1, -Layout.padX * 2, 0, full)
            local extra = if fill > 0 then DISCLOSURE_GAP + full * fill else 0
            frame.Size = UDim2.new(1, 0, 0, Layout.buttonHeight + extra)
        end})
    function obj:SetOpen(open, instant)
        open = open == true
        if open == self.Open then return self end
        self.Open = open
        animate(open, instant)
        local goal = if open then 180 else 0
        if instant then chevron.Rotation = goal
        else tween(chevron, Layout.transitionTime * 0.45, {Rotation = goal}, Enum.EasingStyle.Quint) end
        return self
    end
    function obj:Toggle() return self:SetOpen(not self.Open) end
    -- Option pills: the same hover as every glass control (inward settle plus a
    -- brighter fill); the selected one stays lit.
    local pills = {}
    local function paintPill(pill, hovered)
        local selected = pill:GetAttribute("Choice") == obj.Value
        tween(pill, 0.2, {BackgroundTransparency = if hovered then 0.88 elseif selected then 0.92 else 1})
        tween(pill.Label, 0.2, {TextColor3 = if hovered or selected then Color3.new(1, 1, 1) else Theme.mist})
    end
    function obj:Set(value, silent)
        local found = false
        for _, choice in choices do if choice == value then found = true; break end end
        assert(found, "Dropdown value is not in Options")
        self.Value = value
        label.Text = (config.Name or "Dropdown") .. ": " .. tostring(value)
        for _, pill in pills do paintPill(pill, false) end
        self:SetOpen(false)
        if not silent then self:_emit(value) end
        return self
    end
    function obj:Refresh(newChoices)
        assert(typeof(newChoices) == "table", "Refresh needs an array")
        choices = newChoices
        for _, pill in pills do pill:Destroy() end
        table.clear(pills)
        for index, choice in choices do
            local pill = create("TextButton", {Name = "Option", Text = "", AutoButtonColor = false,
                BackgroundColor3 = Theme.mist, BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, OPTION_H), LayoutOrder = index, ZIndex = 12, Parent = list})
            pill:SetAttribute("Choice", choice)
            corner(pill, 8)
            create("TextLabel", {Name = "Label", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
                Text = tostring(choice), TextColor3 = Theme.mist, TextSize = 12, FontFace = font(Enum.FontWeight.Medium),
                ZIndex = 13, Parent = pill})
            attachHoverScale(pill)
            self:Bind(pill.MouseEnter:Connect(function() paintPill(pill, true) end))
            self:Bind(pill.MouseLeave:Connect(function() paintPill(pill, false) end))
            self:Bind(pill.MouseButton1Click:Connect(function() if not self.Disabled then self:Set(choice) end end))
            table.insert(pills, pill)
            if choice == self.Value then pill.BackgroundTransparency = 0.92; pill.Label.TextColor3 = Color3.new(1, 1, 1) end
        end
        redraw()
        return self
    end
    obj:Refresh(choices)
    obj:Bind(button.MouseButton1Click:Connect(function()
        if obj.Disabled then return end
        obj:Toggle()
    end))
    obj:Bind(button.MouseEnter:Connect(function()
        for _, bar in chevronBars do tween(bar, 0.2, {BackgroundColor3 = Theme.mist}) end
    end))
    obj:Bind(button.MouseLeave:Connect(function()
        for _, bar in chevronBars do tween(bar, 0.25, {BackgroundColor3 = Theme.mistDim}) end
    end))
    if config.CurrentValue ~= nil then obj:Set(config.CurrentValue, true) end
    return obj
end
local function addKeybind(container, config)
    assert(typeof(config) == "table", "Keybind needs an options table")
    local frame = row(container, config.Name or "Keybind", Layout.buttonHeight)
    local button, label = glassButton(frame, config.Name or "Keybind", config.Name or "Keybind", 0, Layout.buttonHeight)
    local keyLabel = create("TextLabel", {BackgroundTransparency = 1, Position = UDim2.new(1, -86, 0, 0),
        Size = UDim2.new(0, 70, 1, 0), TextSize = 12, FontFace = font(), TextColor3 = Theme.mist,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = button})
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Position = UDim2.fromOffset(20, 0)
    label.Size = UDim2.new(1, -115, 1, 0)
    local obj = controlBase("Keybind", frame, config.CurrentKeybind or Enum.KeyCode.Unknown, config.Callback, config.Flag)
    local listening = false
    function obj:Set(key, silent)
        assert(typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode, "Keybind:Set expects Enum.KeyCode")
        self.Value = key
        keyLabel.Text = key.Name
        if not silent then self:_emit(key) end
        return self
    end
    obj:Set(obj.Value, true)
    obj:Bind(button.MouseButton1Click:Connect(function()
        if obj.Disabled then return end
        listening = true; keyLabel.Text = "Press key"
    end))
    obj:Bind(UserInputService.InputBegan:Connect(function(input, processed)
        if obj.Disabled then return end
        if listening then
            if input.KeyCode ~= Enum.KeyCode.Unknown then listening = false; obj:Set(input.KeyCode) end
        elseif not processed and input.KeyCode == obj.Value then safeCall(config.OnTriggered) end
    end))
    return obj
end
local function addColorPicker(container, config)
    assert(typeof(config) == "table", "ColorPicker needs an options table")
    -- One glass card: the header row expands into the picker body (no separate popup).
    local headerHeight = Layout.rowHeight
    -- Compact layout: the shade square (same height as before, narrower) with the
    -- three sliders standing vertically to its right (H / B / A), and only the HEX
    -- row underneath.
    local INSET, KNOB, TRACK_W, HIT_W = 14, 18, 14, 26
    local SHADE_Y, SHADE_H = 0, 160
    local COL_GAP, SIDE_GAP = 12, 14
    local SLIDERS_W = SIDE_GAP + TRACK_W * 3 + COL_GAP * 2
    local TRACK_LEN = SHADE_H - 20          -- room for the caption under each track
    local HEX_Y, HEX_H = SHADE_Y + SHADE_H + 12, 36
    local CAPTION = Layout.captionTextSize or 12
    -- the card around the body: INSET on every side (room for the knobs, which
    -- overhang their tracks by up to 11 px, so nothing is clipped)
    local bodyHeight = INSET + HEX_Y + HEX_H + INSET
    local bodyTop = headerHeight + DISCLOSURE_GAP
    local radius = UDim.new(0, headerHeight / 2)

    local frame = row(container, config.Name or "ColorPicker", headerHeight)
    local card = create("Frame", {Name = "Card", BackgroundColor3 = Theme.mist, BackgroundTransparency = 0.94,
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(1, -Layout.padX * 2, 0, headerHeight), ClipsDescendants = true, ZIndex = 2, Parent = frame})
    corner(card, radius); specularRim(card); sheen(card, radius, 2)

    -- Header ----------------------------------------------------------------
    local header = create("TextButton", {Name = "Header", Text = "", AutoButtonColor = false,
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headerHeight), ZIndex = 4, Parent = card})
    create("TextLabel", {Name = "Label", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 20, 0.5, 0), Size = UDim2.new(1, -172, 0, 20),
        FontFace = font(Enum.FontWeight.SemiBold), Text = config.Name or "ColorPicker", TextSize = 14,
        TextColor3 = Theme.mist, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5, Parent = header})
    local hexValue = create("TextLabel", {Name = "HexValue", BackgroundTransparency = 1,
        Position = UDim2.new(1, -156, 0, 0), Size = UDim2.new(0, 80, 1, 0),
        FontFace = font(Enum.FontWeight.SemiBold), TextSize = 12, TextColor3 = Theme.mistDim,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = header})
    -- Picker art, baked once per window at 4x and drawn as images: every knob
    -- layer is the same-size image (the insets live inside the pixels), so the
    -- layers are always exactly concentric and the same size at any UIScale;
    -- the bead's gloss is one smooth image instead of stacked frames.
    local function pickerArt()
        if Resize.pickerArt ~= nil then return Resize.pickerArt or nil end
        local ok, art = pcall(function()
            local AS = game:GetService("AssetService")
            local function smoothstep(e0, e1, x) local t = math.clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t) end
            local function bake(n, shade)
                local buf = buffer.create(n * n * 4)
                for y = 0, n - 1 do for x = 0, n - 1 do
                    local u, v = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
                    local rgb, alpha = shade(u, v, math.sqrt(u * u + v * v))
                    alpha = math.clamp(alpha, 0, 1)
                    if alpha > 0 then
                        local c = math.floor(math.clamp(rgb, 0, 1) * 255 + 0.5)
                        buffer.writeu32(buf, (y * n + x) * 4, c + c * 256 + c * 65536 + math.floor(alpha * 255 + 0.5) * 16777216)
                    end
                end end
                local image = AS:CreateEditableImage({Size = Vector2.new(n, n)})
                image:WritePixelsBuffer(Vector2.zero, Vector2.new(n, n), buf)
                return image
            end
            -- anti-aliased disc of radius `edge` (fraction of the half-size), `n` px texture
            local function disc(n, edge)
                local px = n / 2
                return bake(n, function(_, _, r) return 1, (edge - r) * px / 2.2 + 0.5 end)
            end
            local K = 22 * 4 -- knob texture: 22 logical px (knob 18 + shadow ring)
            local result = {}
            result.knobBase = bake(K, function(_, _, r)
                local white = math.clamp((9 / 11 - r) * (K / 2) / 2.2 + 0.5, 0, 1)
                local shadow = 0.34 * (1 - smoothstep(0.72, 1, r))
                local a = white + shadow * (1 - white)
                return (a > 0 and white / a or 0), a
            end)
            result.knobWell = disc(K, 5 / 11)
            result.knobFill = disc(K, 6 / 11)
            local B = 24 * 4 -- bead gloss: depth shade, highlight and a faint caustic
            result.beadGloss = bake(B, function(u, v, r)
                local cover = math.clamp((1 - r) * (B / 2) / 2.2 + 0.5, 0, 1)
                if cover <= 0 then return 0, 0 end
                local depth = 0.42 * smoothstep(-0.1, 1, v) ^ 1.5 + 0.16 * r ^ 5
                -- specular crescent that follows the curve of the glass: inside the
                -- bead's edge, outside the same circle shifted toward the bottom right,
                -- brightest at the top left and thinning out around the arc
                local inner = math.sqrt((u - 0.09) ^ 2 + (v - 0.12) ^ 2)
                local band = smoothstep(0.9, 0.87, r) * smoothstep(0.86, 0.91, inner)
                local angle = math.atan2(v, u)
                band *= smoothstep(0.4, 0.92, math.cos(angle - math.rad(-128)))
                local highlight = 0.8 * band
                -- light bending back out through the bottom right
                local caustic = 0.25 * smoothstep(0.74, 0.93, r) * (1 - smoothstep(0.93, 1, r))
                    * smoothstep(0.45, 0.92, math.cos(angle - math.rad(52)))
                local white = math.max(highlight, caustic)
                local a = white + depth * (1 - white)
                return (a > 0 and white / a or 0), a * cover
            end)
            return result
        end)
        Resize.pickerArt = ok and art or false
        if not ok then warn("[Mercury] picker art unavailable: " .. tostring(art)) end
        return ok and art or nil
    end
    local art = pickerArt()
    -- Preview: a liquid-glass bead filled with the colour. The colour is the
    -- liquid; over it sit a soft depth shade, the window's own liquid rim
    -- (9-sliced at the bead's radius) and a specular highlight. It wobbles like
    -- a droplet when the colour changes.
    local BEAD = 24
    local beadHolder = create("Frame", {Name = "Swatch", BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -51, 0.5, 0),
        Size = UDim2.fromOffset(BEAD, BEAD), ZIndex = 5, Parent = header})
    local bead = create("Frame", {Name = "Bead", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = beadHolder})
    local swatch = create("Frame", {Name = "Fill", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        ZIndex = 6, Parent = bead})
    corner(swatch, UDim.new(0.5, 0))
    swatch:SetAttribute("MercuryKeep", true)
    local depth
    if art then
        depth = create("ImageLabel", {Name = "Gloss", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
            ImageContent = Content.fromObject(art.beadGloss), ZIndex = 7, Parent = bead})
    else
        depth = create("Frame", {Name = "Depth", BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = bead})
        corner(depth, UDim.new(0.5, 0))
        create("UIGradient", {Rotation = 90,
            Transparency = numberSeq({{0, 1}, {0.45, 1}, {1, 0.55}}), Parent = depth})
    end
    local beadRim = Resize.beadRim
    if beadRim then
        local k = Layout.uiScale
        local s, mg = beadRim.side, beadRim.margin
        create("ImageLabel", {Name = "LiquidRim", BackgroundTransparency = 1, ImageColor3 = Theme.mist,
            ImageContent = Content.fromObject(beadRim.image), ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(s / 2 - 1, s / 2 - 1, s / 2 + 1, s / 2 + 1), SliceScale = 1 / k,
            Position = UDim2.fromOffset(-mg / k, -mg / k), Size = UDim2.new(1, 2 * mg / k, 1, 2 * mg / k),
            ZIndex = 8, Parent = bead})
    else
        specularRim(depth, 1, 0.2)
    end
    local wobbling, beadShown, holdWobble = false, false, false
    local function wobble()
        if not beadShown then beadShown = true; return end -- no wobble for the first colour
        if wobbling then return end
        wobbling = true
        bead.Size = UDim2.fromScale(1.1, 0.9)
        tween(bead, 0.55, {Size = UDim2.fromScale(1, 1)}, Enum.EasingStyle.Elastic)
        task.delay(0.35, function() wobbling = false end)
    end
    local chevron, chevronBars = disclosureChevron(header, UDim2.new(1, -26, 0.5, 0), 12, 5)

    -- Body ------------------------------------------------------------------
    -- bodyGroup covers the whole liquid card (so nothing near its edge is
    -- clipped); the controls live in `body`, INSET inside it
    local bodyGroup = create("CanvasGroup", {Name = "Body", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(Layout.padX, bodyTop), Size = UDim2.new(1, -Layout.padX * 2, 0, bodyHeight),
        GroupTransparency = 1, Visible = false, ZIndex = 4, Parent = frame})
    local body = create("Frame", {Name = "Content", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(INSET, INSET), Size = UDim2.new(1, -INSET * 2, 1, -INSET * 2),
        ZIndex = 4, Parent = bodyGroup})

    local shade = create("Frame", {Name = "Shade", BorderSizePixel = 0, Position = UDim2.fromOffset(0, SHADE_Y),
        Size = UDim2.new(1, -SLIDERS_W, 0, SHADE_H), ZIndex = 3, Parent = body})
    corner(shade, 14)
    local white = create("Frame", {BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = shade})
    corner(white, 14)
    create("UIGradient", {Transparency = NumberSequence.new(0, 1), Parent = white})
    local black = create("Frame", {BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = shade})
    corner(black, 14)
    create("UIGradient", {Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black})
    create("UIStroke", {Color = Color3.new(1, 1, 1), Transparency = 0.86, Thickness = 1, Parent = shade})
    local shadeHit = create("TextButton", {Name = "ShadeInput", Text = "", AutoButtonColor = false,
        BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = shade})

    -- Knob = solid white disc with the colour disc laid on top (no UIStroke: a
    -- stroke around a fill leaves a 1px seam when UIScale makes sizes fractional).
    -- Every layer is inset from its parent's edges so it stays exactly centred.
    local function makeKnob(parent, size, z)
        if art then
            local holder = create("Frame", {Name = "KnobShadow", AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1, Size = UDim2.fromOffset(size + 4, size + 4), ZIndex = z, Parent = parent})
            local function layer(image, name, zz)
                return create("ImageLabel", {Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
                    ImageContent = Content.fromObject(image), ZIndex = zz, Parent = holder})
            end
            layer(art.knobBase, "Rim", z + 1)
            layer(art.knobWell, "Well", z + 2).ImageColor3 = Theme.tint
            local fill = layer(art.knobFill, "Knob", z + 3)
            fill:SetAttribute("MercuryKeep", true)
            return holder, fill
        end
        local holder = create("Frame", {Name = "KnobShadow", AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.72, BorderSizePixel = 0,
            Size = UDim2.fromOffset(size + 4, size + 4), ZIndex = z, Parent = parent})
        corner(holder, UDim.new(0.5, 0))
        local rim = create("Frame", {Name = "Rim", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
            Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), ZIndex = z + 1, Parent = holder})
        corner(rim, UDim.new(0.5, 0))
        -- dark well under the colour (only shows through when the colour is transparent);
        -- smaller than the fill so the fill's edge always blends into white, never dark
        local well = create("Frame", {Name = "Well", BackgroundColor3 = Theme.tint, BorderSizePixel = 0,
            Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), ZIndex = z + 2, Parent = rim})
        corner(well, UDim.new(0.5, 0))
        local fill = create("Frame", {Name = "Knob", BorderSizePixel = 0,
            Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = z + 3, Parent = rim})
        corner(fill, UDim.new(0.5, 0))
        return holder, fill
    end
    shade:SetAttribute("MercuryKeep", true)
    local shadeKnobHolder, shadeKnob = makeKnob(shade, KNOB, 7)
    local function paintKnob(knob, color, transparency)
        if knob:IsA("ImageLabel") then knob.ImageColor3 = color; knob.ImageTransparency = transparency or 0
        else knob.BackgroundColor3 = color; knob.BackgroundTransparency = transparency or 0 end
    end

    local function caption(text, x, y, w, align)
        return create("TextLabel", {Name = text .. "Label", BackgroundTransparency = 1,
            Position = UDim2.new(1, x, 0, y), Size = UDim2.fromOffset(w, CAPTION + 2),
            FontFace = font(Enum.FontWeight.SemiBold), Text = text, TextSize = CAPTION,
            TextColor3 = Theme.mistDim, TextXAlignment = align or Enum.TextXAlignment.Center, ZIndex = 4, Parent = body})
    end
    -- vertical track number `column` (1..3), right of the square
    local function track(text, column)
        local x = -SLIDERS_W + SIDE_GAP + (column - 1) * (TRACK_W + COL_GAP)
        caption(text, x - 6, SHADE_Y + TRACK_LEN + 4, TRACK_W + 12)
        local bar = create("Frame", {Name = text .. "Track", BorderSizePixel = 0,
            Position = UDim2.new(1, x, 0, SHADE_Y), Size = UDim2.fromOffset(TRACK_W, TRACK_LEN), ZIndex = 4, Parent = body})
        corner(bar, UDim.new(0.5, 0))
        create("UIStroke", {Color = Color3.new(1, 1, 1), Transparency = 0.84, Thickness = 1, Parent = bar})
        local hit = create("TextButton", {Name = "Input", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, HIT_W, 1, 0),
            ZIndex = 8, Parent = bar})
        local holder, knob = makeKnob(bar, KNOB, 6)
        return bar, hit, holder, knob
    end
    -- knob travels inside the track so it never hangs off the rounded ends
    local function along(fraction)
        return UDim2.new(0.5, 0, fraction, KNOB / 2 - KNOB * fraction)
    end

    local hueBar, hueHit, hueKnobHolder, hueKnob = track("H", 1)
    local hueKeys = {}
    for i = 0, 6 do
        table.insert(hueKeys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i % 6) / 6, 1, 1)))
    end
    create("UIGradient", {Rotation = 90, Color = ColorSequence.new(hueKeys), Parent = hueBar})
    hueBar.BackgroundColor3 = Color3.new(1, 1, 1)

    -- brightness, top to bottom: white, the pure colour (middle), black
    local brightBar, brightHit, brightKnobHolder, brightKnob = track("B", 2)
    brightBar.BackgroundColor3 = Color3.new(1, 1, 1)
    brightBar:SetAttribute("MercuryKeep", true)
    local brightGradient = create("UIGradient", {Rotation = 90, Parent = brightBar})

    -- transparency, top to bottom: opaque to clear
    local alphaBar, alphaHit, alphaKnobHolder, alphaKnob = track("A", 3)
    alphaBar.BackgroundColor3 = Theme.tint
    alphaBar.BackgroundTransparency = 0.25
    local alphaFill = create("Frame", {Name = "Fill", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
        ZIndex = 5, Parent = alphaBar})
    corner(alphaFill, UDim.new(0.5, 0))
    alphaFill:SetAttribute("MercuryKeep", true)
    create("UIGradient", {Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = alphaFill})

    -- HEX row (full width under the square): caption, field, transparency value
    local hexCaption = create("TextLabel", {Name = "HEXLabel", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(2, HEX_Y), Size = UDim2.fromOffset(38, HEX_H),
        FontFace = font(Enum.FontWeight.SemiBold), Text = "HEX", TextSize = CAPTION,
        TextColor3 = Theme.mistDim, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = body})
    local hexHolder = create("Frame", {Name = "HexField", BackgroundColor3 = Theme.tint, BackgroundTransparency = 0.45,
        BorderSizePixel = 0, Position = UDim2.fromOffset(44, HEX_Y), Size = UDim2.new(1, -44 - 58, 0, HEX_H),
        ZIndex = 4, Parent = body})
    corner(hexHolder, UDim.new(0.5, 0))
    local hexStroke = create("UIStroke", {Color = Color3.new(1, 1, 1), Transparency = 0.86, Thickness = 1, Parent = hexHolder})
    create("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(12, HEX_H),
        FontFace = font(Enum.FontWeight.SemiBold), Text = "#", TextSize = 16, TextColor3 = Theme.mistDim,
        ZIndex = 5, Parent = hexHolder})
    local hexBox = create("TextBox", {Name = "HexInput", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -44, 1, 0),
        FontFace = font(Enum.FontWeight.SemiBold), Text = "", PlaceholderText = "RRGGBB",
        TextSize = 15, TextColor3 = Theme.mist, PlaceholderColor3 = Theme.mistDim,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ZIndex = 5, Parent = hexHolder})
    local alphaValue = create("TextLabel", {Name = "TransparencyValue", BackgroundTransparency = 1,
        Position = UDim2.new(1, -52, 0, HEX_Y), Size = UDim2.fromOffset(50, HEX_H),
        FontFace = font(Enum.FontWeight.SemiBold), TextSize = CAPTION + 1, TextColor3 = Theme.mist,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4, Parent = body})

    -- State -----------------------------------------------------------------
    local obj = controlBase("ColorPicker", frame, config.CurrentValue or Color3.new(1, 1, 1), config.Callback, config.Flag)
    assert(typeof(obj.Value) == "Color3", "ColorPicker CurrentValue must be a Color3")
    local initialTransparency = config.CurrentTransparency or config.Transparency or 0
    assert(typeof(initialTransparency) == "number", "ColorPicker transparency must be a number")
    obj.Transparency = math.clamp(initialTransparency, 0, 1)
    obj.Open = false
    local animate = liquidDisclosure(frame, {inset = Layout.padX, zIndex = 3, top = bodyTop, gap = DISCLOSURE_GAP,
        persistent = true, glass = true, height = function() return bodyHeight end,
        paint = function(fill, reveal, active, full)
            bodyGroup.Visible = (active or obj.Open) and reveal > 0
            bodyGroup.GroupTransparency = 1 - reveal
            bodyGroup.Interactable = obj.Open and reveal > 0.95
            local extra = if fill > 0 then DISCLOSURE_GAP + full * fill else 0
            frame.Size = UDim2.new(1, 0, 0, headerHeight + extra)
        end})
    local hue, saturation, shadeValue = obj.Value:ToHSV()
    local brightness = 0
    local editingHex = false

    local function hexOf(color)
        return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
    end
    local function baseColor() return Color3.fromHSV(hue, saturation, shadeValue) end
    local function mixedColor()
        local target = if brightness < 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
        return baseColor():Lerp(target, math.abs(brightness))
    end
    local function render()
        local base, color = baseColor(), mixedColor()
        shade.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        paintKnob(shadeKnob, base)
        shadeKnobHolder.Position = UDim2.fromScale(saturation, 1 - shadeValue)
        paintKnob(hueKnob, Color3.fromHSV(hue, 1, 1))
        hueKnobHolder.Position = along(hue)
        brightGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(0.5, base),
            ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
        })
        paintKnob(brightKnob, color)
        brightKnobHolder.Position = along((brightness + 1) / 2)
        alphaFill.BackgroundColor3 = color
        paintKnob(alphaKnob, color, obj.Transparency)
        alphaKnobHolder.Position = along(obj.Transparency)
        alphaValue.Text = string.format("%d%%", math.round(obj.Transparency * 100))
        if swatch.BackgroundColor3 ~= color then swatch.BackgroundColor3 = color; if not holdWobble then wobble() end end
        swatch.BackgroundTransparency = obj.Transparency * 0.8
        hexValue.Text = hexOf(color)
        if not editingHex then hexBox.Text = string.sub(hexValue.Text, 2) end
    end
    local function updateColor()
        local color = mixedColor()
        if color == obj.Value then render(); return end
        obj.Value = color
        render()
        obj:_emit(color, obj.Transparency)
    end
    function obj:Set(value, silent)
        assert(typeof(value) == "Color3", "ColorPicker:Set expects Color3")
        local newHue, newSaturation, newValue = value:ToHSV()
        -- greys/black have no hue: keep the current one so the hue knob doesn't jump to red
        if newSaturation > 0 and newValue > 0 then hue = newHue end
        saturation, shadeValue, brightness = newSaturation, newValue, 0
        local changed = self.Value ~= value
        self.Value = value
        render()
        if changed and not silent then self:_emit(value, self.Transparency) end
        return self
    end
    function obj:SetTransparency(transparency, silent)
        assert(typeof(transparency) == "number", "ColorPicker:SetTransparency expects a number")
        transparency = math.clamp(transparency, 0, 1)
        if transparency == self.Transparency then return self end
        self.Transparency = transparency
        render()
        if not silent then self:_emit(self.Value, transparency) end
        return self
    end
    function obj:SetOpen(open, instant)
        open = open == true
        if open == self.Open then return self end
        self.Open = open
        animate(open, instant)
        local goal = if open then 180 else 0
        if instant then chevron.Rotation = goal
        else tween(chevron, Layout.transitionTime * 0.45, {Rotation = goal}, Enum.EasingStyle.Quint) end
        return self
    end
    function obj:Toggle() return self:SetOpen(not self.Open) end
    obj:Set(obj.Value, true)

    -- Input -----------------------------------------------------------------
    local dragging = nil
    local function fromPointer(kind, pointer)
        if obj.Disabled then return end
        if kind == "shade" then
            local pos, size = shade.AbsolutePosition, shade.AbsoluteSize
            saturation = math.clamp((pointer.X - pos.X) / math.max(1, size.X), 0, 1)
            shadeValue = 1 - math.clamp((pointer.Y - pos.Y) / math.max(1, size.Y), 0, 1)
        else
            local bar = if kind == "hue" then hueBar elseif kind == "brightness" then brightBar else alphaBar
            local holder = if kind == "hue" then hueKnobHolder elseif kind == "brightness" then brightKnobHolder else alphaKnobHolder
            -- knob centres stop KNOB/2 px in from each end; measure that in screen px (UIScale aware)
            local inset = holder.AbsoluteSize.Y * (KNOB / 2) / (KNOB + 4)
            local fraction = math.clamp((pointer.Y - bar.AbsolutePosition.Y - inset) / math.max(1, bar.AbsoluteSize.Y - inset * 2), 0, 1)
            if kind == "transparency" then obj:SetTransparency(math.round(fraction * 100) / 100); return end
            if kind == "hue" then hue = fraction else
                brightness = fraction * 2 - 1
                if math.abs(brightness) < 0.04 then brightness = 0 end
            end
        end
        updateColor()
    end
    for _, part in {{shadeHit, "shade"}, {hueHit, "hue"}, {brightHit, "brightness"}, {alphaHit, "transparency"}} do
        obj:Bind(part[1].InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = part[2]
                wobble(); holdWobble = true -- one wobble as the drag starts, none while sliding
                fromPointer(dragging, input.Position)
            end
        end))
    end
    -- double-click the brightness track to snap back to the pure color
    local lastBrightClick = 0
    obj:Bind(brightHit.MouseButton1Down:Connect(function()
        local now = os.clock()
        if now - lastBrightClick < 0.3 then brightness = 0; updateColor() end
        lastBrightClick = now
    end))
    obj:Bind(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            fromPointer(dragging, input.Position)
        end
    end))
    obj:Bind(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = nil; holdWobble = false end
    end))

    local function parseHex(text)
        if #text == 3 then text = text:gsub("%x", "%0%0") end
        if #text ~= 6 then return nil end
        return Color3.fromRGB(tonumber(text:sub(1, 2), 16), tonumber(text:sub(3, 4), 16), tonumber(text:sub(5, 6), 16))
    end
    obj:Bind(hexBox.Focused:Connect(function()
        editingHex = true
        tween(hexStroke, 0.15, {Color = Theme.lilac, Transparency = 0.25})
        task.defer(function() hexBox.SelectionStart = 1; hexBox.CursorPosition = #hexBox.Text + 1 end)
    end))
    obj:Bind(hexBox:GetPropertyChangedSignal("Text"):Connect(function()
        if not editingHex then return end
        local cleaned = string.upper(string.gsub(hexBox.Text, "[^%x]", "")):sub(1, 6)
        if cleaned ~= hexBox.Text then hexBox.Text = cleaned; return end
        hexBox.TextColor3 = if #cleaned == 6 or #cleaned == 0 then Theme.mist else Theme.danger
        if #cleaned == 6 and not obj.Disabled then obj:Set(parseHex(cleaned)) end
    end))
    obj:Bind(hexBox.FocusLost:Connect(function()
        local color = parseHex(hexBox.Text)
        if color and #hexBox.Text == 3 and not obj.Disabled then obj:Set(color) end
        editingHex = false
        hexBox.TextColor3 = Theme.mist
        tween(hexStroke, 0.2, {Color = Color3.new(1, 1, 1), Transparency = 0.86})
        render()
    end))

    -- same hover as every glass button: settle inward, press, brighter fill
    attachHoverScale(header, card)
    obj:Bind(header.MouseEnter:Connect(function()
        tween(card, 0.2, {BackgroundTransparency = 0.9})
        for _, bar in chevronBars do tween(bar, 0.2, {BackgroundColor3 = Theme.mist}) end
    end))
    obj:Bind(header.MouseLeave:Connect(function()
        tween(card, 0.25, {BackgroundTransparency = 0.94})
        for _, bar in chevronBars do tween(bar, 0.25, {BackgroundColor3 = Theme.mistDim}) end
    end))
    obj:Bind(header.MouseButton1Click:Connect(function()
        if not obj.Disabled then obj:Toggle() end
    end))
    if config.Open == true then obj:SetOpen(true, true) end
    return obj
end
local factories = {CreateLabel = addLabel, CreateParagraph = addParagraph, CreateDivider = addDivider, CreateButton = addButton,
    CreateToggle = addToggle, CreateInput = addInput, CreateSlider = addSlider,
    CreateDropdown = addDropdown, CreateKeybind = addKeybind, CreateColorPicker = addColorPicker}
local function installFactories(target, container)
    for name, factory in factories do
        target[name] = function(_, config) return factory(container, config) end
        local short = name:gsub("^Create", "Add")
        target[short] = target[name]
    end
end
function window:CreateTab(name, icon)
    if name == "Settings" and tabByName.Settings then return tabByName.Settings end
    local tab = addTab(name, icon)
    tab.Attributes = {}
    function tab:SetAttribute(key, value) self.Attributes[key] = value; self.page:SetAttribute(key, value); return self end
    function tab:GetAttribute(key) return self.Attributes[key] end
    installFactories(tab, tab.content)
    function tab:CreateSection(title, sectionOptions)
        local section = {Name = title}
        local holder = row(self.content, title, 0)
        holder.AutomaticSize = Enum.AutomaticSize.None
        -- Heading: TITLE ─────── with half a tapered divider after the title, thick
        -- and glowing next to the text and thinning out toward the right edge.
        -- rest tint (multiplied with the glint gradient); hover brightens it to white
        local HEAD_REST = Color3.new(0.95, 0.95, 0.95)
        local HEAD_H, RULE_GAP, RULE_LENGTH, RULE_NUDGE = 24, 16, 170, 1.5
        -- title lines up with the row labels inside the glass rows, not the rows' edge
        local TITLE_X = Layout.padX + 20
        local heading = create("TextLabel", {Name = "Heading", BackgroundTransparency = 1,
            -- sized to the text itself (not the row) so the glint's band crosses the letters
            Position = UDim2.fromOffset(TITLE_X, 0), Size = UDim2.fromOffset(0, HEAD_H), AutomaticSize = Enum.AutomaticSize.X,
            FontFace = font(Enum.FontWeight.Bold), Text = string.upper(title),
            TextColor3 = HEAD_REST, TextTransparency = 0, TextSize = 13, -- white: the glint UIGradient supplies the mist tint (gradients multiply the text colour)
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Parent = holder})
        local mark = create("Frame", {Name = "Rule", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(Layout.padX, HEAD_H / 2 - 2), Size = UDim2.new(1, -Layout.padX * 2, 0, 4), Parent = holder})
        passThrough(mark)
        local function placeRule()
            local start = math.ceil(heading.TextBounds.X) + RULE_GAP
            -- the text box leaves room below for descenders (g, p, y), so ALL-CAPS titles sit
            -- ~1px above the box centre; RULE_NUDGE lines the rule up with the capitals instead
            mark.Position = UDim2.fromOffset(TITLE_X + start, math.round(HEAD_H / 2 - Divider.maxThickness / 2) + RULE_NUDGE)
            mark.Size = UDim2.fromOffset(RULE_LENGTH, Divider.maxThickness)
        end
        heading:GetPropertyChangedSignal("TextBounds"):Connect(placeRule)
        placeRule()
        -- Glint sweep: every 6-10 s a thin, slanted bright streak slides across the
        -- letters, like light passing over glass. It is a narrow white band in a
        -- UIGradient on the title text whose Offset is tweened from left to right.
        local glowLayers = {}
        -- band profile (moving right): a long, faint, eased ghost trail on the left,
        -- a smooth rise, a flat white core about 1.5 letters wide, a quicker fall-off
        local glintKeys = {}
        local function glintAt(x)
            local function smooth(a) a = math.clamp(a, 0, 1); return a * a * (3 - 2 * a) end
            if x < 0.08 then return 0
            elseif x < 0.40 then return 0.3 * ((x - 0.08) / 0.32) ^ 2.2
            elseif x < 0.45 then return 0.3 + 0.7 * smooth((x - 0.40) / 0.05)
            elseif x <= 0.57 then return 1
            else return 1 - smooth((x - 0.57) / 0.06) end
        end
        local function glintColors()
            table.clear(glintKeys)
            for _, x in {0, 0.08, 0.14, 0.2, 0.26, 0.32, 0.37, 0.40, 0.425, 0.45, 0.57, 0.6, 0.63, 1} do
                table.insert(glintKeys, ColorSequenceKeypoint.new(x, Theme.mist:Lerp(Theme.bruise, 0.13):Lerp(Color3.new(1, 1, 1), glintAt(x))))
            end
            return ColorSequence.new(glintKeys)
        end
        local glint = create("UIGradient", {Rotation = 20, Offset = Vector2.new(-1.2, 0),
            Color = glintColors(), Parent = heading})
        -- the title's resting tint follows the theme
        Resize.themeHooks = Resize.themeHooks or {}
        table.insert(Resize.themeHooks, function() if glint.Parent then glint.Color = glintColors() end end)
        -- swept on the window's shared glint beat, in sync with the game name
        Resize.glintListeners = Resize.glintListeners or {}
        table.insert(Resize.glintListeners, function()
            if not holder.Parent then return false end
            glint.Offset = Vector2.new(-1.2, 0)
            tween(glint, 2.4, {Offset = Vector2.new(1.2, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
            return true
        end)
        -- The rule is the right half of the regular divider: same layer count, taper,
        -- per-layer fade and colour (read from Divider), bright at the title, thinning out.
        local LEAD = 0
        local boxHeight = Divider.maxThickness
        local layerAlpha = 1 - (1 - Divider.centreOpacity) ^ (1 / Divider.layers)
        local halfFade = numberSeq({
            {0, 1 - layerAlpha}, {0.16, 1 - layerAlpha * 0.85}, {0.4, 1 - layerAlpha * 0.45},
            {0.7, 1 - layerAlpha * 0.1}, {1, 1},
        })
        local body = create("Frame", {Name = "Body", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(LEAD, 0), Size = UDim2.new(1, -LEAD, 1, 0), Parent = mark})
        for index = 1, Divider.layers do
            local t = (index - 1) / (Divider.layers - 1)
            local height = if t < 0.5 then 1 else boxHeight
            local line = create("Frame", {BackgroundColor3 = Theme.spec, BorderSizePixel = 0,
                Position = UDim2.fromOffset(0, (boxHeight - height) // 2),
                Size = UDim2.new(1 - t * (1 - Divider.minWidth), 0, 0, height), ZIndex = 2, Parent = body})
            corner(line, UDim.new(0.5, 0))
            create("UIGradient", {Transparency = halfFade, Parent = line})
        end
        local reveal = create("CanvasGroup", {Name = "LiquidReveal", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, HEAD_H + 4), Size = UDim2.new(1, 0, 0, 0),
            ClipsDescendants = true, Parent = holder})
        local content = create("Frame", {Name = "Items", BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = reveal})
        create("UIListLayout", {Padding = UDim.new(0, Layout.itemGap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content})
        section.Instance = holder
        installFactories(section, content)
        local animate, redraw = liquidDisclosure(holder, {inset = Layout.padX, zIndex = 2, top = HEAD_H + 6,
            height = function() return content.AbsoluteSize.Y / math.max(0.001, root.AbsoluteSize.X / root.Size.X.Offset) end,
            paint = function(fill, opacity, active, full)
                local height = full * fill
                reveal.Size = UDim2.new(1, 0, 0, math.ceil(height) + 4)
                reveal.GroupTransparency = 1 - opacity
                reveal.Interactable = not section.Collapsed and opacity > 0.95
                local settled = not active and fill == 1
                reveal.Visible = not settled and fill > 0
                local parent = if settled then holder else reveal
                if content.Parent ~= parent then content.Parent = parent end
                content.Position = UDim2.fromOffset(0, if settled then HEAD_H + 6 else 2)
                holder.Size = UDim2.new(1, 0, 0, HEAD_H + 6 + height + 10 + fill * 10)
            end})
        track(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(redraw))
        animate(true, true)

        -- The heading controls the same liquid reveal as the other disclosures.
        local headButton = create("TextButton", {Name = "HeadingButton", Text = "", AutoButtonColor = false,
            BackgroundTransparency = 1, Position = UDim2.fromOffset(Layout.padX, 0),
            Size = UDim2.new(1, -Layout.padX * 2, 0, HEAD_H), ZIndex = 3, Parent = holder})
        local chevron = create("Frame", {Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -Layout.padX - 26, 0, HEAD_H / 2), Size = UDim2.fromOffset(10, 10), Parent = holder})
        local chevronBars = {}
        for _, side in {-1, 1} do
            local bar = create("Frame", {BackgroundColor3 = Theme.mistDim, BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * 2, 0.5, 0),
                Size = UDim2.fromOffset(2, 7), Rotation = -side * 45, Parent = chevron})
            corner(bar, UDim.new(0.5, 0))
            table.insert(chevronBars, bar)
        end
        section.Collapsed = false
        function section:SetCollapsed(collapsed, instant)
            collapsed = collapsed == true
            if collapsed == self.Collapsed then return self end
            self.Collapsed = collapsed
            animate(not collapsed, instant)
            if instant then chevron.Rotation = if collapsed then -90 else 0
            else tween(chevron, Layout.transitionTime * 0.45, {Rotation = if collapsed then -90 else 0}) end
            return self
        end
        function section:Toggle() return self:SetCollapsed(not self.Collapsed) end
        local function setHover(on)
            tween(heading, 0.18, {TextColor3 = if on then Color3.new(1, 1, 1) else HEAD_REST})
            for _, layer in glowLayers do
                tween(layer.stroke, 0.18, {Transparency = if on then layer.base - (1 - layer.base) * 0.6 else layer.base})
            end
            for _, bar in chevronBars do tween(bar, 0.18, {BackgroundColor3 = if on then Theme.mist else Theme.mistDim}) end
        end
        track(headButton.MouseEnter:Connect(function() setHover(true) end))
        track(headButton.MouseLeave:Connect(function() setHover(false) end))
        track(headButton.MouseButton1Click:Connect(function() section:Toggle() end))
        if typeof(sectionOptions) == "table" and sectionOptions.Collapsed == true then section:SetCollapsed(true, true) end

        function section:Destroy() holder:Destroy() end
        return section
    end
    tab.AddSection = tab.CreateSection
    function tab:Select() return selectTab(self.Name) end
    function tab:Destroy()
        if self.Name == "Settings" then return end
        self.parts.button:Destroy(); self.parts.label:Destroy(); self.parts.platter:Destroy(); self.page:Destroy()
        if self.parts.icon then self.parts.icon:Destroy() end
        tabByName[self.Name] = nil
        table.remove(tabs, self.index)
        for i, item in tabs do item.index = i end
        layoutTabs()
        if #tabs > 0 then selectTab(tabs[1].Name, true) else state.currentTab = nil end
    end
    return tab
end
window.AddTab = window.CreateTab
window.SettingsTab = window:CreateTab("Settings", "settings")

-- The game name wears the section headings' glint: white text tinted by a
-- UIGradient, with a soft band (and faint trail) sweeping across the text
-- every few seconds. The band is sized to the text, not the wider label.
do
    local WHITE = Color3.new(1, 1, 1)
    local POINTS = {0, 0.08, 0.14, 0.2, 0.26, 0.32, 0.37, 0.40, 0.425, 0.45, 0.57, 0.6, 0.63}
    local function smooth(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
    local function glintAt(x)
        if x < 0.08 then return 0
        elseif x < 0.40 then return 0.3 * ((x - 0.08) / 0.32) ^ 2.2
        elseif x < 0.45 then return 0.3 + 0.7 * smooth((x - 0.40) / 0.05)
        elseif x <= 0.57 then return 1
        else return 1 - smooth((x - 0.57) / 0.06) end
    end
    -- the band laid over the first `fraction` of the label (where the text is)
    local fraction = 1
    local function colors()
        local base = Theme.mist:Lerp(Theme.bruise, 0.13)
        local keys = {}
        for _, x in POINTS do table.insert(keys, ColorSequenceKeypoint.new(x * fraction, base:Lerp(WHITE, glintAt(x)))) end
        table.insert(keys, ColorSequenceKeypoint.new(1, base))
        return ColorSequence.new(keys)
    end
    gameTitle.TextColor3 = Color3.new(0.95, 0.95, 0.95)
    local titleGlint = create("UIGradient", {Offset = Vector2.new(-1.2, 0), Color = colors(), Parent = gameTitle})
    Resize.themeHooks = Resize.themeHooks or {}
    table.insert(Resize.themeHooks, function() if titleGlint.Parent then titleGlint.Color = colors() end end)
    Resize.glintListeners = Resize.glintListeners or {}
    table.insert(Resize.glintListeners, function()
        if not gameTitle.Parent then return false end
        fraction = math.clamp(gameTitle.TextBounds.X / math.max(1, gameTitle.AbsoluteSize.X), 0.05, 1)
        titleGlint.Color = colors()
        titleGlint.Offset = Vector2.new(-0.7 * fraction, 0)
        tween(titleGlint, 2.4, {Offset = Vector2.new(1.0 * fraction, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
        return true
    end)
    -- One beat for every glint (game name and section titles): they all sweep
    -- together, every 2.4 s sweep + 2.75 s pause (was 3-5 s, random per title).
    task.spawn(function()
        task.wait(1)
        while not state.destroyed do
            local listeners = Resize.glintListeners or {}
            for i = #listeners, 1, -1 do
                local ok, alive = pcall(listeners[i])
                if not ok or alive == false then table.remove(listeners, i) end
            end
            task.wait(2.4 + 2.75)
        end
    end)
end

-- Themes ---------------------------------------------------------------------
-- window:SetTheme("Red") or a table of role colours ({Accent = ..., Text = ...},
-- role names in config.lua). Every colour in the window is matched by value to
-- its role and swapped; the liquid marble and rim light rebuild from the new
-- colours. Colours that belong to the user (colour picker values) are kept.
window.Themes = table.clone(ThemeOrder)
window.Theme = "Default"
local function colorKey(c: Color3): number
    return math.round(c.R * 255) * 65536 + math.round(c.G * 255) * 256 + math.round(c.B * 255)
end
local function keepColor(o) return o:GetAttribute("MercuryKeep") or (o.Parent ~= nil and o.Parent:GetAttribute("MercuryKeep")) end
-- Every themed colour in the window as {instance, property, role key}; a gradient
-- is {instance, "Gradient", {keypoint index -> role key}}. `known` maps colour
-- values (current and recent palettes) to role keys.
local function scanThemed(known)
    local list = {}
    local function bind(o, prop, value)
        local key = known[colorKey(value)]
        if key then list[#list + 1] = {o, prop, key} end
    end
    for _, o in screenGui:GetDescendants() do
        if keepColor(o) then continue end
        if o:IsA("GuiObject") then
            bind(o, "BackgroundColor3", o.BackgroundColor3)
            if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
                bind(o, "TextColor3", o.TextColor3)
                if o:IsA("TextBox") then bind(o, "PlaceholderColor3", o.PlaceholderColor3) end
            elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then
                bind(o, "ImageColor3", o.ImageColor3)
            end
        elseif o:IsA("UIStroke") then
            bind(o, "Color", o.Color)
        elseif o:IsA("UIGradient") then
            local roles, any = {}, false
            for i, point in o.Color.Keypoints do
                local key = known[colorKey(point.Value)]
                if key then roles[i] = key; any = true end
            end
            if any then list[#list + 1] = {o, "Gradient", roles} end
        end
    end
    return list
end
local function knownColors(palettes)
    local known = {}
    for _, palette in palettes do for _, role in ThemeRoles do known[colorKey(palette[role.key])] = role.key end end
    return known
end
local function applyPalette(palette, bindings)
    for _, b in bindings do
        local o = b[1]
        if o.Parent then
            if b[2] == "Gradient" then
                local keys = {}
                for i, point in o.Color.Keypoints do
                    local key = b[3][i]
                    keys[i] = ColorSequenceKeypoint.new(point.Time, if key then palette[key] else point.Value)
                end
                o.Color = ColorSequence.new(keys)
            else
                o[b[2]] = palette[b[3]]
            end
        end
    end
    for key, value in palette do Theme[key] = value end
    -- pixel-baked pieces (resize grip) follow the accent's hue
    local h0, s0, v0 = DefaultPalette.violet:ToHSV()
    local h1, s1, v1 = Theme.violet:ToHSV()
    Resize.themeTint = {hue = h1, sat = s1 / math.max(s0, 1e-3), value = v1 / math.max(v0, 1e-3),
        default = Theme.violet == DefaultPalette.violet}
    for _, hook in Resize.themeHooks or {} do task.spawn(hook, Theme) end
end
local rainbowToken = 0
local themeHistory = {} -- recent rainbow palettes, so leaving Rainbow finds every colour
function window:SetTheme(theme)
    rainbowToken += 1
    if theme == "Rainbow" then
        -- The hue drifts through every colour (a full turn in ~25 s). Every themed
        -- colour property is watched (new instances join as they appear); each tick
        -- reads its value, finds its role among recent palettes and sets the new
        -- colour, so no periodic full rescan (that hitched every 2 s). The liquid's
        -- marble is re-tinted with native image ops every 0.3 s and fully rebuilt
        -- in the background every 6 s.
        local token = rainbowToken
        self.Theme = "Rainbow"
        task.spawn(function()
            local hue = (Theme.violet:ToHSV())
            local history = themeHistory
            table.clear(history); table.insert(history, table.clone(Theme))
            local known = knownColors(history)
            local watch = {}
            local function watchInstance(o)
                if keepColor(o) then return end
                if o:IsA("GuiObject") then
                    watch[#watch + 1] = {o, "BackgroundColor3"}
                    if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
                        watch[#watch + 1] = {o, "TextColor3"}
                        if o:IsA("TextBox") then watch[#watch + 1] = {o, "PlaceholderColor3"} end
                    elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then
                        watch[#watch + 1] = {o, "ImageColor3"}
                    end
                elseif o:IsA("UIStroke") then
                    watch[#watch + 1] = {o, "Color"}
                elseif o:IsA("UIGradient") then
                    watch[#watch + 1] = {o, "Gradient"}
                end
            end
            for _, o in screenGui:GetDescendants() do watchInstance(o) end
            local added = screenGui.DescendantAdded:Connect(function(o) task.defer(function() if o.Parent then watchInstance(o) end end) end)
            local ticks, lastFast, lastLava, lastFull = 0, 0, 0, os.clock()
            while token == rainbowToken and not state.destroyed do
                local now = os.clock()
                local palette = tintPalette({hue = hue, sat = RainbowTint.sat, value = RainbowTint.value})
                for i = #watch, 1, -1 do
                    local item = watch[i]
                    local o, prop = item[1], item[2]
                    if not o.Parent then
                        watch[i] = watch[#watch]; watch[#watch] = nil
                    elseif prop == "Gradient" then
                        local keys, changed = {}, false
                        for j, point in o.Color.Keypoints do
                            local key = known[colorKey(point.Value)]
                            if key then changed = true end
                            keys[j] = ColorSequenceKeypoint.new(point.Time, if key then palette[key] else point.Value)
                        end
                        if changed then o.Color = ColorSequence.new(keys) end
                    else
                        local key = known[colorKey(o[prop])]
                        if key then o[prop] = palette[key] end
                    end
                end
                applyPalette(palette, {})
                table.insert(history, palette)
                for _, role in ThemeRoles do known[colorKey(palette[role.key])] = role.key end
                ticks += 1
                if #history > 60 then table.remove(history, 1) end
                if ticks % 60 == 0 then known = knownColors(history) end
                if now - lastFast > 0.3 and Resize.recolorMaterialFast then
                    lastFast = now
                    -- the lava strips (the costly part) re-tint about once a second, one strip per frame
                    local withLava = now - lastLava > 1
                    if withLava then lastLava = now end
                    pcall(Resize.recolorMaterialFast, function(c)
                        local key = known[colorKey(c)]
                        return if key then palette[key] else c
                    end, withLava)
                end
                if now - lastFull > 6 and Resize.recolorMaterial then lastFull = now; pcall(Resize.recolorMaterial) end
                hue = (hue + 0.004) % 1
                task.wait(0.1)
            end
            added:Disconnect()
        end)
        return self
    end
    local palettes = {Theme}
    for _, palette in themeHistory do table.insert(palettes, palette) end
    table.clear(themeHistory)
    applyPalette(themePalette(theme), scanThemed(knownColors(palettes)))
    if Resize.recolorMaterial then pcall(Resize.recolorMaterial) end
    self.Theme = if typeof(theme) == "string" and ThemeTints[theme] then theme elseif typeof(theme) == "table" then "Custom" else "Default"
    return self
end
local THEME_FILE = "Mercury/Theme.txt"
local function savedTheme(): string?
    local ok, value = pcall(function()
        if typeof(executorEnv.isfile) == "function" and executorEnv.isfile(THEME_FILE) then return executorEnv.readfile(THEME_FILE) end
        return nil
    end)
    if ok and typeof(value) == "string" and table.find(ThemeOrder, value) then return value end
    return nil
end
local function saveTheme(name: string)
    pcall(function()
        if typeof(executorEnv.writefile) ~= "function" then return end
        if typeof(executorEnv.isfolder) == "function" and not executorEnv.isfolder("Mercury") and typeof(executorEnv.makefolder) == "function" then executorEnv.makefolder("Mercury") end
        executorEnv.writefile(THEME_FILE, name)
    end)
end
local initialTheme = if typeof(options.Theme) == "string" and table.find(ThemeOrder, options.Theme) then options.Theme
    elseif typeof(options.Theme) == "table" then nil else savedTheme()
do
    local appearance = window.SettingsTab:CreateSection("Appearance")
    window.ThemeDropdown = appearance:CreateDropdown({
        Name = "Theme",
        Options = table.clone(ThemeOrder),
        CurrentValue = initialTheme or "Default",
        Callback = function(name)
            window:SetTheme(name)
            saveTheme(name)
        end,
    })
end
window.Attributes = {}
function window:SetAttribute(key, value) self.Attributes[key] = value; screenGui:SetAttribute(key, value); return self end
function window:GetAttribute(key) return self.Attributes[key] end
function window:SelectTab(name) return selectTab(name) end
local introState = {notifications = {}, loaded = false} -- notifications sent while the intro plays
function window:Notify(config)
    assert(typeof(config) == "table", "Notify needs an options table")
    if Resize.intro then table.insert(introState.notifications, config); return end
    -- optional status badge: Type = "Success" | "Error" (Flag is accepted as an alias)
    showToast(config.Title or "", config.Content or "", config.Duration, config.Type or config.Flag)
end
function window:SetFooter(text) panel:FindFirstChild("Credit").Text = tostring(text) end
function window:SetTitle(text) header:FindFirstChild("Title").Text = tostring(text) end
function window:Minimize() Resize.setMinimized(true) end
function window:Unminimize() Resize.setMinimized(false) end
function window:Close() close() end
function window:Destroy() shutdown() end
window.Unload = window.Destroy
biolinkButton.Visible = options.FooterButtonText ~= false
track(biolinkButton.MouseButton1Click:Connect(function()
    if typeof(options.FooterButtonCallback) == "function" then
        safeCall(options.FooterButtonCallback)
        return
    end
    local link = if typeof(options.FooterButtonUrl) == "string" and options.FooterButtonUrl ~= ""
        then options.FooterButtonUrl else "https://alo.ne/egowho"
    local opened = pcall(function()
        (game:GetService("GuiService") :: any):OpenBrowserWindow(link)
    end)
    local setter = executorEnv.setclipboard or executorEnv.toclipboard
    local copied = typeof(setter) == "function" and pcall(setter, link)
    local title = if opened and copied then "Opening · link copied"
        elseif opened then "Opening in browser"
        elseif copied then "Link copied"
        else "Copy not supported"
    showToast(title, (link:gsub("^https://", "")), 2.4, if copied or opened then "Success" else "Error")
end))
track(header.InputBegan:Connect(beginDrag))
track(UserInputService.InputChanged:Connect(updateDrag))
track(UserInputService.InputEnded:Connect(endDrag))
track(RunService.RenderStepped:Connect(onRenderStep))
Resize.apply(Layout.defaultSize.X, Layout.defaultSize.Y)
root.Position = UDim2.new(
    0.5, -math.round(root.Size.X.Offset * Layout.uiScale / 2) - screenGui.AbsolutePosition.X,
    0.5, -math.round(root.Size.Y.Offset * Layout.uiScale / 2) - screenGui.AbsolutePosition.Y
)
skeletonGhost.Position = root.Position
-- One window at a time: running another Mercury script closes the window that's
-- already up (same animation as its close button). Opt out with AllowMultiple = true.
do
    local registry = if typeof(executorEnv.getgenv) == "function" then executorEnv.getgenv() else _G
    if options.AllowMultiple ~= true then
        local previous = registry.__MercuryWindow
        if typeof(previous) == "table" and previous ~= window and typeof(previous.Close) == "function" then
            pcall(previous.Close, previous)
        end
        registry.__MercuryWindow = window
        track(function()
            if registry.__MercuryWindow == window then registry.__MercuryWindow = nil end
        end)
    end
end
if typeof(options.Theme) == "table" then window:SetTheme(options.Theme)
elseif initialTheme and initialTheme ~= "Default" then window:SetTheme(initialTheme) end

-- Intro --------------------------------------------------------------------------
-- Liquid pours in from the screen edges and fills a landscape window; "Mercury",
-- the window's name and a loading ring fade in; once the script has finished
-- building its UI they fade out and the window flows into its portrait size.
-- Options.Intro = false skips it; Options.Intro = {Manual = true} keeps the ring
-- up until window:FinishLoading() is called (otherwise loading is detected: no
-- new UI for a moment, plus Mercury's own start-up work).
function window:FinishLoading() introState.loaded = true; return self end
do -- scoped: CreateWindow is close to Luau's 200-local limit
local introOptions = if typeof(options.Intro) == "table" then options.Intro else {}
local introEnabled = options.Intro ~= false and Resize.liquid ~= nil and Resize.liquid.introPour ~= nil
    and Layout.performance ~= "Low"
-- flagged right away: a Notify sent straight after CreateWindow (before the
-- deferred start below) must already wait for the intro
if introEnabled then Resize.intro = true end
local function startIntro()
    local liquid = Resize.liquid
    if not introEnabled then
        open(); return
    end
    local k = Layout.uiScale
    local portrait = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
    local landscape = Vector2.new(portrait.Y, portrait.X)
    local function centerRoot()
        root.Position = UDim2.new(
            0.5, -math.round(root.Size.X.Offset * k / 2) - screenGui.AbsolutePosition.X,
            0.5, -math.round(root.Size.Y.Offset * k / 2) - screenGui.AbsolutePosition.Y)
        skeletonGhost.Position = root.Position
    end
    -- everything inside the panel except its glass stays hidden until the end
    -- (new controls created meanwhile land inside these and stay hidden too)
    local hidden = {}
    for _, child in panel:GetChildren() do
        -- (liquid pieces such as edge droplets manage their own visibility: leave them)
        if child:IsA("GuiObject") and not child:IsA("ImageLabel") and child.Visible and child ~= backdrop
            and child ~= toast and child.Name ~= "Lens" and child.Name ~= "Rim" then
            child.Visible = false
            table.insert(hidden, child)
        end
    end
    -- overlay: title, window name, loading ring
    local overlay = create("Frame", {Name = "IntroOverlay", BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), ZIndex = 40, Visible = false, Parent = root})
    passThrough(overlay)
    local TITLE_Y = math.round(landscape.Y * 0.24)
    local title = create("TextLabel", {Name = "Title", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, TITLE_Y), Size = UDim2.new(1, -40, 0, 44),
        FontFace = font(Enum.FontWeight.Bold), Text = "Mercury", TextSize = 36, -- 2x the game name
        TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1, ZIndex = 41, Parent = overlay})
    create("UIGradient", {Rotation = 90, Color = colorSeq({{0, Color3.new(1, 1, 1)}, {1, Theme.mist}}), Parent = title})
    local windowName = if typeof(options.Name) == "string" and options.Name ~= "" then options.Name else nil
    local nameLabel = create("TextLabel", {Name = "WindowName", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, TITLE_Y + 46), Size = UDim2.new(1, -40, 0, 20),
        FontFace = font(Enum.FontWeight.SemiBold), Text = windowName or "", TextSize = 15,
        TextColor3 = Theme.mistDim, TextTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd,
        Visible = windowName ~= nil, ZIndex = 41, Parent = overlay})
    local RING = 30
    local ring = create("Frame", {Name = "Loading", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, TITLE_Y + (if windowName then 92 else 70)), Size = UDim2.fromOffset(RING, RING),
        ZIndex = 41, Parent = overlay})
    corner(ring, UDim.new(0.5, 0))
    local ringTrack = create("UIStroke", {Color = Theme.mist, Thickness = 2.5, Transparency = 1, Parent = ring})
    local arcFrame = create("Frame", {Name = "Arc", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 42, Parent = ring})
    corner(arcFrame, UDim.new(0.5, 0))
    local arc = create("UIStroke", {Color = Theme.mist, Thickness = 2.5, Transparency = 1, Parent = arcFrame})
    -- a comet: bright head fading into a tail over about a third of the ring
    local arcGradient = create("UIGradient", {Transparency = numberSeq({{0, 1}, {0.5, 1}, {0.62, 0.75}, {0.9, 0.12}, {1, 0}}), Parent = arc})

    local finished = false
    local function cleanupOverlay() if overlay.Parent then overlay:Destroy() end end
    local function flushNotifications()
        local queued = table.clone(introState.notifications)
        table.clear(introState.notifications)
        for index, config in queued do
            task.delay((index - 1) * 0.35, function()
                if not state.destroyed and not state.closing then window:Notify(config) end
            end)
        end
    end
    -- anything going wrong: show the window the ordinary way
    local function fallback()
        if finished then return end
        finished = true
        pcall(liquid.introAbort)
        Resize.intro = nil; Resize.animating = false
        cleanupOverlay()
        if state.destroyed or state.closing then return end
        Resize.apply(portrait.X, portrait.Y); centerRoot()
        for _, child in hidden do if child.Parent then child.Visible = true end end
        root.Visible = true
        panelScale.Scale = k * 0.92
        backdrop.GroupTransparency = 1
        open()
        flushNotifications()
    end
    Resize.introFailed = fallback
    track(function() Resize.introFailed = nil; Resize.intro = nil end)

    Resize.intro = true
    Resize.animating = true
    root.Visible = false
    panelScale.Scale = k
    backdrop.GroupTransparency = 0
    Resize.apply(landscape.X, landscape.Y); centerRoot()

    -- quiet detection: loading counts as done once no new UI has appeared for a moment
    local lastActivity = os.clock()
    local activity = screenGui.DescendantAdded:Connect(function(item)
        if not item:IsDescendantOf(overlay) then lastActivity = os.clock() end
    end)
    track(activity)
    local function alive() return not finished and not state.destroyed and not state.closing end
    local function wait(seconds)
        local untilAt = os.clock() + seconds
        while alive() and os.clock() < untilAt do RunService.RenderStepped:Wait() end
        return alive()
    end

    task.spawn(function()
        local ok, err = pcall(function()
            RunService.RenderStepped:Wait() -- let the landscape size reach Absolute*
            if not alive() then return end
            local geo = {center = root.AbsolutePosition + root.AbsoluteSize / 2, land = root.AbsoluteSize,
                port = portrait * k, panelTL = root.AbsolutePosition}
            local landed = false
            if not liquid.introPour(geo, function()
                -- the window is fully formed: the real (landscape) panel takes over
                root.Visible = true
                overlay.Visible = true
                landed = true
            end) then fallback(); return end
            local giveUp = os.clock() + 8
            while alive() and not landed do
                if os.clock() > giveUp then fallback(); return end
                RunService.RenderStepped:Wait()
            end
            if not alive() then return end

            -- title, name, ring
            tween(title, 0.5, {TextTransparency = 0}, Enum.EasingStyle.Sine)
            if not wait(0.25) then return end
            tween(nameLabel, 0.5, {TextTransparency = 0}, Enum.EasingStyle.Sine)
            if not wait(0.25) then return end
            tween(ringTrack, 0.4, {Transparency = 0.85}); tween(arc, 0.4, {Transparency = 0})
            local spin = RunService.RenderStepped:Connect(function(dt)
                arcGradient.Rotation = (arcGradient.Rotation + dt * 400) % 360
            end)
            track(spin)
            -- wait for the script (and Mercury's own start-up work) to finish loading
            local shownAt = os.clock()
            local limit = if introOptions.Manual then 30 else 12
            while alive() do
                local now = os.clock()
                local quiet = introOptions.Manual ~= true and now - lastActivity >= 0.4 and Resize.lavaReady == true
                if now - shownAt >= 0.8 and (introState.loaded or quiet) then break end
                if now - shownAt >= limit then break end
                RunService.RenderStepped:Wait()
            end
            activity:Disconnect()
            if not alive() then spin:Disconnect(); return end

            -- fade out, then flow into the portrait window
            tween(title, 0.45, {TextTransparency = 1}); tween(nameLabel, 0.45, {TextTransparency = 1})
            tween(ringTrack, 0.45, {Transparency = 1}); tween(arc, 0.45, {Transparency = 1})
            if not wait(0.5) then spin:Disconnect(); return end
            spin:Disconnect()
            overlay.Visible = false
            local geo2 = {center = root.AbsolutePosition + root.AbsoluteSize / 2, land = root.AbsoluteSize,
                port = portrait * k, panelTL = root.AbsolutePosition}
            local done = false
            if not liquid.introMorph(geo2, function()
                -- portrait reached: the real window comes back; its glass fades in
                -- over the liquid while the liquid fades out underneath
                Resize.apply(portrait.X, portrait.Y); centerRoot()
                backdrop.GroupTransparency = 1
                tween(backdrop, 0.3, {GroupTransparency = 0}, Enum.EasingStyle.Sine)
            end, function() done = true end) then fallback(); return end
            local giveUp2 = os.clock() + 6
            while alive() and not done do
                if os.clock() > giveUp2 then fallback(); return end
                RunService.RenderStepped:Wait()
            end
            if not alive() then return end
            finished = true
            liquid.introDone()
            cleanupOverlay()
            -- the contents fade in, like after un-minimizing
            for _, child in hidden do if child.Parent then child.Visible = true end end
            local entries = collectFade(panel, panelFadeSkip)
            playFade(entries, true, 0.3)
            task.delay(0.35, function()
                if state.destroyed then return end
                Resize.intro = nil
                Resize.animating = false
                refreshCanvasRenders(entries)
                flushNotifications()
            end)
        end)
        if not ok then warn("[Mercury] intro failed: " .. tostring(err)); fallback() end
    end)
end
task.defer(function() if not state.destroyed then startIntro() end end)
end
return window
