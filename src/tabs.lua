-- Tabs retain the existing sliding pages and segmented-control animations.
local tabs = {}
local tabByName = {}
local function layoutTabs()
    local count = #tabs
    if count == 0 then return end
    local share = 1 / count
    for _, item in tabs do
        local i, button, label, platter = item.index, item.parts.button, item.parts.label, item.parts.platter
        button.Position = UDim2.new(share * (i - 1), 0, 0, 0)
        button.Size = UDim2.new(share, 0, 1, 0)
        label.Position = UDim2.new(share * (i - 0.5), 0, 0, if item.parts.icon then 33 else Layout.tabsHeight / 2)
        label.Size = UDim2.new(share, -10, 0, 16)
        platter.Position = UDim2.new(share * (i - 1), if i == 1 then 3 else 1, 0, 3)
        platter.Size = UDim2.new(share, -4, 1, -6)
        if item.parts.icon then item.parts.icon.Position = UDim2.new(share * (i - 0.5), 0, 0, 8) end
    end
end
local function makeIcon(parent, name, size)
    local data = LUCIDE[name]
    if not data then return nil end
    return create("ImageLabel", {
        Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
        Size = UDim2.fromOffset(size, size),
        Image = "rbxassetid://" .. tostring(data[1]), ImageRectSize = Vector2.new(data[2], data[3]),
        ImageRectOffset = Vector2.new(data[4], data[5]), ImageColor3 = Color3.new(1, 1, 1),
        ZIndex = 5, Parent = parent,
    })
end

local function selectTab(name: string, instant: boolean?)
    local nextTab = tabByName[name]
    if not nextTab or state.destroyed then return false end
    if state.currentTab == name and not instant then return true end
    state.currentTab = name
    local count, active = #tabs, nextTab.index
    local share = 1 / count
    styleTo(tabIndicator, 0.4, {
        Position = UDim2.new(share * (active - 1), if active == 1 then 3 else 1, 0, 3),
        Size = UDim2.new(share, -4, 1, -6),
    }, instant, Enum.EasingStyle.Back)
    for _, tab in tabs do
        styleTo(tab.parts.label, 0.2, {TextColor3 = if tab.index == active then Theme.mist else Theme.mistDim}, instant)
        if tab.index == active then styleTo(tab.parts.platter, 0.2, {BackgroundTransparency = 1}, instant) end
        styleTo(tab.page, 0.42, {Position = UDim2.new(tab.index - active, 0, 0, 8)}, instant)
    end
    return true
end

local function addTab(name: string, icon: string?)
    assert(typeof(name) == "string" and name ~= "", "Tab name must be a nonempty string")
    assert(not tabByName[name], "Duplicate tab: " .. name)
    local insertBeforeSettings = name ~= "Settings" and tabByName.Settings ~= nil
    local firstCustomTab = insertBeforeSettings and #tabs == 1
    local index = if insertBeforeSettings then #tabs else #tabs + 1
    Layout.tabCount = #tabs + 1
    local parts = createTab(name, index)
    if icon then
        local image = makeIcon(tabBar, icon, 13)
        if image then
            parts.icon = image
        end
    end
    local page = createPage(name .. "Page", index - 1)
    ScrollHints.attach(page, pageViewport, true)
    local content = create("Frame", {
        Name = "Content", BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Parent = page,
    })
    create("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12), Parent = content})
    create("UIListLayout", {Padding = UDim.new(0, Layout.itemGap), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content})
    local tab = {Name = name, Icon = icon, index = index, parts = parts, page = page, content = content}
    table.insert(tabs, index, tab)
    tabByName[name] = tab
    for i, item in tabs do item.index = i end
    track(parts.button.MouseButton1Click:Connect(function() selectTab(name) end))
    layoutTabs()
    selectTab(if firstCustomTab then name else (state.currentTab or name), true)
    return tab
end
