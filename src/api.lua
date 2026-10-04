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
    local frame = row(container, config.Name or "ColorPicker", Layout.buttonHeight)
    local button, label = glassButton(frame, config.Name or "ColorPicker", config.Name or "ColorPicker", 0, Layout.buttonHeight)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Position = UDim2.fromOffset(20, 0)
    label.Size = UDim2.new(1, -115, 1, 0)
    local swatch = create("Frame", {Name = "Swatch", BorderSizePixel = 0,
        Position = UDim2.new(1, -48, 0.5, -12), Size = UDim2.fromOffset(28, 24),
        BackgroundColor3 = config.CurrentValue or Color3.new(1, 1, 1), ZIndex = 5, Parent = button})
    corner(swatch, 7); specularRim(swatch)
    local fields = create("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(Layout.padX, Layout.buttonHeight),
        Size = UDim2.new(1, -Layout.padX * 2, 0, 32), Visible = false, Parent = frame})
    local boxes = {}
    for i, name in {"R", "G", "B"} do
        boxes[i] = create("TextBox", {Name = name, BackgroundColor3 = Theme.mist,
            BackgroundTransparency = 0.88, BorderSizePixel = 0, Position = UDim2.new((i - 1) / 3, 2, 0, 0),
            Size = UDim2.new(1 / 3, -6, 0, 28), FontFace = font(), TextSize = 12,
            TextColor3 = Theme.mist, ZIndex = 5, Parent = fields})
        corner(boxes[i], 8)
    end
    local obj = controlBase("ColorPicker", frame, swatch.BackgroundColor3, config.Callback, config.Flag)
    function obj:Set(value, silent)
        assert(typeof(value) == "Color3", "ColorPicker:Set expects Color3")
        self.Value = value
        swatch.BackgroundColor3 = value
        boxes[1].Text = tostring(math.round(value.R * 255))
        boxes[2].Text = tostring(math.round(value.G * 255))
        boxes[3].Text = tostring(math.round(value.B * 255))
        if not silent then self:_emit(value) end
        return self
    end
    obj:Set(obj.Value, true)
    local function update()
        if obj.Disabled then return end
        local r, g, b = tonumber(boxes[1].Text), tonumber(boxes[2].Text), tonumber(boxes[3].Text)
        if r and g and b then obj:Set(Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))) end
    end
    for _, box in boxes do obj:Bind(box.FocusLost:Connect(update)) end
    obj:Bind(button.MouseButton1Click:Connect(function()
        if obj.Disabled then return end
        fields.Visible = not fields.Visible
        frame.Size = UDim2.new(1, 0, 0, Layout.buttonHeight + (if fields.Visible then 32 else 0))
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
