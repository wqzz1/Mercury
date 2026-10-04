-- header buttons and footer items sit this far in from the panel's side edges,
-- matching the header buttons' 15px gap from the top edge
local CORNER_INSET = 15
local CONTENT_Y = Layout.tabsY + Layout.tabsHeight + Layout.gap
local FOOTER_Y = CONTENT_Y + pageHeight + Layout.gap
local PANEL_WIDTH = Layout.width
local PANEL_HEIGHT = FOOTER_Y + Layout.footerHeight + Layout.bottomPad

local screenGui = track(create("ScreenGui", {
    Name = options.Name or "Mercury",
    ResetOnSpawn = false,
    -- above every game GUI (their highest is 6000; pet talk bubbles are 3)
    DisplayOrder = 2147483000,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = options.Parent or LocalPlayer:WaitForChild("PlayerGui", 10),
})) :: ScreenGui

local root: Frame = create("Frame", {
    Name = "Root",
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
    Position = UDim2.new(0.5, -math.round(PANEL_WIDTH * Layout.uiScale / 2), 0.5, -math.round(PANEL_HEIGHT * Layout.uiScale / 2)),
    Parent = screenGui,
})
local panelScale: UIScale = create("UIScale", { Scale = Layout.uiScale * 0.92, Parent = root })

local panel: Frame = create("Frame", {
    Name = "Panel",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 1,
    Parent = root,
})

-- Glass body (non-text layers only, so text never renders through a CanvasGroup)
local backdrop: CanvasGroup = create("CanvasGroup", {
    Name = "Backdrop",
    BackgroundColor3 = Theme.tint,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    GroupTransparency = 1,
    ZIndex = 0,
    Parent = panel,
})
passThrough(backdrop)
corner(backdrop, Layout.radius)

-- Liquid marble: drifting veins + soft orbs over a dark graphite/plum base.
-- Orbs are built from many thin concentric rings and veins from smooth
-- multi-key gradients, so neither shows visible banding.
local blobs, veins, lavaLayers  -- shared out of the marble backdrop block below
do -- marble backdrop (scoped to stay under Luau's 200-local limit)
local MARBLE = {
    ink = Color3.fromRGB(7, 7, 10),
    graphite = Color3.fromRGB(22, 21, 27),
    smoke = Color3.fromRGB(66, 63, 76),
    bruise = Color3.fromRGB(28, 20, 42),
}

local marbleBase = create("Frame", {
    Name = "Base",
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    Parent = backdrop,
})
create("UIGradient", {
    Rotation = 125,
    Color = colorSeq({{0, MARBLE.ink}, {0.4, MARBLE.graphite}, {0.7, MARBLE.bruise}, {1, MARBLE.ink}}),
    Parent = marbleBase,
})

-- Smoothstep falloff sampled into 15 keys (NumberSequence caps at 20).
local function smoothBand(width: number, alpha: number): NumberSequence
    local points = { {0, 1} }
    local steps = Quality.veinSteps
    for side = -1, 1, 2 do
        for step = 0, steps do
            local t = step / steps                 -- 0 = edge, 1 = centre
            local eased = t * t * (3 - 2 * t)
            local x = 0.5 + side * width * (1 - t)
            if side == 1 then
                x = 0.5 + width * t
                eased = (1 - t) * (1 - t) * (3 - 2 * (1 - t))
            end
            if not (side == 1 and step == 0) then
                table.insert(points, { math.clamp(x, 0.001, 0.999), 1 - alpha * eased })
            end
        end
    end
    table.insert(points, {1, 1})
    table.sort(points, function(a, b)
        return a[1] < b[1]
    end)
    return numberSeq(points)
end

blobs = {}
local function addOrb(color: Color3, size: number, peak: number, center: Vector2, radius: Vector2, speed: number, phase: number)
    local holder: Frame = create("Frame", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        Position = UDim2.fromScale(center.X, center.Y),
        Parent = backdrop,
    })
    -- per-ring alpha so the stacked centre reaches `peak`
    local ringAlpha = 1 - (1 - peak) ^ (1 / Quality.orbRings)
    for index = 1, Quality.orbRings do
        local scale = 1 - (index - 1) / Quality.orbRings * 0.92
        local ring = create("Frame", {
            BackgroundColor3 = color,
            BackgroundTransparency = 1 - ringAlpha,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(scale, scale),
            Parent = holder,
        })
        corner(ring, UDim.new(0.5, 0))
    end
    table.insert(blobs, { frame = holder, center = center, radius = radius, speed = speed, phase = phase })
end
addOrb(Theme.violet, 230, 0.42, Vector2.new(0.85, 0.15), Vector2.new(0.10, 0.08), 0.35, 0)
addOrb(Theme.plum, 260, 0.55, Vector2.new(0.10, 0.90), Vector2.new(0.08, 0.06), 0.28, 2.1)
addOrb(Theme.lilac, 140, 0.20, Vector2.new(0.30, 0.35), Vector2.new(0.12, 0.10), 0.45, 4.0)

type Vein = {
    frame: Frame,
    gradient: UIGradient,
    base: number,
    swing: number,
    speed: number,
    drift: number,
    phase: number,
}
veins = {}
local function addVein(color: Color3, width: number, alpha: number, rotation: number, swing: number, speed: number, drift: number, phase: number)
    local frame: Frame = create("Frame", {
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(2.6, 2.6),
        Rotation = rotation,
        Parent = backdrop,
    })
    local gradient: UIGradient = create("UIGradient", { Transparency = smoothBand(width, alpha), Parent = frame })
    table.insert(veins, {
        frame = frame, gradient = gradient, base = rotation, swing = swing,
        speed = speed, drift = drift, phase = phase,
    })
end
-- broad liquid bodies
addVein(Theme.violet, 0.16, 0.30, 35, 14, 0.22, 0.10, 0)
addVein(MARBLE.ink, 0.10, 0.55, -20, 18, 0.18, 0.12, 1.7)
addVein(MARBLE.smoke, 0.06, 0.25, 70, 10, 0.26, 0.08, 3.3)

-- Marble lava: two copies of a seamless domain-warped texture (soft molten
-- pools + thin marble veins) creeping slowly in different directions.
type LavaLayer = { label: ImageLabel, origin: Vector2, velocity: Vector2, phase: number }
lavaLayers = {}
local lavaAsset = loadEmbeddedImage("marble-lava.png", EmbeddedPng.lava)
if lavaAsset then
    local panelAspect = Layout.width / PANEL_HEIGHT
    local rectSize = Vector2.new(Lava.window * panelAspect, Lava.window)
    for index, layer in Lava.layers do
        local label: ImageLabel = create("ImageLabel", {
            Name = "MarbleLava" .. index,
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Image = lavaAsset,
            ImageColor3 = layer.color,
            ImageTransparency = layer.transparency,
            ScaleType = Enum.ScaleType.Stretch,
            ImageRectSize = rectSize,
            Parent = backdrop,
        })
        table.insert(lavaLayers, {
            label = label,
            origin = layer.origin,
            velocity = layer.velocity,
            phase = index * 2.3,
        })
    end
end

local topGloss = create("Frame", {
    BackgroundColor3 = Theme.spec,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 0.46),
    Parent = backdrop,
})
create("UIGradient", { Rotation = 90, Transparency = numberSeq({{0, 0.96}, {0.6, 0.99}, {1, 1}}), Parent = topGloss })

local vignette = create("Frame", {
    BackgroundColor3 = MARBLE.ink,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0, 0.55),
    Size = UDim2.fromScale(1, 0.45),
    Parent = backdrop,
})
create("UIGradient", { Rotation = 90, Transparency = numberSeq({{0, 1}, {1, 0.5}}), Parent = vignette })

-- Lensing band just inside the edge
local lens: Frame = create("Frame", {
    Name = "Lens",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(5, 5),
    Size = UDim2.new(1, -10, 1, -10),
    ZIndex = 1,
    Parent = panel,
})
passThrough(lens)
corner(lens, Layout.radius - 5)
local lensStroke = create("UIStroke", { Color = Theme.lilac, Thickness = 4, Parent = lens })
create("UIGradient", {
    Rotation = 90,
    Transparency = numberSeq({{0, 0.92}, {0.5, 0.985}, {1, 0.9}}),
    Parent = lensStroke,
})

local rim: Frame = create("Frame", {
    Name = "Rim",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 6,
    Parent = panel,
})
passThrough(rim)
corner(rim, Layout.radius)
specularRim(rim, 1.5, 0.08)
end

-- Header ---------------------------------------------------------------------
local header: Frame = create("Frame", {
    Name = "DragHeader",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, Layout.tabsY - 4),
    ZIndex = 2,
    Parent = panel,
})

local logo: Frame = create("Frame", {
    BackgroundColor3 = Theme.mist,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(CORNER_INSET + 7, 22), -- centre mirrors the close button's (27px in)
    Size = UDim2.fromOffset(10, 10),
    ZIndex = 2,
    Parent = header,
})
corner(logo, UDim.new(0.5, 0))
local logoGradient: UIGradient = create("UIGradient", {
    Color = colorSeq({{0, Theme.mist}, {0.5, Theme.lilac}, {1, Theme.violet}}),
    Parent = logo,
})

local gameTitle: TextLabel = create("TextLabel", {
    Name = "Title",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(CORNER_INSET + 28, 16),
    Size = UDim2.new(1, -150, 0, 22),
    FontFace = font(Enum.FontWeight.Bold),
    Text = "Loading game…",
    TextTruncate = Enum.TextTruncate.AtEnd,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Theme.mist,
    ZIndex = 2,
    Parent = header,
})

task.spawn(function()
    local ok, info = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId, Enum.InfoType.Asset)
    end)
    if gameTitle.Parent then
        gameTitle.Text = if ok and typeof(info) == "table" and typeof(info.Name) == "string"
            then info.Name else (game.Name ~= "" and game.Name or "Place " .. tostring(game.PlaceId))
    end
end)

local closeButton: TextButton = create("TextButton", {
    Name = "Close",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(24, 24),
    Position = UDim2.new(1, -CORNER_INSET - 12, 0, 27), -- 15px from the top (27-12) and from the right
    BackgroundColor3 = Theme.mist,
    BackgroundTransparency = 0.93,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    Text = "",
    ZIndex = 3,
    Parent = header,
})
corner(closeButton, UDim.new(0.5, 0))
specularRim(closeButton)
attachHoverScale(closeButton)

do
    -- Header icons are drawn from rounded bars centred on the button, not
    -- font glyphs: the "×" glyph sat off-centre (fonts add side bearing).
    local function iconBar(parent: GuiObject, width: number, rotation: number)
        local bar = create("Frame", {
            Name = "IconBar",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(width, 2),
            Rotation = rotation,
            BackgroundColor3 = Theme.mist,
            BorderSizePixel = 0,
            ZIndex = 4,
            Parent = parent,
        })
        passThrough(bar)
        corner(bar, UDim.new(0.5, 0))
    end
    iconBar(closeButton, 11, 45)
    iconBar(closeButton, 11, -45)

    -- Minimize: same glass pill, just left of Close, with a dash.
    local minimizeButton: TextButton = create("TextButton", {
        Name = "Minimize",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(24, 24),
        Position = UDim2.new(1, -CORNER_INSET - 12 - 24 - 8, 0, 27),
        BackgroundColor3 = Theme.mist,
        BackgroundTransparency = 0.93,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        Text = "",
        ZIndex = 3,
        Parent = header,
    })
    corner(minimizeButton, UDim.new(0.5, 0))
    specularRim(minimizeButton)
    attachHoverScale(minimizeButton)
    iconBar(minimizeButton, 10, 0)
end

-- Tabs -----------------------------------------------------------------------
local tabBar: Frame = create("Frame", {
    Name = "Tabs",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0, Layout.tabsY + Layout.tabsHeight / 2),
    Size = UDim2.new(1, -Layout.padX * 2, 0, Layout.tabsHeight),
    BackgroundColor3 = Theme.tint,
    BackgroundTransparency = 0.5,
    BorderSizePixel = 0,
    ZIndex = 2,
    Parent = panel,
})
corner(tabBar, UDim.new(0.5, 0))
specularRim(tabBar, 1, 0.5)
liquidWave(tabBar, Layout.width - Layout.padX * 2, Layout.tabsHeight, UDim.new(0.5, 0), 1)

local tabIndicator: Frame = create("Frame", {
    Name = "Indicator",
    Position = UDim2.new(0, 3, 0, 3),
    Size = UDim2.new(1 / Layout.tabCount, -4, 1, -6),
    BackgroundColor3 = Theme.mist,
    BorderSizePixel = 0,
    ZIndex = 2,
    Parent = tabBar,
})
passThrough(tabIndicator)
corner(tabIndicator, UDim.new(0.5, 0))
create("UIGradient", {
    Color = colorSeq({{0, Theme.plum}, {0.6, Theme.violet}, {1, Theme.lilac}}),
    Transparency = numberSeq({{0, 0.3}, {1, 0.5}}),
    Parent = tabIndicator,
})
specularRim(tabIndicator, 1, 0.3)

-- Hover follows the Apple segmented-control pattern: a faint platter fades
-- in behind the inactive segment and its label brightens. Nothing scales,
-- so the text never shifts.
local function createTab(text: string, index: number, key: string?): TabParts
    local tabKey = key or text
    local share = 1 / Layout.tabCount
    local platter: Frame = create("Frame", {
        Name = tabKey .. "HoverPlatter",
        BackgroundColor3 = Theme.mist,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(share * (index - 1), if index == 1 then 3 else 1, 0, 3),
        Size = UDim2.new(share, -4, 1, -6),
        ZIndex = 1,
        Parent = tabBar,
    })
    passThrough(platter)
    corner(platter, UDim.new(0.5, 0))

    local button: TextButton = create("TextButton", {
        Name = tabKey .. "Tab",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Position = UDim2.fromScale(share * (index - 1), 0),
        Size = UDim2.fromScale(share, 1),
        Text = "",
        ZIndex = 3,
        Parent = tabBar,
    })

    -- Label sits on the tab bar itself with an explicit centre anchor and a
    -- fixed pixel height, so every name shares the same vertical position.
    -- It shrinks (never below 10px) only if the panel is resized too narrow.
    local label: TextLabel = create("TextLabel", {
        Name = tabKey .. "Label",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(share * (index - 0.5), 0, 0, 33),
        Size = UDim2.new(share, -10, 0, 16),
        FontFace = font(Enum.FontWeight.SemiBold),
        Text = text,
        TextScaled = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextColor3 = if index == 1 then Theme.mist else Theme.mistDim,
        ZIndex = 4,
        Parent = tabBar,
    })
    create("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 10, Parent = label })
    passThrough(label)

    local function isActive(): boolean
        return state.currentTab == tabKey
    end

    track(button.MouseEnter:Connect(function()
        tween(label, 0.18, { TextColor3 = Theme.mist })
        if not isActive() then
            tween(platter, 0.2, { BackgroundTransparency = 0.92 })
        end
    end))
    track(button.MouseLeave:Connect(function()
        tween(label, 0.22, { TextColor3 = if isActive() then Theme.mist else Theme.mistDim })
        tween(platter, 0.25, { BackgroundTransparency = 1 })
    end))
    track(button.MouseButton1Down:Connect(function()
        if not isActive() then
            tween(platter, 0.08, { BackgroundTransparency = 0.86 })
        end
    end))

    return { button = button, label = label, platter = platter }
end
-- Pages slide inside a clipping viewport (with headroom for hover growth)
local pageViewport: Frame = create("Frame", {
    Name = "Pages",
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Position = UDim2.fromOffset(0, CONTENT_Y - 8),
    -- top-anchored, bottom kept a fixed distance above the footer, so a taller
    -- (resized) panel just shows more of the scrolling page
    Size = UDim2.new(1, 0, 1, pageHeight + 16 - PANEL_HEIGHT),
    ZIndex = 2,
    Parent = panel,
})

-- Pages are ScrollingFrames: the panel keeps its size and anything taller
-- than the page area scrolls (mouse wheel, drag, or the thin scrollbar).
local function createPage(name: string, offsetScale: number): ScrollingFrame
    local page: ScrollingFrame = create("ScrollingFrame", {
        Name = name,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(offsetScale, 0, 0, 8),
        Size = UDim2.new(1, 0, 1, -8),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.mist,
        ScrollBarImageTransparency = 0.6,
        VerticalScrollBarInset = Enum.ScrollBarInset.None,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ZIndex = 2,
        Parent = pageViewport,
    })
    -- breathing room top and bottom: the first row's rim is never clipped by
    -- the scroll edge and the last control is never flush with it
    create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12), Parent = page })
    return page
end
-- Footer pieces are pinned to the panel's bottom edge (offset from the
-- bottom = their default distance), so they ride the bottom when resized.
do
    local footerDivider = taperedDivider(panel, FOOTER_Y - Layout.gap / 2)
    local y = footerDivider.Position.Y.Offset
    -- moved down with the footer items (they now sit CORNER_INSET from the bottom)
    footerDivider.Position = UDim2.new(footerDivider.Position.X, UDim.new(1, y - PANEL_HEIGHT + Layout.bottomPad - CORNER_INSET))
end

create("TextLabel", {
    Name = "Credit",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, CORNER_INSET + 2, 1, -Layout.footerHeight / 2 - CORNER_INSET), -- same gap from the bottom as from the side
    Size = UDim2.fromOffset(150, 16),
    FontFace = font(Enum.FontWeight.Medium),
    Text = options.Footer or "made by ego",
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Theme.mistDim,
    ZIndex = 2,
    Parent = panel,
})

-- Icon + label live in a centred horizontal list, and the pill sizes itself
-- to that content with equal padding, so the group is always centred.
local biolinkButton: TextButton = create("TextButton", {
    Name = "Biolink",
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
    BackgroundColor3 = Theme.mist,
    BackgroundTransparency = 0.93,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -CORNER_INSET, 1, -Layout.footerHeight / 2 - CORNER_INSET), -- same gap from the bottom as from the side
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, Layout.footerHeight),
    ZIndex = 3,
    Parent = panel,
})
corner(biolinkButton, UDim.new(0.5, 0))
specularRim(biolinkButton)
attachHoverScale(biolinkButton)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
    Parent = biolinkButton,
})
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 7),
    Parent = biolinkButton,
})

local globeAsset = loadEmbeddedImage("lucide-globe.png", EmbeddedPng.globe)
if globeAsset then
    create("ImageLabel", {
        Name = "GlobeIcon",
        LayoutOrder = 1,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(14, 14),
        Image = globeAsset,
        ImageColor3 = Theme.mist,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 4,
        Parent = biolinkButton,
    })
else
    -- No custom-asset support: rebuild the Lucide globe from primitives.
    local globeIcon: Frame = create("Frame", {
        Name = "GlobeIcon",
        LayoutOrder = 1,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(14, 14),
        ZIndex = 4,
        Parent = biolinkButton,
    })
    local function globeStroke(size: UDim2)
        local outline = create("Frame", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = size,
            ZIndex = 4,
            Parent = globeIcon,
        })
        corner(outline, UDim.new(0.5, 0))
        create("UIStroke", { Color = Theme.mist, Thickness = 1.2, Parent = outline })
    end
    globeStroke(UDim2.fromScale(1, 1))
    globeStroke(UDim2.fromScale(0.5, 1))
    create("Frame", {
        BackgroundColor3 = Theme.mist,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 0, 0, 1),
        ZIndex = 4,
        Parent = globeIcon,
    })
end
create("TextLabel", {
    Name = "Label",
    LayoutOrder = 2,
    BackgroundTransparency = 1,
    AutomaticSize = Enum.AutomaticSize.X,
    Size = UDim2.fromOffset(0, 16),
    FontFace = font(Enum.FontWeight.SemiBold),
    Text = options.FooterButtonText or "Biolink",
    TextSize = 12,
    TextColor3 = Theme.mist,
    ZIndex = 4,
    Parent = biolinkButton,
})

-- Notification toast ---------------------------------------------------------
local TOAST_SIZE = Vector2.new(190, 58)

local toast: Frame = create("Frame", {
    Name = "Notification",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(TOAST_SIZE.X, TOAST_SIZE.Y),
    Visible = false,
    ZIndex = 10,
    Parent = root,
})
corner(toast, 18)
local toastBase = create("Frame", {
    Name = "MarbleBase",
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 10,
    Parent = toast,
})
corner(toastBase, 18)
create("UIGradient", {
    Rotation = 125,
    Color = colorSeq({
        {0, Color3.fromRGB(7, 7, 10)},
        {0.4, Color3.fromRGB(22, 21, 27)},
        {0.7, Color3.fromRGB(28, 20, 42)},
        {1, Color3.fromRGB(7, 7, 10)},
    }),
    Parent = toastBase,
})
if lavaAsset then
    -- same texels-per-pixel as the window's lava, so the swirls are the same size
    local texel = PANEL_HEIGHT / Lava.window
    for index, layer in Lava.layers do
        local toastMarble = create("ImageLabel", {
            Name = "MarbleLava" .. index,
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Image = lavaAsset,
            ImageColor3 = layer.color,
            ImageTransparency = layer.transparency,
            ImageRectOffset = layer.origin + Vector2.new(25, 20),
            ImageRectSize = Vector2.new(TOAST_SIZE.X / texel, TOAST_SIZE.Y / texel),
            ZIndex = 10,
            Parent = toastBase,
        })
        corner(toastMarble, 18)
    end
end
specularRim(toast, 1, 0.5)
liquidWave(toast, TOAST_SIZE.X, TOAST_SIZE.Y, 18, 10)
for _, layer in toast:GetChildren() do
    if layer.Name == "LiquidWater" then
        layer.ImageColor3 = Theme.violet
        layer.ImageTransparency = math.max(layer.ImageTransparency, 0.83)
    end
end
sheen(toast, 18, 10)
local toastTitle: TextLabel = create("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 10),
    Size = UDim2.new(1, -32, 0, 18),
    FontFace = font(Enum.FontWeight.SemiBold),
    Text = "",
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Theme.mist,
    ZIndex = 11,
    Parent = toast,
})
local toastContent = create("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(16, 30),
    Size = UDim2.new(1, -32, 0, 16),
    FontFace = font(Enum.FontWeight.Medium),
    Text = "",
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Theme.mistDim,
    ZIndex = 11,
    Parent = toast,
})
-- Optional status badge on the right (Notify Type = "Success" / "Error"):
-- a soft tinted disc with a Lucide check or x. Created before collectFade so it
-- fades in and out with the text.
local toastBadge = create("Frame", {
    Name = "StatusBadge",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -14, 0.5, 0),
    Size = UDim2.fromOffset(26, 26),
    BackgroundColor3 = Theme.mist,
    BackgroundTransparency = 0.84,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 11,
    Parent = toast,
})
corner(toastBadge, UDim.new(0.5, 0))
local toastBadgeIcon = create("ImageLabel", {
    Name = "Icon",
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(15, 15),
    ZIndex = 12,
    Parent = toastBadge,
})
local TOAST_STATUS = {
    success = { icon = "check", color = Color3.fromRGB(150, 232, 190) },
    error = { icon = "x", color = Theme.danger },
}
local function setToastStatus(kind: string?)
    local status = if typeof(kind) == "string" then TOAST_STATUS[string.lower(kind)] else nil
    local data = status and LUCIDE[status.icon]
    toastBadge.Visible = data ~= nil
    local textWidth = if data then -32 - 34 else -32
    toastTitle.Size = UDim2.new(1, textWidth, 0, 18)
    toastContent.Size = UDim2.new(1, textWidth, 0, 16)
    if not data then return end
    toastBadge.BackgroundColor3 = status.color
    toastBadgeIcon.Image = "rbxassetid://" .. tostring(data[1])
    toastBadgeIcon.ImageRectSize = Vector2.new(data[2], data[3])
    toastBadgeIcon.ImageRectOffset = Vector2.new(data[4], data[5])
    toastBadgeIcon.ImageColor3 = status.color
end
-- Glint: one soft streak sweeping across the card, slanted \ (up to the left,
-- down to the right), with a faint eased trail. Clipped to the card's corners.
local toastGlint = create("Frame", {
    Name = "Glint",
    BackgroundColor3 = Theme.spec,
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 11,
    Parent = toast,
})
corner(toastGlint, 18)
local toastGlintKeys = {}
do
    local function smooth(a) a = math.clamp(a, 0, 1); return a * a * (3 - 2 * a) end
    local function strength(x) -- 0..1 brightness across the band (moving right)
        if x < 0.1 then return 0
        elseif x < 0.42 then return 0.22 * ((x - 0.1) / 0.32) ^ 2.2
        elseif x < 0.47 then return 0.22 + 0.78 * smooth((x - 0.42) / 0.05)
        elseif x <= 0.53 then return 1
        else return 1 - smooth((x - 0.53) / 0.07) end
    end
    for _, x in {0, 0.1, 0.18, 0.26, 0.34, 0.42, 0.445, 0.47, 0.53, 0.565, 0.6, 1} do
        table.insert(toastGlintKeys, NumberSequenceKeypoint.new(x, 1 - 0.42 * strength(x)))
    end
end
local toastGlintGradient = create("UIGradient", {
    Rotation = -32,
    Offset = Vector2.new(-1.4, 0),
    Transparency = NumberSequence.new(toastGlintKeys),
    Parent = toastGlint,
})
local toastFade = collectFade(toast)
-- collectFade only knows background/text/stroke transparency; the badge's
-- icon is an image, so add it explicitly or it lingers after the card is gone
table.insert(toastFade, { instance = toastBadgeIcon, property = "ImageTransparency", base = 0 })

-- Panel resizing state (grip, limits, and skeleton bones that depend on height)
local Resize = {
    pageBones = {} :: { { bone: Frame, bottom: number } },
    minimized = false,
    minSize = Vector2.new(Layout.width - 40, CONTENT_Y + Layout.rowHeight * 2 + (PANEL_HEIGHT - FOOTER_Y) + 30),
    maxSize = Vector2.new(Layout.width * 2, PANEL_HEIGHT * 2.2),
    dragging = false,
}
local skeletonGhost, skeletonGroup, skeletonGlow, skeletonGradient, boneGradients  -- shared out of the drag skeleton block below
do -- drag skeleton (scoped to stay under Luau's 200-local limit)
-- Drag skeleton (the only element with glow) ---------------------------------
local SKELETON_PAD = 26

-- The ghost mirrors the panel exactly: same size, anchor and UIScale, and it
-- is moved with the same UDim2 Position the panel will get. Whatever pivot
-- Roblox scales around, ghost and panel line up pixel for pixel.
skeletonGhost = create("Frame", {
    Name = "DragGhost",
    BackgroundTransparency = 1,
    Size = root.Size,
    AnchorPoint = root.AnchorPoint,
    Position = root.Position,
    Visible = false,
    ZIndex = 20,
    Parent = screenGui,
})
passThrough(skeletonGhost)
create("UIScale", { Scale = Layout.uiScale, Parent = skeletonGhost })

skeletonGroup = create("CanvasGroup", {
    Name = "DragSkeleton",
    BackgroundTransparency = 1,
    GroupTransparency = 1,
    ZIndex = 20,
    Position = UDim2.fromOffset(-SKELETON_PAD, -SKELETON_PAD),
    Size = UDim2.new(1, SKELETON_PAD * 2, 1, SKELETON_PAD * 2),
    Parent = skeletonGhost,
})
passThrough(skeletonGroup)

local skeleton: Frame = create("Frame", {
    Name = "Outline",
    BackgroundColor3 = Theme.tint,
    BackgroundTransparency = 0.74,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(SKELETON_PAD, SKELETON_PAD),
    Size = UDim2.new(1, -SKELETON_PAD * 2, 1, -SKELETON_PAD * 2),
    ZIndex = 2,
    Parent = skeletonGroup,
})
corner(skeleton, Layout.radius)
-- Glow sits outside the CanvasGroup (so it is never clipped by the group's
-- bounds) and fades on its own alongside it.
skeletonGlow = nil
local glowAsset = loadEmbeddedImage("skeleton-glow.png", EmbeddedPng.glow)
if glowAsset then
    local m, r, s = GLOW_SPRITE.margin, GLOW_SPRITE.radius, GLOW_SPRITE.size
    skeletonGlow = create("ImageLabel", {
        Name = "Glow",
        BackgroundTransparency = 1,
        Image = glowAsset,
        ImageColor3 = Theme.violet,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(m + r, m + r, s - m - r, s - m - r),
        SliceScale = Layout.radius / r,
        Position = UDim2.fromOffset(-m * Layout.radius / r, -m * Layout.radius / r),
        Size = UDim2.new(1, 2 * m * Layout.radius / r, 1, 2 * m * Layout.radius / r),
        ZIndex = 19,
        Parent = skeletonGhost,
    })
    passThrough(skeletonGlow :: ImageLabel)
else
    -- No custom-asset support: whole-pixel rings that never overlap, so the
    -- falloff stays monotonic.
    softGlow(skeleton, Theme.violet, Quality.glowLayers, Quality.glowSpread, 0.66, Layout.radius)
end
local skeletonStroke = create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Parent = skeleton })
skeletonGradient = create("UIGradient", {
    Color = colorSeq({{0, Theme.lilac}, {0.5, Theme.violet}, {1, Theme.lilac}}),
    Transparency = numberSeq({{0, 0.45}, {0.5, 0.62}, {1, 0.45}}),
    Parent = skeletonStroke,
})

boneGradients = {}
local function addBone(position: UDim2, size: UDim2): Frame
    local bone = create("Frame", {
        BackgroundColor3 = Theme.spec,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
        ZIndex = 3,
        Parent = skeleton,
    })
    -- Carved groove: dark inset with a bevel (shadowed top, lit bottom edge)
    -- and a thin light lip under its top edge.
    bone.BackgroundColor3 = Color3.fromRGB(7, 7, 10)
    bone.BackgroundTransparency = 0.84
    corner(bone, UDim.new(0.5, 0))
    local bevel = create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 1, Parent = bone })
    create("UIGradient", {
        Rotation = 90,
        Color = colorSeq({{0, Color3.fromRGB(7, 7, 10)}, {1, Theme.spec}}),
        Transparency = numberSeq({{0, 0.45}, {0.55, 0.9}, {1, 0.62}}),
        Parent = bevel,
    })
    if size.Y.Offset >= 10 then
        local lip = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 2),
            Size = UDim2.new(0.8, 0, 0, 1),
            BackgroundColor3 = Theme.spec,
            BorderSizePixel = 0,
            ZIndex = 4,
            Parent = bone,
        })
        create("UIGradient", { Transparency = numberSeq({{0, 1}, {0.5, 0.66}, {1, 1}}), Parent = lip })
    end
    return bone
end

local function fullWidth(height: number): UDim2
    return UDim2.new(1, -Layout.padX * 2, 0, height)
end

addBone(UDim2.fromOffset(CORNER_INSET + 7, 22), UDim2.fromOffset(10, 10))
addBone(UDim2.fromOffset(CORNER_INSET + 24, 21), UDim2.fromOffset(100, 12))
addBone(UDim2.new(1, -CORNER_INSET - 24, 0, 15), UDim2.fromOffset(24, 24))
addBone(UDim2.new(1, -CORNER_INSET - 24 - 8 - 24, 0, 15), UDim2.fromOffset(24, 24)) -- minimize
addBone(UDim2.fromOffset(Layout.padX, Layout.tabsY), fullWidth(Layout.tabsHeight))
-- Content bones are created from the active tab by the library API.
Resize.addBone = addBone
-- footer bones ride the bottom edge, like the footer itself
addBone(UDim2.new(0, Layout.padX, 1, FOOTER_Y + 8 - PANEL_HEIGHT), UDim2.fromOffset(96, 12))
addBone(UDim2.new(1, -Layout.padX - 92, 1, FOOTER_Y - PANEL_HEIGHT), UDim2.fromOffset(92, Layout.footerHeight))
end
