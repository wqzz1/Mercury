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
local function controlBase(kind, frame, default, callback, flag)
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
    local frame = row(container, config.Name or "Dropdown", Layout.buttonHeight)
    local button, label = glassButton(frame, config.Name or "Dropdown", config.Name or "Dropdown", 0, Layout.buttonHeight)
    local list = create("Frame", {Name = "Options", BackgroundColor3 = Theme.tint, BackgroundTransparency = 0.08,
        BorderSizePixel = 0, Position = UDim2.fromOffset(Layout.padX, Layout.buttonHeight + 2),
        Size = UDim2.new(1, -Layout.padX * 2, 0, 0), Visible = false, ZIndex = 10, Parent = frame})
    corner(list, 12); specularRim(list)
    create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
    local obj = controlBase("Dropdown", frame, nil, config.Callback, config.Flag)
    function obj:Set(value, silent)
        local found = false
        for _, choice in choices do if choice == value then found = true; break end end
        assert(found, "Dropdown value is not in Options")
        self.Value = value
        label.Text = (config.Name or "Dropdown") .. ": " .. tostring(value)
        list.Visible = false; frame.Size = UDim2.new(1, 0, 0, Layout.buttonHeight)
        if not silent then self:_emit(value) end
        return self
    end
    function obj:Refresh(newChoices)
        assert(typeof(newChoices) == "table", "Refresh needs an array")
        choices = newChoices
        for _, child in list:GetChildren() do if child:IsA("GuiButton") then child:Destroy() end end
        for _, choice in choices do
            local option = create("TextButton", {BackgroundColor3 = Theme.mist, BackgroundTransparency = 0.94,
                BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 28), Text = tostring(choice),
                TextColor3 = Theme.mist, TextSize = 12, FontFace = font(), ZIndex = 11, Parent = list})
            self:Bind(option.MouseButton1Click:Connect(function() if not self.Disabled then self:Set(choice) end end))
        end
        list.Size = UDim2.new(1, -Layout.padX * 2, 0, #choices * 28)
        return self
    end
    obj:Refresh(choices)
    obj:Bind(button.MouseButton1Click:Connect(function()
        if obj.Disabled then return end
        list.Visible = not list.Visible
        frame.Size = UDim2.new(1, 0, 0, Layout.buttonHeight + (if list.Visible then #choices * 28 + 2 else 0))
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
    local SHADE_Y, SHADE_H = 2, 160
    local COL_GAP, SIDE_GAP = 12, 14
    local SLIDERS_W = SIDE_GAP + TRACK_W * 3 + COL_GAP * 2
    local TRACK_LEN = SHADE_H - 20          -- room for the caption under each track
    local HEX_Y, HEX_H = SHADE_Y + SHADE_H + 12, 36
    local CAPTION = Layout.captionTextSize or 12
    local bodyHeight = HEX_Y + HEX_H + 14
    local openHeight = headerHeight + bodyHeight
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
    local chevron = create("Frame", {Name = "Chevron", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, -26, 0.5, 0), Size = UDim2.fromOffset(12, 12), ZIndex = 5, Parent = header})
    for _, side in {-1, 1} do
        local bar = create("Frame", {BackgroundColor3 = Theme.mistDim, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, side * 2.4, 0.5, 0),
            Size = UDim2.fromOffset(2, 8), Rotation = -side * 45, ZIndex = 5, Parent = chevron})
        corner(bar, UDim.new(0.5, 0))
    end

    -- Body ------------------------------------------------------------------
    local body = create("Frame", {Name = "Body", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(INSET, headerHeight), Size = UDim2.new(1, -INSET * 2, 0, bodyHeight),
        Visible = false, ZIndex = 3, Parent = card})

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
    local openToken = 0
    function obj:SetOpen(open)
        open = open == true
        if open == self.Open then return self end
        self.Open = open
        openToken += 1
        local token = openToken
        local height = if open then openHeight else headerHeight
        if open then body.Visible = true end
        tween(frame, 0.32, {Size = UDim2.new(1, 0, 0, height)}, Enum.EasingStyle.Quint)
        tween(card, 0.32, {Size = UDim2.new(1, -Layout.padX * 2, 0, height)}, Enum.EasingStyle.Quint)
        tween(chevron, 0.25, {Rotation = if open then 180 else 0}, Enum.EasingStyle.Quint)
        if not open then
            task.delay(0.33, function()
                if token == openToken and body.Parent then body.Visible = false end
            end)
        end
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

    obj:Bind(header.MouseEnter:Connect(function() tween(card, 0.2, {BackgroundTransparency = 0.9}) end))
    obj:Bind(header.MouseLeave:Connect(function() tween(card, 0.25, {BackgroundTransparency = 0.94}) end))
    obj:Bind(header.MouseButton1Click:Connect(function()
        if not obj.Disabled then obj:Toggle() end
    end))
    if config.Open == true then obj:SetOpen(true) end
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
        holder.AutomaticSize = Enum.AutomaticSize.Y
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
        task.spawn(function()
            local glintRng = Random.new()
            task.wait(glintRng:NextNumber(0.4, 1.2))
            while holder.Parent and not state.destroyed do
                glint.Offset = Vector2.new(-1.2, 0)
                tween(glint, 2.4, {Offset = Vector2.new(1.2, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
                task.wait(2.4 + glintRng:NextNumber(3, 5))
            end
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
        local content = create("Frame", {Name = "Items", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, HEAD_H + 6), Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, Parent = holder})
        create("UIListLayout", {Padding = UDim.new(0, Layout.itemGap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content})
        local padding = create("UIPadding", {PaddingBottom = UDim.new(0, 20), Parent = holder})
        section.Instance = holder
        installFactories(section, content)

        -- Click the heading to collapse/expand the section (instant for now, like
        -- the dropdown; to be replaced with a liquid animation later).
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
        function section:SetCollapsed(collapsed)
            collapsed = collapsed == true
            if collapsed == self.Collapsed then return self end
            self.Collapsed = collapsed
            content.Visible = not collapsed
            padding.PaddingBottom = UDim.new(0, if collapsed then 10 else 20)
            chevron.Rotation = if collapsed then -90 else 0
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
        if typeof(sectionOptions) == "table" and sectionOptions.Collapsed == true then section:SetCollapsed(true) end

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
    task.spawn(function()
        local rng = Random.new()
        task.wait(rng:NextNumber(0.8, 1.6))
        while gameTitle.Parent and not state.destroyed do
            fraction = math.clamp(gameTitle.TextBounds.X / math.max(1, gameTitle.AbsoluteSize.X), 0.05, 1)
            titleGlint.Color = colors()
            titleGlint.Offset = Vector2.new(-0.7 * fraction, 0)
            tween(titleGlint, 2.4, {Offset = Vector2.new(1.0 * fraction, 0)}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
            task.wait(2.4 + rng:NextNumber(3, 5))
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
function window:Notify(config)
    assert(typeof(config) == "table", "Notify needs an options table")
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
task.defer(function() if not state.destroyed then open() end end)
return window
