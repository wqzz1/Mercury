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
    function object:_emit(value)
        safeCall(callback, value)
        for _, listener in listeners do safeCall(listener, value) end
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
    local headerHeight, openHeight = Layout.buttonHeight, 360
    local frame = row(container, config.Name or "ColorPicker", headerHeight)
    local button, label = glassButton(frame, config.Name or "ColorPicker", config.Name or "ColorPicker", 0, headerHeight)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Position = UDim2.fromOffset(20, 0)
    label.Size = UDim2.new(1, -160, 1, 0)
    local hexValue = create("TextLabel", {Name = "HexValue", BackgroundTransparency = 1,
        Position = UDim2.new(1, -126, 0, 0), Size = UDim2.fromOffset(70, headerHeight),
        FontFace = font(Enum.FontWeight.SemiBold), TextSize = 12, TextColor3 = Theme.mistDim,
        TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5, Parent = button})
    local swatch = create("Frame", {Name = "Swatch", BorderSizePixel = 0,
        Position = UDim2.new(1, -50, 0.5, -11), Size = UDim2.fromOffset(22, 22),
        BackgroundColor3 = config.CurrentValue or Color3.new(1, 1, 1), ZIndex = 5, Parent = button})
    corner(swatch, UDim.new(0.5, 0)); specularRim(swatch, 1.5, 0.08)
    local chevron = create("TextLabel", {Name = "Chevron", BackgroundTransparency = 1,
        Position = UDim2.new(1, -24, 0, 0), Size = UDim2.fromOffset(16, headerHeight),
        FontFace = font(Enum.FontWeight.SemiBold), Text = "⌄", TextSize = 17,
        TextColor3 = Theme.mistDim, ZIndex = 5, Parent = button})
    local fields = create("Frame", {Name = "PickerFields", BackgroundColor3 = Theme.tint,
        BackgroundTransparency = 0.08, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, headerHeight + 8),
        Size = UDim2.new(1, -Layout.padX * 2, 0, 310),
        Visible = false, ZIndex = 3, Parent = frame})
    corner(fields, 12); specularRim(fields)
    create("UISizeConstraint", {MaxSize = Vector2.new(270, 310), Parent = fields})
    local content = create("Frame", {BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 1, -12),
        ZIndex = 3, Parent = fields})
    local shade = create("Frame", {Name = "Shade", BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 158), ZIndex = 3, Parent = content})
    corner(shade, 14); specularRim(shade, 1, 0.5)
    local white = create("Frame", {BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = shade})
    corner(white, 14)
    create("UIGradient", {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}), Parent = white})
    local black = create("Frame", {BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = shade})
    corner(black, 14)
    create("UIGradient", {Rotation = 90, Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)}), Parent = black})
    local shadeHit = create("TextButton", {Name = "ShadeInput", Text = "", BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = shade})
    local shadeKnob = create("Frame", {Name = "ShadeKnob", AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0, ZIndex = 7, Parent = shade})
    corner(shadeKnob, UDim.new(0.5, 0))
    create("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 2.5, Parent = shadeKnob})
    local function caption(name, y)
        return create("TextLabel", {Name = name .. "Label", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 13),
            FontFace = font(Enum.FontWeight.SemiBold), Text = name, TextSize = 10,
            TextColor3 = Theme.mistDim, TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 4, Parent = content})
    end
    local function track(name, y)
        caption(name, y)
        local bar = create("Frame", {Name = name .. "Track", BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, y + 20), Size = UDim2.new(1, 0, 0, 14),
            ZIndex = 4, Parent = content})
        corner(bar, UDim.new(0.5, 0)); specularRim(bar, 1, 0.5)
        local hit = create("TextButton", {Name = "Input", Text = "", BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = bar})
        local knob = create("Frame", {Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6, Parent = bar})
        corner(knob, UDim.new(0.5, 0))
        create("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = 2.5, Parent = knob})
        return bar, hit, knob
    end
    local hueBar, hueHit, hueKnob = track("HUE", 174)
    create("UIGradient", {Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(1/6, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(2/6, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(3/6, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(4/6, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(5/6, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
    }), Parent = hueBar})
    local brightBar, brightHit, brightKnob = track("BRIGHTNESS", 219)
    local brightGradient = create("UIGradient", {Parent = brightBar})
    caption("HEX", 267)
    local hexHolder = create("Frame", {Name = "HexField", BackgroundColor3 = Theme.tint,
        BackgroundTransparency = 0.35, BorderSizePixel = 0,
        Position = UDim2.fromOffset(38, 260), Size = UDim2.new(1, -38, 0, 38),
        ZIndex = 4, Parent = content})
    corner(hexHolder, UDim.new(0.5, 0)); specularRim(hexHolder, 1, 0.5)
    create("TextLabel", {BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0),
        Size = UDim2.fromOffset(12, 38), FontFace = font(Enum.FontWeight.SemiBold),
        Text = "#", TextSize = 15, TextColor3 = Theme.mistDim, ZIndex = 5, Parent = hexHolder})
    local hexBox = create("TextBox", {Name = "HexInput", BackgroundTransparency = 1,
        Position = UDim2.fromOffset(27, 0), Size = UDim2.new(1, -38, 1, 0),
        FontFace = font(Enum.FontWeight.SemiBold), Text = "", PlaceholderText = "RRGGBB",
        TextSize = 14, TextColor3 = Theme.mist, PlaceholderColor3 = Theme.mistDim,
        TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        ZIndex = 5, Parent = hexHolder})
    local obj = controlBase("ColorPicker", frame, swatch.BackgroundColor3, config.Callback, config.Flag)
    local hue, saturation, shadeValue = obj.Value:ToHSV()
    local brightness = 0
    local editingHex = false
    local function hexOf(color)
        return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
    end
    local function baseColor()
        return Color3.fromHSV(hue, saturation, shadeValue)
    end
    local function mixedColor()
        local base = baseColor()
        local target = if brightness < 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
        return base:Lerp(target, math.abs(brightness))
    end
    local function render()
        local base = baseColor()
        local color = mixedColor()
        shade.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        shadeKnob.BackgroundColor3 = base
        shadeKnob.Position = UDim2.fromScale(saturation, 1 - shadeValue)
        hueKnob.Position = UDim2.fromScale(hue, 0.5)
        brightKnob.Position = UDim2.fromScale((brightness + 1) / 2, 0.5)
        brightGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(0.5, base),
            ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
        })
        swatch.BackgroundColor3 = color
        hexValue.Text = hexOf(color)
        if not editingHex then hexBox.Text = string.sub(hexValue.Text, 2) end
    end
    local function updateColor()
        local color = mixedColor()
        if color == obj.Value then render(); return end
        obj.Value = color
        render()
        obj:_emit(color)
    end
    function obj:Set(value, silent)
        assert(typeof(value) == "Color3", "ColorPicker:Set expects Color3")
        local newHue, newSaturation, newValue = value:ToHSV()
        if newSaturation > 0 and newValue > 0 then hue = newHue end
        saturation, shadeValue, brightness = newSaturation, newValue, 0
        local changed = self.Value ~= value
        self.Value = value
        render()
        if changed and not silent then self:_emit(value) end
        return self
    end
    obj:Set(obj.Value, true)
    local dragging = nil
    local function fromPointer(kind, pointer)
        if obj.Disabled then return end
        if kind == "shade" then
            local pos, size = shade.AbsolutePosition, shade.AbsoluteSize
            saturation = math.clamp((pointer.X - pos.X) / math.max(1, size.X), 0, 1)
            shadeValue = 1 - math.clamp((pointer.Y - pos.Y) / math.max(1, size.Y), 0, 1)
        else
            local bar = if kind == "hue" then hueBar else brightBar
            local fraction = math.clamp((pointer.X - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1)
            if kind == "hue" then hue = fraction else
                brightness = fraction * 2 - 1
                if math.abs(brightness) < 0.04 then brightness = 0 end
            end
        end
        updateColor()
    end
    for _, part in {{shadeHit, "shade"}, {hueHit, "hue"}, {brightHit, "brightness"}} do
        obj:Bind(part[1].InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = part[2]
                fromPointer(dragging, input.Position)
            end
        end))
    end
    obj:Bind(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            fromPointer(dragging, input.Position)
        end
    end))
    obj:Bind(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = nil end
    end))
    obj:Bind(hexBox.Focused:Connect(function()
        editingHex = true
    end))
    obj:Bind(hexBox:GetPropertyChangedSignal("Text"):Connect(function()
        if not editingHex then return end
        local cleaned = string.upper(string.gsub(hexBox.Text, "[^%x]", "")):sub(1, 6)
        if cleaned ~= hexBox.Text then hexBox.Text = cleaned end
        if #cleaned == 6 then
            local r = tonumber(cleaned:sub(1, 2), 16)
            local g = tonumber(cleaned:sub(3, 4), 16)
            local b = tonumber(cleaned:sub(5, 6), 16)
            obj:Set(Color3.fromRGB(r, g, b))
        end
    end))
    obj:Bind(hexBox.FocusLost:Connect(function()
        if #hexBox.Text == 3 then
            local t = hexBox.Text
            obj:Set(Color3.fromRGB(tonumber(t:sub(1, 1) .. t:sub(1, 1), 16),
                tonumber(t:sub(2, 2) .. t:sub(2, 2), 16), tonumber(t:sub(3, 3) .. t:sub(3, 3), 16)))
        end
        editingHex = false
        render()
    end))
    obj:Bind(button.MouseButton1Click:Connect(function()
        if obj.Disabled then return end
        fields.Visible = not fields.Visible
        chevron.Rotation = if fields.Visible then 180 else 0
        frame.Size = UDim2.new(1, 0, 0, if fields.Visible then openHeight else headerHeight)
    end))
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
    function tab:CreateSection(title)
        local section = {Name = title}
        local holder = row(self.content, title, 0)
        holder.AutomaticSize = Enum.AutomaticSize.Y
        create("TextLabel", {Name = "Heading", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(Layout.padX, 0), Size = UDim2.new(1, -Layout.padX * 2, 0, 20),
            FontFace = font(Enum.FontWeight.SemiBold), Text = string.upper(title),
            TextColor3 = Theme.mistDim, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Parent = holder})
        local content = create("Frame", {Name = "Items", BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, Parent = holder})
        create("UIListLayout", {Padding = UDim.new(0, Layout.itemGap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content})
        create("UIPadding", {PaddingBottom = UDim.new(0, 20), Parent = holder})
        section.Instance = holder
        installFactories(section, content)
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
window.Attributes = {}
function window:SetAttribute(key, value) self.Attributes[key] = value; screenGui:SetAttribute(key, value); return self end
function window:GetAttribute(key) return self.Attributes[key] end
function window:SelectTab(name) return selectTab(name) end
function window:Notify(config)
    assert(typeof(config) == "table", "Notify needs an options table")
    showToast(config.Title or "", config.Content or "", config.Duration)
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
    showToast(title, link:gsub("^https://", ""), 2.4)
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
task.defer(function() if not state.destroyed then open() end end)
return window
