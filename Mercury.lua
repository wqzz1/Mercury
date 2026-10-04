--!nocheck
-- Mercury: standalone UI library.
-- No game features, persistence, or external requests.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local executorEnv = getfenv(0)
local Mercury = {}
function Mercury:CreateWindow(options)
    options = options or {}
    local state = {currentTab = nil, closing = false, destroyed = false}
    local cleanupTasks = {}
    local function track(item)
        table.insert(cleanupTasks, item)
        return item
    end
    local function runCleanup()
        for i = #cleanupTasks, 1, -1 do
            local item = cleanupTasks[i]
            if typeof(item) == "RBXScriptConnection" then item:Disconnect()
            elseif typeof(item) == "Instance" then item:Destroy()
            elseif typeof(item) == "function" then pcall(item) end
        end
        table.clear(cleanupTasks)
    end
    local pageHeight = 418
-- source: config.lua
local Theme = {
    tint = Color3.fromRGB(16, 11, 26),
    mist = Color3.fromRGB(226, 214, 246),
    mistDim = Color3.fromRGB(160, 142, 192),
    spec = Color3.fromRGB(238, 228, 255),
    lilac = Color3.fromRGB(190, 160, 250),
    violet = Color3.fromRGB(124, 80, 214),
    plum = Color3.fromRGB(50, 28, 86),
    knob = Color3.fromRGB(234, 226, 250),
    danger = Color3.fromRGB(255, 138, 156),
    ink = Color3.fromRGB(7, 7, 10),
    graphite = Color3.fromRGB(22, 21, 27),
    bruise = Color3.fromRGB(28, 20, 42),
    smoke = Color3.fromRGB(66, 63, 76),
    lava = Color3.fromRGB(150, 90, 240),
    lavaDeep = Color3.fromRGB(90, 46, 150),

    fontFamily = "rbxasset://fonts/families/BuilderSans.json",
}

-- Colour roles. Every colour Mercury draws comes from one of these, so a theme
-- is one value per role. `name` is the public name (used by window:SetTheme with
-- a custom table); `key` is the field in Theme the code reads.
local ThemeRoles = {
    {name = "Surface", key = "tint"},           -- dark glass fill: wells, lists, tracks, hex field
    {name = "Text", key = "mist"},              -- titles, labels, icons; also the liquid rim light
    {name = "SubText", key = "mistDim"},        -- descriptions, captions, values, inactive icons
    {name = "Highlight", key = "spec"},         -- specular glints, sheens, divider shine
    {name = "Glow", key = "lilac"},             -- soft accent: glows, hover rims, gradient ends
    {name = "Accent", key = "violet"},          -- main accent: active tab, fills, toggles on
    {name = "AccentDeep", key = "plum"},        -- deep accent: background orbs, shadows
    {name = "Knob", key = "knob"},              -- slider and toggle knobs
    {name = "Danger", key = "danger", fixed = true}, -- errors and destructive actions
    {name = "Background", key = "ink"},         -- marble background, darkest tone
    {name = "BackgroundMid", key = "graphite"}, -- marble background, middle tone
    {name = "BackgroundTint", key = "bruise"},  -- marble background, accent-tinted tone
    {name = "Vein", key = "smoke"},             -- marble veins
    {name = "Swirl", key = "lava"},             -- marble swirl, bright layer
    {name = "SwirlDeep", key = "lavaDeep"},     -- marble swirl, deep layer
}
-- Built-in themes: the default palette moved to one hue (sat/value scale it).
-- "Rainbow" is not a palette: it slowly cycles the hue through every colour (api.lua)
local ThemeOrder = {"Default", "Mono", "Red", "Brown", "Orange", "Green", "Turquoise", "Hot Pink", "Rainbow"}
-- sat / value scale the default palette's saturation and brightness
local ThemeTints = {
    Mono = {sat = 0, value = 1.1},
    Red = {hue = 0.988, sat = 1.35, value = 1.15},
    Brown = {hue = 0.075, sat = 1.15, value = 1.08},
    Orange = {hue = 0.088, sat = 1.45, value = 1.18},
    Green = {hue = 0.37, sat = 1.35, value = 1.15},
    Turquoise = {hue = 0.475, sat = 1.35, value = 1.15},
    ["Hot Pink"] = {hue = 0.915, sat = 1.45, value = 1.15},
}
local RainbowTint = {sat = 1.35, value = 1.12}
local DefaultPalette = {}
for _, role in ThemeRoles do DefaultPalette[role.key] = Theme[role.key] end
-- whole 0-255 values, and no two roles equal (colours are matched by value)
local function finishPalette(palette: {[string]: Color3}): {[string]: Color3}
    local used = {}
    for _, role in ThemeRoles do
        local c = palette[role.key]
        local r, g, b = math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)
        -- nudge a duplicate by the smallest free step (blue, then green, then red)
        if used[r * 65536 + g * 256 + b] then
            local found = false
            for step = 1, 255 do
                for _, d in {-step, step} do
                    for channel = 3, 1, -1 do
                        local rr, gg, bb = r, g, b
                        if channel == 3 then bb = b + d elseif channel == 2 then gg = g + d else rr = r + d end
                        if rr >= 0 and rr <= 255 and gg >= 0 and gg <= 255 and bb >= 0 and bb <= 255 and not used[rr * 65536 + gg * 256 + bb] then
                            r, g, b, found = rr, gg, bb, true
                            break
                        end
                    end
                    if found then break end
                end
                if found then break end
            end
        end
        used[r * 65536 + g * 256 + b] = true
        palette[role.key] = Color3.fromRGB(r, g, b)
    end
    return palette
end
-- the default palette moved to one hue: tint = {hue, sat (scale), value (scale)}
local function tintPalette(tint): {[string]: Color3}
    local palette = table.clone(DefaultPalette)
    for _, role in ThemeRoles do
        if not role.fixed then
            local h, s, v = DefaultPalette[role.key]:ToHSV()
            palette[role.key] = Color3.fromHSV(tint.hue or h, math.clamp(s * (tint.sat or 1), 0, 1), math.clamp(v * (tint.value or 1), 0, 1))
        end
    end
    return finishPalette(palette)
end
local function themePalette(theme): {[string]: Color3}
    if typeof(theme) == "table" then
        local palette = table.clone(DefaultPalette)
        for _, role in ThemeRoles do
            local value = theme[role.name] or theme[role.key]
            if typeof(value) == "Color3" then palette[role.key] = value end
        end
        return finishPalette(palette)
    elseif ThemeTints[theme] then
        return tintPalette(ThemeTints[theme])
    end
    return finishPalette(table.clone(DefaultPalette))
end

local Layout = {
    uiScale = 0.94,        -- overall size of the panel (1 = full size)
    width = 300,
    padX = 20,
    gap = 18,              -- tabs -> first control; also toast offset
    radius = 22,
    tabsY = 56,
    tabsHeight = 49,
    rowHeight = 48,
    buttonHeight = 40,
    itemGap = 12,
    tabCount = 1,
    -- First row sits this far inside the page's fade layer; that layer clips
    -- at its edge, so a row at 0 lost its top rim.
    pageInset = 6,
    dividerHeight = 3,
    footerHeight = 28,
    bottomPad = 22,
    hoverGrowPx = -15,     -- total px width change on hover (negative = settles inward, ~7.5px per side)
    pressShrinkPx = 18,    -- total px it narrows while pressed
    defaultSize = Vector2.new(414, 592), -- panel size before you resize it (px, before uiScale)
    minimizeKey = Enum.KeyCode.RightShift, -- hotkey: minimize to the bubble / restore
    bubbleSize = 76,       -- minimized bubble diameter (px, before uiScale)
    -- Icon shown in the minimized bubble. Any of:
    --   1234567 / "1234567"            Roblox image or decal id
    --   "rbxassetid://1234567"         (also rbxasset://, rbxthumb://)
    --   "https://example.com/logo.png" downloaded once into the workspace
    --   "Mercury/logo.png"       a file in your executor workspace
    -- Empty = the panel's spinning logo dot.
    minimizedIcon = "" :: any,
    -- Liquid quality: "Smooth" (full), "Balanced" (lighter), "Low" (no liquid
    -- morph, slow bubble). Smooth and Balanced also ease off by themselves
    -- when the game alone is near 60 FPS.
    performance = "Smooth",
    -- Standard length (seconds) of any open/close animation, both directions:
    -- matches the minimize morph (~0.85-1.25 s, 1.05 on average). New animated
    -- elements use this so everything opens and closes at the same pace.
    transitionTime = 1.05,
    -- Small labels inside controls (slider captions, HEX, values): one size
    -- under the 13 px section titles, two under the 14 px row text.
    captionTextSize = 12,
}

-- Tapered divider: many stacked lines, each narrower and thicker, so the
-- ends thin out and fade while the centre is thick and nearly solid.
local Divider = {
    layers = 14,
    minWidth = 0.14,        -- innermost layer width (fraction of full)
    maxThickness = 2,       -- px at the centre
    centreOpacity = 0.72,   -- combined opacity at the middle
}

-- High-resolution layer counts for anything built from stacked objects.
local Quality = {
    orbRings = 56,          -- rings per background orb
    veinSteps = 8,          -- smoothstep samples per vein side (max 9)
    glowLayers = 18,        -- fallback glow rings (used only without custom assets)
    glowSpread = 1,         -- px between fallback rings (whole pixels avoid banding)
}

-- Marble-lava background texture (160x160 seamless tile, stored 2x2).
local Lava = {
    tile = 160,
    window = 105,           -- texture rows shown across the panel; smaller = bigger, sparser swirls
    layers = {
        { color = Theme.lava, transparency = 0.64,
          velocity = Vector2.new(1.6, 1.1), origin = Vector2.new(0, 0) },
        { color = Theme.lavaDeep, transparency = 0.8,
          velocity = Vector2.new(-1.2, 1.5), origin = Vector2.new(70, 40) },
    },
}
-- Embedded PNGs (base64), grouped in one table to save top-level locals.
local EmbeddedPng: { [string]: string } = {}
EmbeddedPng.lava = "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"

-- Liquid water layer inside glass controls. Two copies of a seamless
-- 128x128 water texture (stored 2x2 so any window wraps) drift in different
-- directions at gentle, slowly varying speeds; where they cross they form
-- the shifting, rolling highlights of a calm water surface.
local Liquid = {
    transparency = 0.8,     -- per layer; 1 = invisible
    speedA = Vector2.new(5.5, 2.5),   -- texture px per second
    speedB = Vector2.new(-3.5, 4),
    sway = 0.35,            -- how much the speeds breathe (0..1)
    rectHeight = 28,        -- texture rows shown per control (<= 128)
}
EmbeddedPng.wave = "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"

-- Bold soft-edged stripes used as the ForceField pattern; thick enough to
-- stay readable from far away.
EmbeddedPng.stripes = "iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAIAAABMXPacAAABZklEQVR42u3YwQ2DMBAF0RAhQT/4RvtcqYdrushI+E0JXnn3/1n2ff+gYz2OwyuELNd1eYVyAM/zeIWQryeIb8B9316hXEHneXqFcgDbtnkFAFbQpClojOEVNGFNGJqwJgxNWAwFALgB+FcMpSLiH0BFxAOgIlqoiPoGUBHxCqIixFAAgBswZwylIuIfQEXEA6AiWqiI+gZQEfEKoiLEUABWEDRhTRiasCYMTVgThhgKAHAD3h9DqYj4B1AR8QCoiBYqor4BVES8gqgIMRQA4AbMGUOpiPgHUBHxAKiIFiqivgFURLyCqAgxFIAVBE1YE4YmrAlDE9aEIYYCANyA98dQKiL+AVREPAAqooWKqG8AFRGvICpCDAUAuAFzxlAqIv4BVEQ8ACqihYqobwAVEa8gKkIMBWAFQRPWhKEJa8LQhDVhiKEAADfg/TGUioh/ABURD4CKaKEi6htARcQriIoQQwEADT8A+m1pq2ybUwAAAABJRU5ErkJggg=="

-- Lucide "globe" (ISC licence), rasterised to 64x64 white PNG.
local ASSET_FOLDER = "Mercury"

-- Pre-blurred outer glow for the drag skeleton (176x176, white, 9-slice).
-- A real Gaussian falloff; stacked strokes band and re-brighten at the tail.
local GLOW_SPRITE = {
    size = 176,
    margin = 44,            -- transparent border around the rounded rect
    radius = 22,            -- corner radius baked into the sprite
    visibleTransparency = 0.18,
}
EmbeddedPng.glow = "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"
EmbeddedPng.globe = "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"


-- source: primitives.lua
type FadeEntry = { instance: any, property: string, base: number }

type SwitchRow = {
    button: TextButton,
    set: (on: boolean, instant: boolean?) -> (),
    setSubtitle: (text: string?, color: Color3?) -> (),
}

type Blob = {
    frame: Frame,
    center: Vector2,
    radius: Vector2,
    speed: number,
    phase: number,
}


type WaveLayer = { label: ImageLabel, velocity: Vector2, origin: Vector2, phase: number }
type TabParts = { button: TextButton, label: TextLabel, platter: Frame }
local function create(className: string, props: { [string]: any }): any
    local instance: any = Instance.new(className)
    local parent = props.Parent
    for key, value in props do
        if key ~= "Parent" then
            instance[key] = value
        end
    end
    if parent then
        instance.Parent = parent
    end
    return instance
end

local function font(weight: Enum.FontWeight?): Font
    return Font.new(Theme.fontFamily, weight or Enum.FontWeight.Medium)
end

local function corner(parent: Instance, radius: UDim | number): UICorner
    return create("UICorner", {
        CornerRadius = if typeof(radius) == "UDim" then radius else UDim.new(0, radius :: number),
        Parent = parent,
    })
end

local function colorSeq(points: { { any } }): ColorSequence
    local keys = table.create(#points)
    for index, point in points do
        keys[index] = ColorSequenceKeypoint.new(point[1], point[2])
    end
    return ColorSequence.new(keys)
end

local function numberSeq(points: { { number } }): NumberSequence
    local keys = table.create(#points)
    for index, point in points do
        keys[index] = NumberSequenceKeypoint.new(point[1], point[2])
    end
    return NumberSequence.new(keys)
end

local function tween(
    instance: Instance,
    duration: number,
    goals: { [string]: any },
    style: Enum.EasingStyle?,
    direction: Enum.EasingDirection?
): Tween
    local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
    local handle = TweenService:Create(instance, info, goals)
    handle:Play()
    return handle
end

-- Tween, or apply instantly. Build-time state (saved toggles/filters) must be
-- applied instantly: open()'s fade-in snapshots transparencies right after the
-- UI is built, and would capture (and then restore) a half-finished tween.
local function styleTo(instance: Instance, duration: number, goals: { [string]: any }, instant: boolean?, style: Enum.EasingStyle?)
    if instant then
        for property, value in goals do
            (instance :: any)[property] = value
        end
    else
        tween(instance, duration, goals, style)
    end
end

local function passThrough(object: GuiObject)
    object.Active = false
    pcall(function()
        (object :: any).Interactable = false
    end)
end

local function escapeRichText(text: string): string
    return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local base64Lookup: { [number]: number } = {}
for index = 1, #BASE64_ALPHABET do
    base64Lookup[string.byte(BASE64_ALPHABET, index)] = index - 1
end

local function decodeBase64(input: string): string
    local crypt = executorEnv.crypt
    local native = (crypt and (crypt.base64decode or crypt.base64_decode)) or executorEnv.base64_decode
    if typeof(native) == "function" then
        local ok, result = pcall(native, input)
        if ok and typeof(result) == "string" then
            return result
        end
    end

    local bytes = table.create(#input * 3 // 4)
    for index = 1, #input, 4 do
        local a, b, c, d = string.byte(input, index, index + 3)
        local vc, vd = base64Lookup[c :: number], base64Lookup[d :: number]
        local triple = base64Lookup[a] * 262144 + base64Lookup[b :: number] * 4096 + (vc or 0) * 64 + (vd or 0)
        table.insert(bytes, string.char(triple // 65536))
        if vc then
            table.insert(bytes, string.char((triple // 256) % 256))
        end
        if vd then
            table.insert(bytes, string.char(triple % 256))
        end
    end
    return table.concat(bytes)
end

-- Writes an embedded PNG to the executor workspace and returns its asset id.
local function loadEmbeddedImage(fileName: string, base64Png: string): string?
    local writeFile = executorEnv.writefile
    local getAsset = executorEnv.getcustomasset or executorEnv.getsynasset
    if typeof(writeFile) ~= "function" or typeof(getAsset) ~= "function" then
        return nil
    end
    local ok, assetId = pcall(function()
        local isFolder, makeFolder = executorEnv.isfolder, executorEnv.makefolder
        if typeof(isFolder) == "function" and typeof(makeFolder) == "function" and not isFolder(ASSET_FOLDER) then
            makeFolder(ASSET_FOLDER)
        end
        local path = ASSET_FOLDER .. "/" .. fileName
        writeFile(path, decodeBase64(base64Png))
        return getAsset(path)
    end)
    return if ok and typeof(assetId) == "string" then assetId else nil
end

-- Snapshot every transparency in a subtree so it can fade as one.
local function collectFade(rootObject: Instance, skip: { [Instance]: boolean }?): { FadeEntry }
    local entries: { FadeEntry } = {}
    local function visit(object: Instance)
        if skip and skip[object] then
            return
        end
        if object:IsA("GuiObject") then
            table.insert(entries, { instance = object, property = "BackgroundTransparency", base = object.BackgroundTransparency })
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                -- Status lines can be mid-tween when the snapshot is taken; their
                -- FadeTarget is where they're heading, so fade to that instead.
                local target = object:GetAttribute("FadeTarget")
                local base = if typeof(target) == "number" then target else object.TextTransparency
                table.insert(entries, { instance = object, property = "TextTransparency", base = base })
            end
        elseif object:IsA("UIStroke") then
            table.insert(entries, { instance = object, property = "Transparency", base = object.Transparency })
        end
        for _, child in object:GetChildren() do
            visit(child)
        end
    end
    visit(rootObject)
    return entries
end

local function playFade(entries: { FadeEntry }, show: boolean, duration: number)
    for _, entry in entries do
        if show then
            entry.instance[entry.property] = 1
        end
        tween(entry.instance, duration, { [entry.property] = if show then entry.base else 1 })
    end
end

local function specularRim(parent: Instance, thickness: number?, brightness: number?): UIStroke
    local peak = brightness or 0.35
    local stroke = create("UIStroke", {
        Color = Theme.spec,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
    create("UIGradient", {
        Rotation = -90, -- light from above
        Transparency = numberSeq({
            {0, math.min(1, peak + 0.4)},
            {0.25, 0.86},
            {0.5, 0.97},
            {0.75, 0.86},
            {1, peak},
        }),
        Parent = stroke,
    })
    return stroke
end

type WaveLayer = {
    label: ImageLabel,
    rectSize: Vector2,
    origin: Vector2,
    velocity: Vector2,
    phase: number,
}
local waveLayers: { WaveLayer } = {}
local waveAsset = loadEmbeddedImage("liquid-water.png", EmbeddedPng.wave)
local WAVE_TILE = 128

local function addWaveLayer(parent: Instance, rectSize: Vector2, radius: UDim | number, zIndex: number, velocity: Vector2)
    local label: ImageLabel = create("ImageLabel", {
        Name = "LiquidWater",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Image = waveAsset,
        ImageColor3 = Theme.mist,
        ImageTransparency = Liquid.transparency,
        ScaleType = Enum.ScaleType.Stretch,
        ImageRectSize = rectSize,
        ZIndex = zIndex,
        Parent = parent,
    })
    passThrough(label)
    corner(label, radius)
    local seed = #waveLayers
    table.insert(waveLayers, {
        label = label,
        rectSize = rectSize,
        origin = Vector2.new((seed * 41) % WAVE_TILE, (seed * 67) % WAVE_TILE),
        velocity = velocity,
        phase = seed * 1.7,
    })
end

-- Adds the water layers to a glass surface of known pixel size. UICorner
-- clips each image to the control's rounded shape.
local function liquidWave(parent: Instance, width: number, height: number, radius: UDim | number, zIndex: number?)
    if not waveAsset then
        return
    end
    local aspect = width / math.max(height, 1)
    local rectHeight = math.min(Liquid.rectHeight, WAVE_TILE / aspect)
    local rectSize = Vector2.new(rectHeight * aspect, rectHeight)
    addWaveLayer(parent, rectSize, radius, zIndex or 2, Liquid.speedA)
    addWaveLayer(parent, rectSize, radius, zIndex or 2, Liquid.speedB)
end

local function sheen(parent: Instance, radius: UDim | number, zIndex: number?): Frame
    local frame = create("Frame", {
        Name = "Sheen",
        BackgroundColor3 = Theme.spec,
        BorderSizePixel = 0,
        -- Full size with the parent's own corner, faded out by the middle.
        -- (A half-height frame got a tighter pill radius than its parent and
        -- poked out of the top corners as little circles.)
        Size = UDim2.fromScale(1, 1),
        ZIndex = zIndex or 2,
        Parent = parent,
    })
    passThrough(frame)
    corner(frame, radius)
    create("UIGradient", {
        Rotation = 90,
        Transparency = numberSeq({{0, 0.93}, {0.5, 1}, {1, 1}}),
        Parent = frame,
    })
    return frame
end

local function softGlow(parent: Instance, color: Color3, layers: number, spread: number, peak: number, radius: number)
    for index = 1, layers do
        local pad = index * spread
        local ring = create("Frame", {
            Name = "Glow" .. index,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, pad * 2, 1, pad * 2),
            Position = UDim2.fromOffset(-pad, -pad),
            ZIndex = 0,
            Parent = parent,
        })
        passThrough(ring)
        corner(ring, radius + pad)
        local falloff = (index - 1) / layers
        create("UIStroke", {
            Color = color,
            Thickness = spread,
            Transparency = 1 - (1 - peak) * (1 - falloff) ^ 2,
            Parent = ring,
        })
    end
end

-- Thin, fading ends; thicker, solid centre. Uses the rim colour.
-- The holder and its layers follow the parent's width, keeping the divider
-- inside the window when the user resizes it.
local function taperedDivider(parent: Instance, centerY: number): Frame
    local boxHeight = Divider.maxThickness
    local holder = create("Frame", {
        Name = "Divider",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, Layout.padX, 0, math.round(centerY - boxHeight / 2)),
        Size = UDim2.new(1, -Layout.padX * 2, 0, boxHeight),
        ZIndex = 2,
        Parent = parent,
    })
    passThrough(holder)

    local layerAlpha = 1 - (1 - Divider.centreOpacity) ^ (1 / Divider.layers)
    local fade = numberSeq({
        {0, 1},
        {0.15, 1 - layerAlpha * 0.1},
        {0.3, 1 - layerAlpha * 0.45},
        {0.42, 1 - layerAlpha * 0.85},
        {0.5, 1 - layerAlpha},
        {0.58, 1 - layerAlpha * 0.85},
        {0.7, 1 - layerAlpha * 0.45},
        {0.85, 1 - layerAlpha * 0.1},
        {1, 1},
    })

    for index = 1, Divider.layers do
        local t = (index - 1) / (Divider.layers - 1)
        local widthFraction = 1 - t * (1 - Divider.minWidth)
        local height = if t < 0.5 then 1 else boxHeight
        local line = create("Frame", {
            BackgroundColor3 = Theme.spec,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, (boxHeight - height) // 2),
            Size = UDim2.new(widthFraction, 0, 0, height),
            ZIndex = 2,
            Parent = holder,
        })
        corner(line, UDim.new(0.5, 0))
        create("UIGradient", { Transparency = fade, Parent = line })
    end
    return holder
end

-- Chevron drawn from two rounded bars, in the panel's edge colour.
-- Rotation 0 points down; 180 points up.
local ScrollHints = { list = {} :: { any } } :: any

function ScrollHints.chevron(parent: Instance, size: number, zIndex: number): Frame
    local holder: Frame = create("Frame", {
        Name = "Chevron",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(size, size * 0.6),
        ZIndex = zIndex,
        Parent = parent,
    })
    passThrough(holder)
    for _, side in { -1, 1 } do
        local bar: Frame = create("Frame", {
            Name = "Bar",
            BackgroundColor3 = Theme.spec,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, side * size * 0.19, 0.5, 0),
            Size = UDim2.fromOffset(size * 0.56, 2),
            Rotation = side * -38,
            ZIndex = zIndex,
            Parent = holder,
        })
        corner(bar, UDim.new(0.5, 0))
    end
    return holder
end

-- Shows ^ at the top / v at the bottom of a ScrollingFrame while there is
-- more content in that direction. `overlayParent` must not scroll itself;
-- with `follow`, the overlay tracks the scroller's Position/Size (for pages
-- that slide between tabs).
function ScrollHints.attach(scroller: ScrollingFrame, overlayParent: Instance, follow: boolean)
    local overlay: Frame = create("Frame", {
        Name = scroller.Name .. "Hints",
        BackgroundTransparency = 1,
        Position = if follow then scroller.Position else UDim2.new(),
        Size = if follow then scroller.Size else UDim2.fromScale(1, 1),
        ZIndex = 8,
        Parent = overlayParent,
    })
    passThrough(overlay)
    local up = ScrollHints.chevron(overlay, 16, 8)
    up.Rotation = 180.01
    up.Position = UDim2.new(0.5, 0, 0, 7)
    local down = ScrollHints.chevron(overlay, 16, 8)
    down.Rotation = 0.01
    down.Position = UDim2.new(0.5, 0, 1, -7)
    table.insert(ScrollHints.list, {
        scroller = scroller, overlay = overlay, follow = follow,
        up = up, down = down, upShown = nil, downShown = nil,
    })
end

function ScrollHints.setShown(chevron: Frame, shown: boolean)
    for _, bar in chevron:GetChildren() do
        if bar:IsA("Frame") then
            tween(bar, 0.2, { BackgroundTransparency = if shown then 0.15 else 1 })
        end
    end
end

-- Scroll fade. Everything inside a scroller is moved into one CanvasGroup
-- and faded with a single UIGradient mask that tracks the visible window.
-- Because the whole layer is composited first and faded once, every object
-- fades by exactly the same amount no matter what its own transparency is,
-- so nothing is ever over- or under-faded.
ScrollHints.fades = {} :: { any }
ScrollHints.FADE_PX = 22

function ScrollHints.fade(scroller: ScrollingFrame)
    local content: CanvasGroup = create("CanvasGroup", {
        Name = "FadeContent",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 2,
    })
    -- NOT passThrough(): Interactable=false would disable every button inside.
    -- Active=false alone keeps it from swallowing scroll/clicks.
    content.Active = false
    for _, child in scroller:GetChildren() do
        if not child:IsA("UIPadding") then
            child.Parent = content
        end
    end
    content.Parent = scroller
    local gradient: UIGradient = create("UIGradient", { Rotation = 90, Parent = content })
    table.insert(ScrollHints.fades, { scroller = scroller, content = content, gradient = gradient, key = "" })
end

local function fadeSequence(height: number, top: number, bottom: number, fadeTop: boolean, fadeBottom: boolean, fadePx: number): NumberSequence
    -- transparency is 1 at a faded window edge and eases to 0 over fadePx
    local points: { { number } } = { { 0, if fadeTop then 1 else 0 } }
    local function add(y: number, value: number)
        local t = math.clamp(y / height, 0.0001, 0.9999)
        local last = points[#points]
        if t <= last[1] then
            t = last[1] + 0.00005
        end
        if t < 0.99995 then
            table.insert(points, { t, value })
        end
    end
    local span = math.min(fadePx, math.max(1, (bottom - top) / 2))
    if fadeTop then
        add(top, 1)
        add(top + span * 0.35, 0.62)
        add(top + span * 0.7, 0.2)
        add(top + span, 0)
    else
        add(math.max(top, 0.5), 0)
    end
    if fadeBottom then
        add(bottom - span, 0)
        add(bottom - span * 0.7, 0.2)
        add(bottom - span * 0.35, 0.62)
        add(bottom, 1)
    else
        add(bottom, 0)
    end
    table.insert(points, { 1, points[#points][2] })
    return numberSeq(points)
end

function ScrollHints.updateFades()
    for _, fade in ScrollHints.fades do
        local scroller: ScrollingFrame = fade.scroller
        local content: CanvasGroup = fade.content
        local height = content.AbsoluteSize.Y
        if height < 1 or not scroller.Visible then
            continue
        end
        local top = scroller.AbsolutePosition.Y - content.AbsolutePosition.Y
        local bottom = top + scroller.AbsoluteSize.Y
        local fadeTop = top > 1
        local fadeBottom = bottom < height - 1
        local fadePx = ScrollHints.FADE_PX
        local key = string.format("%d|%d|%d|%s%s", height, top, bottom, tostring(fadeTop), tostring(fadeBottom))
        if key ~= fade.key then
            fade.key = key
            if not fadeTop and not fadeBottom then
                fade.gradient.Transparency = NumberSequence.new(0)
            else
                fade.gradient.Transparency = fadeSequence(height, top, bottom, fadeTop, fadeBottom, fadePx)
            end
        end
    end
end

function ScrollHints.update()
    ScrollHints.updateFades()
    -- "this way" nudge: each arrow eases 5px toward where it points and back,
    -- about every 1.6s. The arrows carry a tiny rotation so Roblox draws them
    -- at sub-pixel positions (unrotated GUI snaps to whole pixels, which made
    -- the old 2px move look like 2-3 frames).
    local nudge = 5 * (0.5 - 0.5 * math.cos(os.clock() * (2 * math.pi / 1.6)))
    for _, hint in ScrollHints.list do
        hint.up.Position = UDim2.new(0.5, 0, 0, 8 - nudge)
        hint.down.Position = UDim2.new(0.5, 0, 1, -8 + nudge)
        local scroller: ScrollingFrame = hint.scroller
        if hint.follow then
            hint.overlay.Position = scroller.Position
            hint.overlay.Size = scroller.Size
        end
        local maxY = scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y
        local y = scroller.CanvasPosition.Y
        local visible = scroller.Visible
        local upShown = visible and y > 2
        local downShown = visible and maxY > 2 and y < maxY - 2
        if upShown ~= hint.upShown then
            hint.upShown = upShown
            ScrollHints.setShown(hint.up, upShown)
        end
        if downShown ~= hint.downShown then
            hint.downShown = downShown
            ScrollHints.setShown(hint.down, downShown)
        end
    end
end

-- Uniform hover/press scaling from the centre; children scale with it.
-- Growth is a fixed pixel amount, so wide and narrow controls grow equally.
local function attachHoverScale(trigger: GuiObject, target: GuiObject?)
    local scaled = target or trigger
    local scale = create("UIScale", { Parent = scaled })
    local hovered = false

    local function scaleFor(pixels: number): number
        local width = math.max(scaled.AbsoluteSize.X / scale.Scale, 1)
        if width < 40 then
            -- tiny icon buttons (close / minimize): a fixed -15px would shrink
            -- a 28px circle to under half its size, so cap it at -12%
            return math.max(1 + pixels / width, 0.88)
        end
        return 1 + pixels / width
    end

    track(trigger.MouseEnter:Connect(function()
        hovered = true
        tween(scale, 0.22, { Scale = scaleFor(Layout.hoverGrowPx) })
    end))
    track(trigger.MouseLeave:Connect(function()
        hovered = false
        tween(scale, 0.28, { Scale = 1 })
    end))
    if trigger:IsA("GuiButton") then
        track(trigger.MouseButton1Down:Connect(function()
            tween(scale, 0.1, { Scale = scaleFor(-Layout.pressShrinkPx) })
        end))
        track(trigger.MouseButton1Up:Connect(function()
            local goal = if hovered then scaleFor(Layout.hoverGrowPx) else 1
            tween(scale, 0.4, { Scale = goal }, Enum.EasingStyle.Back)
        end))
    end
end

local function glassButton(parent: Instance, name: string, text: string, y: number, height: number): (TextButton, TextLabel)
    local button: TextButton = create("TextButton", {
        Name = name,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = Theme.mist,
        BackgroundTransparency = 0.94,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.new(1, -Layout.padX * 2, 0, height),
        Position = UDim2.new(0.5, 0, 0, y + height / 2),
        ZIndex = 2,
        Parent = parent,
    })
    corner(button, UDim.new(0.5, 0))
    specularRim(button)
    liquidWave(button, Layout.width - Layout.padX * 2, height, UDim.new(0.5, 0), 2)
    sheen(button, UDim.new(0.5, 0), 2)

    local label: TextLabel = create("TextLabel", {
        Name = "Label",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        FontFace = font(Enum.FontWeight.Medium),
        Text = text,
        TextSize = 14,
        TextColor3 = Theme.mist,
        ZIndex = 4,
        Parent = button,
    })

    attachHoverScale(button)
    track(button.MouseEnter:Connect(function()
        tween(button, 0.2, { BackgroundTransparency = 0.9 })
    end))
    track(button.MouseLeave:Connect(function()
        tween(button, 0.25, { BackgroundTransparency = 0.94 })
    end))
    return button, label
end

local function switchRow(parent: Instance, name: string, text: string, y: number): SwitchRow
    local button, label = glassButton(parent, name, text, y, Layout.rowHeight)
    label.FontFace = font(Enum.FontWeight.SemiBold)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.AnchorPoint = Vector2.new(0, 0.5)
    label.Size = UDim2.new(1, -96, 0, 20)
    label.Position = UDim2.new(0, 20, 0.5, 0)

    local subtitle: TextLabel = create("TextLabel", {
        Name = "Subtitle",
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 0),
        Size = UDim2.new(1, -96, 0, 14),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(0, 20, 0.5, 2),
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        FontFace = font(Enum.FontWeight.Medium),
        Text = "",
        TextSize = 12,
        TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.mistDim,
        ZIndex = 4,
        Parent = button,
    })

    local fill: Frame = create("Frame", {
        Name = "LiquidFill",
        BackgroundColor3 = Theme.mist,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 1,
        Parent = button,
    })
    passThrough(fill)
    corner(fill, UDim.new(0.5, 0))
    create("UIGradient", {
        Color = colorSeq({{0, Theme.plum}, {0.65, Theme.violet}, {1, Theme.lilac}}),
        Transparency = numberSeq({{0, 0.2}, {1, 0.6}}),
        Parent = fill,
    })

    local trackFrame: Frame = create("Frame", {
        Name = "Track",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -16, 0.5, 0),
        Size = UDim2.fromOffset(46, 26),
        BackgroundColor3 = Theme.mist,
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = button,
    })
    passThrough(trackFrame)
    corner(trackFrame, UDim.new(1, 0))
    specularRim(trackFrame, 1, 0.45)

    local knob: Frame = create("Frame", {
        Name = "Knob",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        BackgroundColor3 = Theme.knob,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = trackFrame,
    })
    corner(knob, UDim.new(1, 0))
    create("UIStroke", { Color = Theme.tint, Transparency = 0.7, Parent = knob })

    local function set(on: boolean, instant: boolean?)
        styleTo(knob, 0.34, {
            Position = if on then UDim2.new(1, -23, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
        }, instant, Enum.EasingStyle.Back)
        styleTo(trackFrame, 0.25, {
            BackgroundColor3 = if on then Theme.violet else Theme.mist,
            BackgroundTransparency = if on then 0.05 else 0.86,
        }, instant)
        styleTo(fill, 0.4, { BackgroundTransparency = if on then 0.5 else 1 }, instant)
    end

    -- Long subtitles wrap onto extra lines and the row grows to fit them,
    -- so nothing slides under the switch. Title + status are laid out as one
    -- block that is vertically centred in the row.
    local baseHeight = Layout.rowHeight
    local TITLE_HEIGHT, LINE_HEIGHT, GAP = 16, 14, 2
    local function layoutWithStatus()
        local lines = math.max(1, math.ceil(subtitle.TextBounds.Y / LINE_HEIGHT - 0.01))
        local rowHeight = baseHeight + (lines - 1) * LINE_HEIGHT
        local blockHeight = TITLE_HEIGHT + GAP + lines * LINE_HEIGHT
        local top = math.floor((rowHeight - blockHeight) / 2 + 0.5)
        tween(button, 0.2, { Size = UDim2.new(1, -Layout.padX * 2, 0, rowHeight) })
        tween(label, 0.25, { Position = UDim2.new(0, 20, 0, top + TITLE_HEIGHT / 2) })
        tween(subtitle, 0.25, { Position = UDim2.new(0, 20, 0, top + TITLE_HEIGHT + GAP) })
    end
    local function setSubtitle(value: string?, color: Color3?)
        if value then
            subtitle.Text = value
            subtitle:SetAttribute("FadeTarget", 0)
            tween(subtitle, 0.2, { TextTransparency = 0, TextColor3 = color or Theme.mistDim })
            label.AnchorPoint = Vector2.new(0, 0.5)
            layoutWithStatus()
            task.defer(layoutWithStatus) -- re-run once TextBounds reflect the new text
        else
            subtitle:SetAttribute("FadeTarget", 1)
            tween(subtitle, 0.18, { TextTransparency = 1 })
            tween(label, 0.25, { Position = UDim2.new(0, 20, 0.5, 0) })
            tween(button, 0.2, { Size = UDim2.new(1, -Layout.padX * 2, 0, baseHeight) })
        end
    end

    return { button = button, set = set, setSubtitle = setSubtitle }
end



    if typeof(options.Performance) == "string" then Layout.performance = options.Performance end
    if typeof(options.MinimizeKey) == "EnumItem" then Layout.minimizeKey = options.MinimizeKey end
    if options.MinimizedIcon ~= nil then Layout.minimizedIcon = options.MinimizedIcon end

local LUCIDE = {
    ["activity"] = {16898612629, 48, 48, 514, 771},
    ["bell"] = {16898612819, 48, 48, 820, 257},
    ["check"] = {16898612819, 48, 48, 710, 869},
    ["chevron-down"] = {16898612819, 48, 48, 196, 918},
    ["chevron-up"] = {16898612819, 48, 48, 710, 918},
    ["circle-help"] = {16898613044, 48, 48, 820, 257},
    ["copy"] = {16898613044, 48, 48, 918, 612},
    ["download"] = {16898613044, 48, 48, 820, 906},
    ["eye"] = {16898613353, 48, 48, 771, 563},
    ["globe"] = {16898613509, 48, 48, 771, 563},
    ["heart"] = {16898613509, 48, 48, 661, 771},
    ["home"] = {16898613509, 48, 48, 820, 147},
    ["info"] = {16898613509, 48, 48, 612, 869},
    ["menu"] = {16898613613, 48, 48, 49, 820},
    ["minus"] = {16898613613, 48, 48, 771, 196},
    ["plus"] = {16898613699, 48, 48, 257, 918},
    ["search"] = {16898613699, 48, 48, 918, 857},
    ["settings"] = {16898613777, 48, 48, 771, 257},
    ["sliders-horizontal"] = {16898613777, 48, 48, 820, 355},
    ["sparkles"] = {16898613777, 48, 48, 918, 49},
    ["x"] = {16898613869, 48, 48, 869, 906},
}

-- source: shell.lua
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
-- Glint: the section headings' glint (text brightens toward white as a soft band
-- with a faint trail passes), swept across the card's text, icon and badge only,
-- never over the card's body. Each of them is drawn white and coloured by its own
-- UIGradient; the band is placed in card pixels and slanted \ (lower lines run
-- ahead), so it reads as one streak across every line.
local ToastGlint = {SPAN = 120, SLANT = 0.45, targets = {}, statusColor = Theme.mist,
    POINTS = {0.08, 0.14, 0.2, 0.26, 0.32, 0.37, 0.40, 0.425, 0.45, 0.57, 0.6, 0.63}}
do
    local function smooth(a) a = math.clamp(a, 0, 1); return a * a * (3 - 2 * a) end
    local function glintAt(x)
        if x < 0.08 then return 0
        elseif x < 0.40 then return 0.3 * ((x - 0.08) / 0.32) ^ 2.2
        elseif x < 0.45 then return 0.3 + 0.7 * smooth((x - 0.40) / 0.05)
        elseif x <= 0.57 then return 1
        else return 1 - smooth((x - 0.57) / 0.06) end
    end
    local WHITE = Color3.new(1, 1, 1)
    local function add(object, prop, base)
        object[prop] = WHITE
        local gradient = create("UIGradient", {Color = ColorSequence.new(base()), Parent = object})
        table.insert(ToastGlint.targets, {object = object, gradient = gradient, base = base})
    end
    add(toastTitle, "TextColor3", function() return Theme.mist end)
    add(toastContent, "TextColor3", function() return Theme.mistDim end)
    add(toastBadge, "BackgroundColor3", function() return ToastGlint.statusColor end)
    add(toastBadgeIcon, "ImageColor3", function() return ToastGlint.statusColor end)
    function ToastGlint.rest()
        for _, t in ToastGlint.targets do t.gradient.Color = ColorSequence.new(t.base()) end
    end
    -- the band's leading edge at `lead` px from the card's left edge
    function ToastGlint.at(lead: number)
        local card = toast.AbsolutePosition
        local midY = card.Y + toast.AbsoluteSize.Y / 2
        local span = ToastGlint.SPAN
        for _, t in ToastGlint.targets do
            local o = t.object
            local x0, w = o.AbsolutePosition.X - card.X, math.max(1, o.AbsoluteSize.X)
            local cy = o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2
            local start = lead - 0.63 * span + (cy - midY) * ToastGlint.SLANT
            local base = t.base()
            local function colorAt(u) return base:Lerp(WHITE, glintAt((x0 + u * w - start) / span)) end
            local keys = {ColorSequenceKeypoint.new(0, colorAt(0))}
            for _, p in ToastGlint.POINTS do
                local u = (start + p * span - x0) / w
                if u > 0.001 and u < 0.999 then table.insert(keys, ColorSequenceKeypoint.new(u, colorAt(u))) end
            end
            table.insert(keys, ColorSequenceKeypoint.new(1, colorAt(1)))
            t.gradient.Color = ColorSequence.new(keys)
        end
    end
end
local function setToastStatus(kind: string?)
    local status = if typeof(kind) == "string" then TOAST_STATUS[string.lower(kind)] else nil
    local data = status and LUCIDE[status.icon]
    toastBadge.Visible = data ~= nil
    local textWidth = if data then -32 - 34 else -32
    toastTitle.Size = UDim2.new(1, textWidth, 0, 18)
    toastContent.Size = UDim2.new(1, textWidth, 0, 16)
    if not data then return end
    ToastGlint.statusColor = status.color
    ToastGlint.rest()
    toastBadgeIcon.Image = "rbxassetid://" .. tostring(data[1])
    toastBadgeIcon.ImageRectSize = Vector2.new(data[2], data[3])
    toastBadgeIcon.ImageRectOffset = Vector2.new(data[4], data[5])
end
local toastGlint = nil -- (the old body streak; the glint now lives on the text, see ToastGlint)
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

-- source: tabs.lua
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
        local image = makeIcon(tabBar, icon, 16)
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

-- source: motion.lua
local drag = {
    pending = false,
    active = false,
    startInput = Vector2.zero,
    startPosition = UDim2.new(),
    minDelta = Vector2.zero,
    maxDelta = Vector2.zero,
    delta = Vector2.zero,
}
local closeHovered = false
local SCREEN_MARGIN = 6

local function isPointerInput(input: InputObject): boolean
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMoveInput(input: InputObject): boolean
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function offsetBy(position: UDim2, delta: Vector2): UDim2
    return position + UDim2.fromOffset(math.round(delta.X), math.round(delta.Y))
end

local function beginDrag(input: InputObject)
    if Resize.animating then return end
    if closeHovered or not isPointerInput(input) then
        return
    end
    -- Visible bounds right now, used to keep the panel fully on screen.
    local viewportSize = screenGui.AbsoluteSize
    local visiblePosition = root.AbsolutePosition
    local visibleSize = root.AbsoluteSize

    drag.pending = true
    drag.active = false
    drag.startInput = Vector2.new(input.Position.X, input.Position.Y)
    drag.startPosition = root.Position
    drag.delta = Vector2.zero
    drag.minDelta = Vector2.new(SCREEN_MARGIN, SCREEN_MARGIN) - visiblePosition
    drag.maxDelta = viewportSize - Vector2.new(SCREEN_MARGIN, SCREEN_MARGIN) - visiblePosition - visibleSize
end

local function updateDrag(input: InputObject)
    if not drag.pending or not isMoveInput(input) then
        return
    end
    local rawDelta = Vector2.new(input.Position.X, input.Position.Y) - drag.startInput
    if not drag.active then
        if rawDelta.Magnitude < 4 then
            return
        end
        drag.active = true
        skeletonGhost.Visible = true
        tween(skeletonGroup, 0.18, { GroupTransparency = 0 })
        if skeletonGlow then
            tween(skeletonGlow, 0.22, { ImageTransparency = GLOW_SPRITE.visibleTransparency })
        end
    end
    drag.delta = Vector2.new(
        math.clamp(rawDelta.X, drag.minDelta.X, math.max(drag.minDelta.X, drag.maxDelta.X)),
        math.clamp(rawDelta.Y, drag.minDelta.Y, math.max(drag.minDelta.Y, drag.maxDelta.Y))
    )
    skeletonGhost.Position = offsetBy(drag.startPosition, drag.delta)
end

local function endDrag(input: InputObject)
    if not drag.pending or not isPointerInput(input) then
        return
    end
    drag.pending = false
    if not drag.active then
        return
    end
    drag.active = false
    local finalPosition = offsetBy(drag.startPosition, drag.delta)
    tween(root, 0.36, { Position = finalPosition })
    local fadeOut = tween(skeletonGroup, 0.28, { GroupTransparency = 1 })
    if skeletonGlow then
        tween(skeletonGlow, 0.28, { ImageTransparency = 1 })
    end
    fadeOut.Completed:Connect(function(playbackState)
        if playbackState == Enum.PlaybackState.Completed and not drag.active then
            skeletonGhost.Visible = false
        end
    end)
end

-- Resize grip: one round handle in the bottom-right corner. Dragging it
-- resizes width and height together; the top-left corner stays put.
do
    -- Two parallel diagonal strokes with round caps, sitting just OUTSIDE the
    -- panel's rounded bottom-right corner. The 20x20 box is centred on the
    -- panel's corner point, so the long stroke crosses the empty corner area
    -- and the short one sits further out.
    local GRIP_BOX = 26
    local grip: TextButton = create("TextButton", {
        Name = "ResizeGrip",
        Text = "",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -GRIP_BOX / 2, 1, -GRIP_BOX / 2),
        Size = UDim2.fromOffset(GRIP_BOX, GRIP_BOX),
        ZIndex = 8,
        Parent = panel,
    })
    -- Each stroke is a small glass capsule (bright specular body fading to
    -- lilac, crisp rim) with a soft violet glow. The glow is GLOW_LAYERS thin
    -- rings, each 1px wider than the last and very faint, so the stacked
    -- falloff is smooth instead of a few hard bands.
    type GripStroke = { body: Frame, rim: UIStroke, halos: { Frame } }
    local strokes: { GripStroke } = {}
    local THICKNESS = 3
    local GLOW_LAYERS = 10
    local GLOW_ALPHA = 0.06        -- per ring at rest
    local GLOW_ALPHA_LIT = 0.11    -- per ring while hovered / dragging
    -- { centre in the box, length }: long runs across the corner, the short
    -- one is offset toward the outer corner
    for _, spec in { { Vector2.new(13, 13), 25 }, { Vector2.new(19, 19), 13 } } do
        local halos = {}
        for ring = 1, GLOW_LAYERS do
            local halo: Frame = create("Frame", {
                Name = "Glow" .. ring,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromOffset(spec[1].X, spec[1].Y),
                Size = UDim2.fromOffset(spec[2] + ring * 2, THICKNESS + ring * 2),
                Rotation = -45,
                BackgroundColor3 = Theme.violet,
                BackgroundTransparency = 1 - GLOW_ALPHA,
                BorderSizePixel = 0,
                ZIndex = 7,
                Parent = grip,
            })
            passThrough(halo)
            corner(halo, UDim.new(0.5, 0))
            table.insert(halos, halo)
        end
        local body: Frame = create("Frame", {
            Name = "Stroke",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(spec[1].X, spec[1].Y),
            Size = UDim2.fromOffset(spec[2], THICKNESS),
            Rotation = -45,
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
            ZIndex = 8,
            Parent = grip,
        })
        passThrough(body)
        corner(body, UDim.new(0.5, 0))
        create("UIGradient", {
            Color = colorSeq({{0, Theme.lilac}, {0.5, Theme.spec}, {1, Theme.spec}}),
            Transparency = numberSeq({{0, 0.25}, {0.6, 0}, {1, 0}}),
            Parent = body,
        })
        local rim: UIStroke = create("UIStroke", {
            Color = Theme.spec,
            Thickness = 1,
            Transparency = 0.5,
            Parent = body,
        })
        table.insert(strokes, { body = body, rim = rim, halos = halos })
    end
    local hovered = false
    local function paintGrip()
        local lit = hovered or Resize.dragging
        for _, stroke in strokes do
            tween(stroke.body, 0.18, {
                BackgroundTransparency = if lit then 0 else 0.2,
                BackgroundColor3 = if Resize.dragging then Theme.lilac else Color3.new(1, 1, 1),
            })
            tween(stroke.rim, 0.18, { Transparency = if lit then 0.2 else 0.5 })
            for _, halo in stroke.halos do
                tween(halo, 0.22, { BackgroundTransparency = 1 - (if lit then GLOW_ALPHA_LIT else GLOW_ALPHA) })
            end
        end
    end
    track(grip.MouseEnter:Connect(function()
        hovered = true
        paintGrip()
    end))
    track(grip.MouseLeave:Connect(function()
        hovered = false
        paintGrip()
    end))

    -- page area bottom at the default size; it moves 1:1 with the panel height
    local defaultViewportBottom = CONTENT_Y + pageHeight + 8

    -- Drag-skeleton bones: only rows the page area can actually show.
    function Resize.refreshBones(height: number)
        local viewportBottom = defaultViewportBottom + (height - PANEL_HEIGHT)
        for _, entry in Resize.pageBones do
            entry.bone.Visible = entry.bottom <= viewportBottom
        end
    end

    function Resize.apply(width: number, height: number)
        width = 2 * math.round(width / 2) -- even widths keep centred lines on whole pixels
        height = math.round(height)
        local size = UDim2.fromOffset(width, height)
        root.Size = size
        skeletonGhost.Size = size
        Resize.refreshBones(height)
        -- keep the marble texture's proportions (never sample past the image)
        local aspect = width / height
        local rect = if aspect >= 1 then Vector2.new(Lava.window, Lava.window / aspect)
            else Vector2.new(Lava.window * aspect, Lava.window)
        for _, lava in lavaLayers do
            lava.label.ImageRectSize = rect
        end
    end

    local start = { input = Vector2.zero, size = Vector2.zero, scale = 1, max = Vector2.zero }
    track(grip.InputBegan:Connect(function(input: InputObject)
        if Resize.animating then return end
        if Resize.minimized or not isPointerInput(input) then
            return
        end
        Resize.dragging = true
        start.input = Vector2.new(input.Position.X, input.Position.Y)
        start.size = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
        start.scale = math.max(panelScale.Scale, 0.01)
        -- never grow past the screen edge (sizes are in unscaled pixels)
        local room = (screenGui.AbsoluteSize - root.AbsolutePosition - Vector2.new(SCREEN_MARGIN, SCREEN_MARGIN)) / start.scale
        start.max = Vector2.new(
            math.max(Resize.minSize.X, math.min(Resize.maxSize.X, room.X)),
            math.max(Resize.minSize.Y, math.min(Resize.maxSize.Y, room.Y))
        )
        paintGrip()
    end))
    track(UserInputService.InputChanged:Connect(function(input: InputObject)
        if not Resize.dragging or not isMoveInput(input) then
            return
        end
        local delta = (Vector2.new(input.Position.X, input.Position.Y) - start.input) / start.scale
        Resize.apply(
            math.clamp(start.size.X + delta.X, Resize.minSize.X, start.max.X),
            math.clamp(start.size.Y + delta.Y, Resize.minSize.Y, start.max.Y)
        )
    end))
    track(UserInputService.InputEnded:Connect(function(input: InputObject)
        if not Resize.dragging or not isPointerInput(input) then
            return
        end
        Resize.dragging = false
        paintGrip()
    end))

    -- Minimize: the whole panel tucks away and a round liquid-glass bubble
    -- with an icon takes its place (nothing is squashed or stretched).
    -- Click the bubble, the minimize button or the hotkey to toggle; drag the
    -- bubble to move it. Icon: Layout.minimizedIcon (see Config).
    local minimizeButton = header:FindFirstChild("Minimize") :: TextButton
    -- built in its own function: a separate register frame keeps the main
    -- chunk under Luau's 200-local limit
    ;(function()
        local BUBBLE = Layout.bubbleSize

        local bubble: TextButton = create("TextButton", {
            Name = "MinimizedBubble",
            Text = "",
            AutoButtonColor = false,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(BUBBLE, BUBBLE),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.12,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 30,
            Parent = screenGui,
        })
        corner(bubble, UDim.new(0.5, 0))
        local bubbleScale: UIScale = create("UIScale", { Scale = Layout.uiScale, Parent = bubble })
        -- same dark marble glass body as the panel
        create("UIGradient", {
            Rotation = 125,
            Color = colorSeq({{0, Color3.fromRGB(7, 7, 10)}, {0.45, Color3.fromRGB(22, 21, 27)}, {0.75, Color3.fromRGB(28, 20, 42)}, {1, Color3.fromRGB(7, 7, 10)}}),
            Parent = bubble,
        })
        local tintOrb: Frame = create("Frame", {
            Name = "Tint",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.72, 0.28),
            Size = UDim2.fromScale(0.9, 0.9),
            BackgroundColor3 = Theme.violet,
            BackgroundTransparency = 0.7,
            BorderSizePixel = 0,
            ZIndex = 30,
            Parent = bubble,
        })
        passThrough(tintOrb)
        corner(tintOrb, UDim.new(0.5, 0))
        create("UIGradient", { Transparency = numberSeq({{0, 0.2}, {0.6, 0.85}, {1, 1}}), Rotation = 135, Parent = tintOrb })
        liquidWave(bubble, BUBBLE, BUBBLE, UDim.new(0.5, 0), 30)
        sheen(bubble, UDim.new(0.5, 0), 31)
        specularRim(bubble, 1.5, 0.08)

        -- Icon. Accepts a Roblox image/decal id (number or "123"), any rbxassetid://,
        -- rbxasset://, rbxthumb:// or http(s) image URL, or a file in the executor
        -- workspace. Falls back to the panel's spinning logo dot.
        local function resolveIcon(source: any): string?
            if typeof(source) == "number" then
                source = tostring(math.floor(source))
            end
            if typeof(source) ~= "string" or source == "" then
                return nil
            end
            if string.match(source, "^%d+$") then
                -- rbxthumb renders both image ids and decal ids
                return "rbxthumb://type=Asset&id=" .. source .. "&w=420&h=420"
            end
            if string.match(source, "^rbx") then
                return source
            end
            local getAsset = executorEnv.getcustomasset or executorEnv.getsynasset
            if typeof(getAsset) ~= "function" then
                return nil
            end
            if string.match(source, "^https?://") then
                local ok, body = pcall(function()
                    return (game :: any):HttpGet(source)
                end)
                if not ok or typeof(body) ~= "string" or #body == 0 then
                    return nil
                end
                local extension = string.match(string.lower(source), "%.(png)") or string.match(string.lower(source), "%.(jpe?g)") or "png"
                local path = ASSET_FOLDER .. "/bubble-icon." .. extension
                local wrote = pcall(executorEnv.writefile, path, body)
                if not wrote then
                    return nil
                end
                local okAsset, asset = pcall(getAsset, path)
                return if okAsset then asset else nil
            end
            local okAsset, asset = pcall(getAsset, source)
            return if okAsset then asset else nil
        end

        local iconHolder: Frame = create("Frame", {
            Name = "Icon",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(0.58, 0.58),
            BackgroundTransparency = 1,
            ZIndex = 32,
            Parent = bubble,
        })
        passThrough(iconHolder)
        task.spawn(function()
            local image = resolveIcon(Layout.minimizedIcon)
            if image then
                local icon: ImageLabel = create("ImageLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1),
                    Image = image,
                    ScaleType = Enum.ScaleType.Fit,
                    ZIndex = 32,
                    Parent = iconHolder,
                })
                passThrough(icon)
                corner(icon, UDim.new(0.22, 0))
            end
        end)

        local function placeBubble(center: Vector2)
            -- keep the whole bubble on screen
            local half = BUBBLE * Layout.uiScale / 2 + SCREEN_MARGIN
            local screen = screenGui.AbsoluteSize
            local x = math.clamp(center.X, half, math.max(half, screen.X - half))
            local y = math.clamp(center.Y, half, math.max(half, screen.Y - half))
            bubble.Position = UDim2.fromOffset(math.round(x), math.round(y))
        end
        do
            local screen = screenGui.AbsoluteSize
            placeBubble(Vector2.new(screen.X / 2, math.max(BUBBLE * Layout.uiScale / 2 + 70, screen.Y * .12)))
        end

-- Integrated liquid renderer; isolated register frame, no gameplay dependencies.
local liquid=(function()
local min,max,floor,ceil,sqrt=math.min,math.max,math.floor,math.ceil,math.sqrt
local move,sort,copy,fill=table.move,table.sort,buffer.copy,buffer.fill
local W,H,S=1,1,3
local OW,OH=3,3
local origin=Vector2.zero
local tiles={}
local surfaces={}
local canvas=create("Frame",{Name="LiquidTransition",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=0,Visible=false,Parent=screenGui})
passThrough(canvas)
-- Each surface lives in its own holder frame. A swap shows one holder and hides
-- the other; nothing already on screen is ever repositioned (moving a parent and
-- its children in the same frame could draw one frame with only half applied).
local holderOf={}
local stopped=false
local panelEntries,iconEntries={},{}
local backgrounds={}
local pending=nil
local step
local count,totalMs,maximumMs=0,0,0
-- Fluency: each liquid picture is drawn for the moment it will reach the screen
-- (lead = measured render latency), and between pictures the GPU slides and
-- scales the last one along the motion every frame, so the movement itself runs
-- at the game's frame rate while the shape detail updates as fast as the CPU allows.
local flow={latency=.02,lead=0,shotTime=0,frameDt=1/60,a=nil,b=nil,shot=nil,warped=false,fadeStart=0,fadeLen=0,fading=false,interval=1/30,doneAt=nil,gameTime=0,ourWork=0,firstLatency=.05,resetElapsed=false,hideIn=nil,retire=nil,panelAlpha=nil,iconAlpha=nil}
-- Work pacing: one liquid update may span a few frames so no single frame stalls.
-- pace() yields once this frame's slice has used its budget; the finished image is
-- uploaded in one go at the end. Synchronous renders (transition start, handoff)
-- run with no budget and never yield.
local FRAME_BUDGET=.004
-- Quality modes (Layout.performance): per-frame CPU slices for transition and
-- bubble pictures, the shortest gap between bubble redraws, and Low's instant
-- minimize. In every mode the slice also shrinks on its own when the game's
-- own frame (measured without the liquid) leaves less than that before 60 FPS,
-- so a slower PC gets a choppier liquid instead of a lower game frame rate.
local PERF=({
 Smooth={morph=.005,idle=.004,bubbleGap=0},
 Balanced={morph=.003,idle=.0025,bubbleGap=1/60},
 Low={morph=.002,idle=.0015,bubbleGap=1/20,instant=true},
})[Layout.performance or 'Smooth'] or {morph=.005,idle=.004,bubbleGap=0}
local function sliceBudget(base) return math.clamp(1/60-flow.gameTime,.0015,base) end
local pacing={budget=nil,start=0,task=nil,work=0,onDone=nil,frameStart=0,limit=FRAME_BUDGET}
local resumeRender
local function pace()
 if pacing.budget and os.clock()-pacing.start>pacing.budget then coroutine.yield() end
end
local P={x=130,y=70,w=300,h=440,r=26}; local bx,by,R=384,112,40
local cx,cy=280,290; local N=120; local rect,angles={},{}
local pi=math.pi; local sin,cos=math.sin,math.cos; local clamp=math.clamp
local function ease(t) return t<.5 and 4*t*t*t or 1-(-2*t+2)^3/2 end
local function rectPoint(s)
 local x,y,w,h,r=P.x,P.y,P.w,P.h,P.r
 local sw,sh=w-2*r,h-2*r;local arc=pi*r/2
 local d=s*(2*sw+2*sh+4*arc)
 local seg={{sw/2,x+w/2,y,1,0},{arc,x+w-r,y+r,-pi/2},{sh,x+w,y+r,0,1},{arc,x+w-r,y+h-r,0},{sw,x+w-r,y+h,-1,0},{arc,x+r,y+h-r,pi/2},{sh,x,y+h-r,0,-1},{arc,x+r,y+r,pi},{sw/2,x+r,y,1,0}}
 for _,v in ipairs(seg) do if d<=v[1] then if #v==5 then return {v[2]+v[4]*d,v[3]+v[5]*d} end;local a=v[4]+d/r;return {v[2]+cos(a)*r,v[3]+sin(a)*r} end;d-=v[1] end
 return {x+w/2,y}
end
local rng=Random.new(); local function rand(a,b) return rng:NextNumber(a,b) end
local function harmonics(n,lo,hi,klo,khi)
 local hs={};for i=1,n do hs[i]={rng:NextInteger(klo or 2,khi or 9),rand(lo,hi),rand(0,2*pi),rand(1.2,5)*(rand(0,1)<.5 and -1 or 1)} end
 return function(a,t) local v=0;for _,h in ipairs(hs) do v+=h[2]*sin(h[1]*a+h[3]+h[4]*t) end;return v end
end
local styles={'noise','edges','spiral','collapse'}
local lastStyle; local morph; local state='panel';local clock=0;local speed=1;local idle={};local nextIdle=0;local idleWave=harmonics(3,.6,1.6)
local api={}
local function newMorph(dir,forced)
 local seed=rng:NextInteger(1,2147483646);rng=Random.new(seed)
 local style=forced or styles[rng:NextInteger(1,#styles)];while not forced and style==lastStyle do style=styles[rng:NextInteger(1,#styles)] end;lastStyle=style
 local f=harmonics(rng:NextInteger(2,4),.3,1,1,6);local a=rand(0,2*pi);local sides=rng:NextInteger(2,4);local sign=rand(0,1)<.5 and -1 or 1
 local raw={};local lo,hi=math.huge,-math.huge
 for i,p in ipairs(rect) do local v
  if style=='noise' then v=f(angles[i],0) elseif style=='sweep' then v=(p[1]-cx)*cos(a)+(p[2]-cy)*sin(a)
  elseif style=='corners' then v=sign*min(math.abs(p[1]-cx)/P.w,math.abs(p[2]-cy)/P.h)
  elseif style=='edges' then v=cos(sides*angles[i]+a) elseif style=='spiral' then v=(sign*(angles[i]-a))%(2*pi)
  else v=-Vector2.new(p[1]-bx,p[2]-by).Magnitude end
  raw[i]=v;lo=min(lo,v);hi=max(hi,v)
 end
 local jitter=harmonics(2,.05,.15,3,12);local range=hi-lo;lo=math.huge;hi=-math.huge
 for i,v in ipairs(raw) do raw[i]=v+jitter(angles[i],0)*range;lo=min(lo,raw[i]);hi=max(hi,raw[i]) end
 local delay=rand(.08,.24);for i,v in ipairs(raw) do raw[i]=(v-lo)/max(hi-lo,.0001)*delay end
 local splash=rand(0,1)<.45;local drops={}
 for i=1,rng:NextInteger(splash and 7 or 4,splash and 11 or 8) do local at=rand(.08,.6);drops[i]={at=at,life=min(rand(.2,.45),.9-at),idx=rng:NextInteger(1,N),out=rand(splash and 22 or 12,splash and 52 or 32),r=rand(13,splash and 18 or 16)} end
 return {dir=dir,t=0,delay=raw,maxDelay=delay,wave=harmonics(rng:NextInteger(2,6),rand(2,6),rand(7,16),1,rng:NextInteger(5,12)),swirl=rand(-.7,.7),bend={rand(-55,55),rand(-55,55)},pace=rand(.85,1.25),drops=drops,style=style,seed=seed}
end
local function spawnIdle()
 local room=3-#idle;if room<=0 then return end
 local n=min(room,rand(0,1)<.18 and 2 or 1);local a=rand(0,2*pi)
 for i=1,n do table.insert(idle,{start=clock+(i-1)*rand(.1,.3),bud=rand(.7,1.1),float=rand(1.4,3.6),back=rand(1.6,2.6),a=a+rand(-.6,.6),out=rand(.7,1.15)*R,r=rand(8.5,11.5),spin=rand(.25,.7)*(rand(0,1)<.5 and -1 or 1),bob=rand(.6,1.4),phase=rand(0,2*pi),split=rand(0,1)<.4,splitSpin=rand(2.5,4.5)}) end
end
-- Live marble material for the liquid surface. Every update it is rebuilt
-- natively from the backdrop's own animated layer properties (orb positions,
-- vein rotation/offset, lava scroll), which the panel's render loop keeps
-- advancing on one continuous clock, minimized or not. Nothing is cached in
-- time: the liquid always shows the marble as it is right now. Layers that
-- never move relative to the panel are pre-rendered once per panel size.
local material=(function()
 local AS=game:GetService('AssetService')
 local OVER,WRITE,MUL=Enum.ImageCombineType.BlendSourceOver,Enum.ImageCombineType.Overwrite,Enum.ImageCombineType.Multiply
 local MARGIN=64      -- px of backdrop extended past the panel edge for droplets and wobble
 local BLOCK=8        -- rows (or columns) per vein blit; <=3.5 px shear on a soft band (<1/255 step)
 local LIMIT=1024     -- EditableImage side limit
 local LUT=2048       -- gradient lookup resolution
 local CHECK=1/4      -- how often to look for a panel resize
 local INK=Color3.fromRGB(7,7,10)
 local writeu32=buffer.writeu32
 local m={pixels=nil,ox=0,oy=0}
 local assets=nil
 local texture=nil
 local veinData={}
 local topLayers={}
 local function round(v) return floor(v+.5) end
 local function seqValue(seq,t)
  local keys=seq.Keypoints;t=clamp(t,0,1)
  for i=2,#keys do if t<=keys[i].Time then local a,b=keys[i-1],keys[i];return a.Value+(b.Value-a.Value)*(t-a.Time)/max(1e-6,b.Time-a.Time) end end
  return keys[#keys].Value
 end
 local function seqColor(seq,t)
  local keys=seq.Keypoints;t=clamp(t,0,1)
  for i=2,#keys do if t<=keys[i].Time then local a,b=keys[i-1],keys[i];return a.Value:Lerp(b.Value,(t-a.Time)/max(1e-6,b.Time-a.Time)) end end
  return keys[#keys].Value
 end
 local function byte(v) return clamp(round(v*255),0,255) end
 local function newImage(w,h) local image=AS:CreateEditableImage({Size=Vector2.new(w,h)});assert(image,'EditableImage allocation unavailable');return image end
 local function tiled(w,h,stripHeight)
  local list={};local step=stripHeight or LIMIT
  for y=0,h-1,step do for x=0,w-1,LIMIT do local tw,th=min(LIMIT,w-x),min(step,h-y);list[#list+1]={image=newImage(tw,th),x=x,y=y,w=tw,h=th} end end
  return list
 end
 local function destroyTiles(list) for _,tile in ipairs(list) do if tile.label then tile.label:Destroy() end;tile.image:Destroy() end end

 -- Read the backdrop's layer definitions once.
 local orbData={}
 for _,orb in ipairs(blobs) do
  local ring=orb.frame:FindFirstChildWhichIsA('Frame')
  if ring then orbData[#orbData+1]={frame=orb.frame,center=orb.center,color=ring.BackgroundColor3,alpha=1-ring.BackgroundTransparency,rings=#orb.frame:GetChildren()} end
 end
 for _,vein in ipairs(veins) do
  local lut=table.create(LUT+1,0);local lo,hi=LUT,0
  for i=0,LUT do local a=1-seqValue(vein.gradient.Transparency,i/LUT);lut[i]=a;if a>.001 then lo=min(lo,i);hi=max(hi,i) end end
  local c=vein.frame.BackgroundColor3
  veinData[#veinData+1]={frame=vein.frame,gradient=vein.gradient,lut=lut,lo=max(0,lo-1)/LUT,hi=min(LUT,hi+1)/LUT,rgb=byte(c.R)+byte(c.G)*256+byte(c.B)*65536}
 end
 local baseGradient=nil
 for _,child in ipairs(backdrop:GetChildren()) do
  if child:IsA('GuiObject') then
   local gradient=child:FindFirstChildWhichIsA('UIGradient')
   if child.Name=='Base' then baseGradient=gradient
   elseif gradient and child:IsA('Frame') and child.Size.X.Scale==1 and child.Size.Y.Scale<1 and gradient.Rotation==90 then
    topLayers[#topLayers+1]={instance=child,y=child.Position.Y.Scale,h=child.Size.Y.Scale,color=child.BackgroundColor3,transparency=gradient.Transparency}
   end
  end
 end
 table.sort(topLayers,function(a,b) return a.y<b.y end)

 -- Orb glows: the real panel built each one from 56 almost-transparent rings,
 -- which the GPU blends one 8-bit step at a time; the rounding eats the green and
 -- left pink-magenta blotches the liquid never had. Each glow is now one smooth
 -- sprite (the exact maths of that ring stack), shown in the real panel in place
 -- of its rings and used by the liquid too, so every surface shows the same glow.
 local orbSprites={}
 local function orbPixels(orb,size,D,yield)
  local c=size/2;local n=orb.rings;local keep=1-orb.alpha
  local rgb=byte(orb.color.R)+byte(orb.color.G)*256+byte(orb.color.B)*65536
  local buf=buffer.create(size*size*4);local slice=os.clock()
  for y=0,size-1 do for x=0,size-1 do
   -- rings at scale 1-(j-1)/n*.92 cover this pixel: a count linear in radius
   local d=sqrt((x+.5-c)^2+(y+.5-c)^2);local count=clamp((1-2*d/D)*n/.92+.5,0,n)
   if count>0 then writeu32(buf,(y*size+x)*4,rgb+round((1-keep^(count/n))*255)*16777216) end
  end
   if yield and os.clock()-slice>.002 then task.wait();slice=os.clock() end
  end
  return buf
 end
 do
  local k=Layout.uiScale
  for i,orb in ipairs(orbData) do
   local D=orb.frame.Size.X.Offset*k;local size=ceil(D)+2
   local image=newImage(size,size);image:WritePixelsBuffer(Vector2.zero,Vector2.new(size,size),orbPixels(orb,size,D))
   -- the panel shows a white copy tinted by ImageColor3, so a theme recolours it at once;
   -- the coloured one is what the liquid's marble draws
   local white=newImage(size,size);white:WritePixelsBuffer(Vector2.zero,Vector2.new(size,size),orbPixels({color=Color3.new(1,1,1),rings=orb.rings,alpha=orb.alpha},size,D))
   orbSprites[i]={image=image,size=size,D=D,white=white}
   for _,ring in ipairs(orb.frame:GetChildren()) do if ring:IsA('GuiObject') then ring.Visible=false end end
   local label=create('ImageLabel',{Name='OrbSprite',BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(size/k,size/k),ImageColor3=orb.color,ImageContent=Content.fromObject(white),Parent=orb.frame})
   passThrough(label)
  end
 end

 -- Stars: small four-point stars twinkle in the marble, anywhere in the panel;
 -- the part of a star behind a glass row, tab or button is seen blurred, the
 -- part in the gaps between them stays sharp. A couple
 -- more in the minimized bubble. Each fades in and out on its own slow rhythm
 -- and reappears somewhere new after fading out; only a few are lit at a time.
 -- While lit, a star scintillates like a real one seen through air: its
 -- brightness flickers irregularly (a few incommensurate rhythms), and its
 -- diffraction spikes stretch and shrink with that brightness while the core
 -- stays steadier. Each star keeps one colour for its life: mostly lavender,
 -- some blue-white, a few pale gold. The panel shows them as labels (core and
 -- spikes); compose() draws the same stars (position, size, brightness) into
 -- the liquid's marble and the bubble. Created here because EditableImages are
 -- refused earlier in the script.
 do
  local SPRITE,LEVELS=33,6
  local ok,err=pcall(function()
   local c=(SPRITE-1)/2
   local TINTS={{206,190,255},{178,200,255},{255,224,188}}
   local function layer(tint,spikes)
    local base=buffer.create(SPRITE*SPRITE*4)
    local alphaOf=table.create(SPRITE*SPRITE,0)
    for y=0,SPRITE-1 do for x=0,SPRITE-1 do
     local dx,dy=x-c,y-c;local r2=dx*dx+dy*dy
     local core=math.exp(-r2/(2*1.3*1.3))
     local a,w
     if spikes then
      local spikeH=math.exp(-dy*dy/(2*.8*.8))*max(0,1-math.abs(dx)/c)^2.2
      local spikeV=math.exp(-dx*dx/(2*.8*.8))*max(0,1-math.abs(dy)/c)^2.2
      -- faint diagonal glints, much shorter than the main spikes
      local u,v=(dx+dy)*.7071,(dx-dy)*.7071
      local diagA=math.exp(-v*v/(2*.6*.6))*max(0,1-math.abs(u)/(c*.45))^2
      local diagB=math.exp(-u*u/(2*.6*.6))*max(0,1-math.abs(v)/(c*.45))^2
      a=clamp(.95*(spikeH+spikeV)+.28*(diagA+diagB),0,1)
      w=clamp(core*1.6+.25*(spikeH+spikeV),0,1)
     else
      local halo=.32*math.exp(-r2/(2*3.6*3.6))
      a=clamp(core+halo,0,1)
      w=clamp(core*1.6,0,1)
     end
     -- white at the heart, the star's own colour toward the tips and halo
     local i=y*SPRITE+x
     alphaOf[i+1]=a
     writeu32(base,i*4,floor(tint[1]+(255-tint[1])*w+.5)+floor(tint[2]+(255-tint[2])*w+.5)*256+floor(tint[3]+(255-tint[3])*w+.5)*65536)
    end end
    local function imageAt(scale)
     local pixels=buffer.create(SPRITE*SPRITE*4)
     for i=0,SPRITE*SPRITE-1 do writeu32(pixels,i*4,buffer.readu32(base,i*4)+floor(alphaOf[i+1]*scale*255+.5)*16777216) end
     local image=newImage(SPRITE,SPRITE);image:WritePixelsBuffer(Vector2.zero,Vector2.new(SPRITE,SPRITE),pixels)
     return image
    end
    local levels={};for level=1,LEVELS do levels[level]=imageAt(level/LEVELS) end
    return {full=imageAt(1),levels=levels}
   end
   local sets={}
   for index,tint in ipairs(TINTS) do sets[index]={core=layer(tint,false),spike=layer(tint,true)} end
   -- the same sprites seen through frosted glass: gaussian-blurred, a little dimmer
   local function frosted(image)
    local px=image:ReadPixelsBuffer(Vector2.zero,Vector2.new(SPRITE,SPRITE))
    local a,t=table.create(SPRITE*SPRITE,0),table.create(SPRITE*SPRITE,0)
    for i=0,SPRITE*SPRITE-1 do a[i+1]=buffer.readu8(px,i*4+3)/255 end
    local K={};local sum=0;for o=-5,5 do K[o]=math.exp(-o*o/(2*2.1*2.1));sum+=K[o] end;for o=-5,5 do K[o]/=sum end
    for y=0,SPRITE-1 do for x=0,SPRITE-1 do local v=0;for o=-5,5 do local xx=x+o;if xx>=0 and xx<SPRITE then v+=a[y*SPRITE+xx+1]*K[o] end end;t[y*SPRITE+x+1]=v end end
    for y=0,SPRITE-1 do for x=0,SPRITE-1 do local v=0;for o=-5,5 do local yy=y+o;if yy>=0 and yy<SPRITE then v+=t[yy*SPRITE+x+1]*K[o] end end;a[y*SPRITE+x+1]=v end end
    local out=buffer.create(SPRITE*SPRITE*4)
    for i=0,SPRITE*SPRITE-1 do
     local rgb=buffer.readu32(px,i*4)%16777216
     writeu32(out,i*4,rgb+floor(clamp(a[i+1]*1.35,0,1)*.8*255+.5)*16777216)
    end
    local img=newImage(SPRITE,SPRITE);img:WritePixelsBuffer(Vector2.zero,Vector2.new(SPRITE,SPRITE),out)
    return img
   end
   local frost={}
   for index,set in ipairs(sets) do frost[index]={core=frosted(set.core.full),spike=frosted(set.spike.full)} end
   local rng=Random.new()
   local function pickTint() local roll=rng:NextNumber();return roll<.5 and 1 or roll<.8 and 2 or 3 end
   local function rhythm(star)
    local tau=2*pi
    star.w1,star.w2,star.w3=tau*rng:NextNumber(2.6,4.2),tau*rng:NextNumber(5.5,8),tau*rng:NextNumber(.9,1.6)
    star.p1,star.p2,star.p3=rng:NextNumber(0,tau),rng:NextNumber(0,tau),rng:NextNumber(0,tau)
    star.depth=rng:NextNumber(.16,.3)
   end

   -- where the panel's content sits (absolute rects, refreshed a few times a
   -- second while the panel is shown); stars keep out of all of it
   local panel=backdrop.Parent
   local LAYERS={Backdrop=true,Lens=true,Rim=true,EdgeDroplet=true}
   local rects,rectsAt=nil,-math.huge
   local glass={}
   local function refreshRects(now)
    if now-rectsAt<.3 then return end
    rectsAt=now
    if not (panel and backdrop.Visible and panel.Visible and panel.AbsoluteSize.X>0) then return end
    local list,glassList={},{}
    local area=panel.AbsoluteSize.X*panel.AbsoluteSize.Y
    for _,o in ipairs(panel:GetDescendants()) do
     if o:IsA('GuiObject') and o.Visible and not (o.Parent==panel and LAYERS[o.Name]) then
      local drawn=o.BackgroundTransparency<1
      local surface=drawn and o:IsA('Frame') or (drawn and o:IsA('GuiButton'))
      if not drawn and (o:IsA('TextLabel') or o:IsA('TextButton') or o:IsA('TextBox')) then drawn=o.Text~='' and o.TextTransparency<1 end
      if not drawn and (o:IsA('ImageLabel') or o:IsA('ImageButton')) then drawn=o.ImageTransparency<1 end
      local p,s=o.AbsolutePosition,o.AbsoluteSize
      if drawn and s.X>0 and s.Y>0 and s.X*s.Y<area*.35 then
       local x0,y0,x1,y1=p.X,p.Y,p.X+s.X,p.Y+s.Y
       local a=o.Parent;local shown=true
       while a and a~=panel do
        if a.Parent==panel and LAYERS[a.Name] then shown=false;break end
        if a:IsA('GuiObject') then
         if not a.Visible then shown=false;break end
         if a.ClipsDescendants then local q,z=a.AbsolutePosition,a.AbsoluteSize;x0,y0,x1,y1=max(x0,q.X),max(y0,q.Y),min(x1,q.X+z.X),min(y1,q.Y+z.Y) end
        end
        a=a.Parent
       end
       if shown and x1>x0 and y1>y0 then list[#list+1]={x0,y0,x1,y1};if surface then glassList[#glassList+1]={x0,y0,x1,y1} end end
      end
     end
    end
    rects=list;glass=glassList
   end
   local function isFree(fx,fy,size)
    if not rects then return true end
    local p,s=backdrop.AbsolutePosition,backdrop.AbsoluteSize
    local k=s.X/max(1,root.Size.X.Offset)
    local x,y=p.X+fx*s.X,p.Y+fy*s.Y
    local r=.38*size*k+3
    for _,b in ipairs(rects) do
     if x+r>b[1] and x-r<b[3] and y+r>b[2] and y-r<b[4] then return false end
    end
    return true
   end

   local list={}
   -- how much of a star sits behind glass (rows, tabs, buttons): 0..1 of its box
   local function scaleK() local s=backdrop.AbsoluteSize;return s.X/max(1,root.Size.X.Offset) end
   local function coverOf(star)
    local p,s=backdrop.AbsolutePosition,backdrop.AbsoluteSize
    local k=scaleK();if k<=0 then return 0 end
    local x,y=p.X+star.fx*s.X,p.Y+star.fy*s.Y
    local r=star.size*.45*k
    local covered=0
    for _,b in ipairs(glass) do
     local w,h=min(x+r,b[3])-max(x-r,b[1]),min(y+r,b[4])-max(y-r,b[2])
     if w>0 and h>0 then covered+=w*h end
    end
    return clamp(covered/(4*r*r),0,1)
   end
   local function place(star)
    star.tint=pickTint();rhythm(star)
    local fx,fy=rng:NextNumber(.07,.93),rng:NextNumber(.06,.94)
    star.fx,star.fy,star.open=fx,fy,true
    local set,fz=sets[star.tint],frost[star.tint]
    star.core.ImageContent=Content.fromObject(set.core.full);star.spike.ImageContent=Content.fromObject(set.spike.full)
    star.blurCore.ImageContent=Content.fromObject(fz.core);star.blurSpike.ImageContent=Content.fromObject(fz.spike)
    star.core.Position=UDim2.fromScale(fx,fy);star.spike.Position=star.core.Position
    star.blurCore.Position=star.core.Position;star.blurSpike.Position=star.core.Position
    star.coverTarget=coverOf(star);star.cover=star.coverTarget
   end
   -- A star behind glass is seen blurred, in the gaps sharp; one that straddles an
   -- edge shows both in proportion, and any change fades over ~0.2 s (no hard
   -- clipped halves, nothing that switches in a single frame).
   local function paint(star,dt)
    star.cover+=(star.coverTarget-star.cover)*min(1,(dt or 0)*10)
    local c=star.cover
    local coreA,spikeA=1-star.core.ImageTransparency,1-star.spike.ImageTransparency
    star.blurCore.Size=star.core.Size;star.blurSpike.Size=star.spike.Size
    star.blurCore.ImageTransparency=1-coreA*c;star.blurSpike.ImageTransparency=1-spikeA*c
    star.core.ImageTransparency=1-coreA*(1-c);star.spike.ImageTransparency=1-spikeA*(1-c)
   end
   for index=1,10 do
    local spike=create('ImageLabel',{Name='Star'..index,BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),ImageTransparency=1,Size=UDim2.fromOffset(0,0),Parent=backdrop})
    local core=create('ImageLabel',{Name='StarCore'..index,BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),ImageTransparency=1,Size=UDim2.fromOffset(0,0),Parent=backdrop})
    local blurSpike=create('ImageLabel',{Name='StarBlur'..index,BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),ImageTransparency=1,Size=UDim2.fromOffset(0,0),Parent=backdrop})
    local blurCore=create('ImageLabel',{Name='StarBlurCore'..index,BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),ImageTransparency=1,Size=UDim2.fromOffset(0,0),Parent=backdrop})
    passThrough(spike);passThrough(core);passThrough(blurSpike);passThrough(blurCore)
    local star={blurCore=blurCore,blurSpike=blurSpike,cover=0,coverTarget=0,core=core,spike=spike,size=rng:NextNumber(16,26),peak=rng:NextNumber(.55,.95),period=rng:NextNumber(3.2,6.5),lit=rng:NextNumber(.28,.42),phase=rng:NextNumber(0,10),cycle=-1,fx=.5,fy=.5,open=false,shown=1,tint=1,coreA=0,spikeA=0,coreS=0,spikeS=0}
    rhythm(star);list[#list+1]=star
   end
   -- bubble stars: offsets from the bubble's centre in panel units
   local bubbleList={}
   local BUBBLE_REACH=(Layout.bubbleSize or 76)/2*.56
   local function placeInBubble(star)
    star.tint=pickTint();rhythm(star)
    for _=1,16 do
     local a,d=rng:NextNumber(0,2*pi),BUBBLE_REACH*math.sqrt(rng:NextNumber())
     local dx,dy=math.cos(a)*d,math.sin(a)*d
     local apart=true
     for _,other in ipairs(bubbleList) do
      if other~=star and (other.dx-dx)^2+(other.dy-dy)^2<14*14 then apart=false;break end
     end
     if apart then star.dx,star.dy,star.open=dx,dy,true;return end
    end
    star.open=false
   end
   for _=1,3 do
    local star={size=rng:NextNumber(10,14),peak=rng:NextNumber(.6,.9),period=rng:NextNumber(4,7),lit=rng:NextNumber(.3,.4),phase=rng:NextNumber(0,10),cycle=-1,dx=0,dy=0,open=false,shown=1,tint=1,coreA=0,spikeA=0,coreS=0,spikeS=0}
    rhythm(star);bubbleList[#bubbleList+1]=star
   end

   -- brightness of one star at `now`: the slow fade envelope times the
   -- scintillation. `steady` leaves out the fastest rhythm for the marble
   -- pictures, which are rebuilt 12-24 times a second and would alias it.
   local function brightness(star,now,steady)
    local t=(now+star.phase)/star.period
    local u=(t-floor(t))/star.lit
    local env=u<1 and math.sin(pi*u)^2 or 0
    if env<=0 then return 0 end
    local n=steady and (.6*math.sin(now*star.w1+star.p1)+.4*math.sin(now*star.w3+star.p3))
     or (.45*math.sin(now*star.w1+star.p1)+.3*math.sin(now*star.w2+star.p2)+.25*math.sin(now*star.w3+star.p3))
    return env*(1+star.depth*n)
   end
   local function shape(star,b)
    -- the core brightens gently; the spikes carry the flicker and reach
    -- further out the brighter the star is
    local lit=b*star.shown
    star.coreA=min(1,star.peak*lit^.8);star.spikeA=min(1,star.peak*lit)
    star.coreS=.7+.3*min(1,lit);star.spikeS=.3+.75*min(1.2,lit)^.7
   end
   local function cycleOf(star,now,move)
    local cycle=floor((now+star.phase)/star.period)
    if cycle~=star.cycle then
     -- each new cycle starts dark: move the star somewhere new
     star.cycle=cycle;move(star)
    end
   end
   local last=nil
   local function update(now)
    local dt=last and clamp(now-last,0,.1) or 0;last=now
    refreshRects(now)
    local checked=rectsAt==now
    for _,star in ipairs(list) do
     cycleOf(star,now,place)
     -- content moved over a lit star (scroll, tab change): let it fade out
     if checked and star.open then star.coverTarget=coverOf(star) end
     star.shown+=((star.open and 1 or 0)-star.shown)*min(1,dt*10)
     shape(star,brightness(star,now,false))
     star.spike.ImageTransparency=1-star.spikeA;star.core.ImageTransparency=1-star.coreA
     star.spike.Size=UDim2.fromOffset(star.size*star.spikeS,star.size*star.spikeS)
     star.core.Size=UDim2.fromOffset(star.size*star.coreS,star.size*star.coreS)
     paint(star,dt)
     -- the marble pictures use the steadier brightness
     shape(star,brightness(star,now,true))
    end
    for _,star in ipairs(bubbleList) do
     cycleOf(star,now,placeInBubble)
     star.shown=star.open and 1 or 0
     shape(star,brightness(star,now,true))
    end
   end
   local function level(a) return math.clamp(math.ceil(a*LEVELS-.25),1,LEVELS) end
   -- draw one star into a marble image (px,py: centre in image space before the
   -- tile offset tx,ty; k: image pixels per panel unit); clipped to the region
   local function draw(image,star,px,py,k,tx,ty,rx0,ry0,rx1,ry1)
    local reach=star.size*k*.6
    if px+reach<=rx0 or px-reach>=rx1 or py+reach<=ry0 or py-reach>=ry1 then return end
    local set=sets[star.tint]
    if star.spikeA>.03 then local s=star.size*star.spikeS*k/SPRITE;image:DrawImageTransformed(Vector2.new(px-tx,py-ty),Vector2.new(s,s),0,set.spike.levels[level(star.spikeA)],{CombineType=OVER}) end
    if star.coreA>.03 then local s=star.size*star.coreS*k/SPRITE;image:DrawImageTransformed(Vector2.new(px-tx,py-ty),Vector2.new(s,s),0,set.core.levels[level(star.coreA)],{CombineType=OVER}) end
   end
   local function free()
    for _,set in ipairs(frost) do set.core:Destroy();set.spike:Destroy() end
    for _,set in ipairs(sets) do for _,part in ipairs({set.core,set.spike}) do
     part.full:Destroy();for _,image in ipairs(part.levels) do image:Destroy() end
    end end
   end
   Liquid.stars={list=list,bubble=bubbleList,update=update,draw=draw,free=free}
  end)
  if not ok then warn('[LiquidStars] unavailable',err) end
 end

 -- Per-size static layers: base gradient (with the extension margin fading to
 -- ink), gloss/vignette, orb sprites and pre-scaled tinted lava tiles.
 local function build(Wp,Hp,yield,resolve)
  local k=Wp/max(1,root.Size.X.Offset)
  local BW,BH=ceil(Wp)+2*MARGIN,ceil(Hp)+2*MARGIN
  local baseBuf,topBuf=buffer.create(BW*BH*4),buffer.create(BW*BH*4)
  local lr,lg,lb={},{},{}
  local baseSeq=baseGradient and baseGradient.Color
  if resolve and baseSeq then local keys={};for i,p in ipairs(baseSeq.Keypoints) do keys[i]=ColorSequenceKeypoint.new(p.Time,resolve(p.Value)) end;baseSeq=ColorSequence.new(keys) end
  for i=0,1023 do local c=baseSeq and seqColor(baseSeq,i/1023) or Theme.tint;lr[i],lg[i],lb[i]=byte(c.R),byte(c.G),byte(c.B) end
  local angle=math.rad(baseGradient and baseGradient.Rotation or 0);local cb,sb=cos(angle),sin(angle)
  local ink=Theme.ink or INK;local ir,ig,ib=byte(ink.R),byte(ink.G),byte(ink.B)
  local slice=os.clock()
  for j=0,BH-1 do
   local py=j-MARGIN+.5;local v=clamp(py/Hp,0,1);local dy=max(0,-py,py-Hp)
   -- top layers depend only on the row: composite them into one straight-alpha colour
   local ta,tr,tg,tb=0,0,0,0
   for _,layer in ipairs(topLayers) do
    if v>=layer.y and v<=layer.y+layer.h then
     local a=1-seqValue(layer.transparency,(v-layer.y)/layer.h)
     if a>0 then
      local outA=a+ta*(1-a)
      tr=(layer.color.R*a+tr*ta*(1-a))/outA;tg=(layer.color.G*a+tg*ta*(1-a))/outA;tb=(layer.color.B*a+tb*ta*(1-a))/outA;ta=outA
     end
    end
   end
   local topRGB=byte(tr)+byte(tg)*256+byte(tb)*65536
   local rowT=.5+(v-.5)*sb
   for i=0,BW-1 do
    local px=i-MARGIN+.5;local dx=max(0,-px,px-Wp)
    local idx=round(clamp(rowT+(clamp(px/Wp,0,1)-.5)*cb,0,1)*1023)
    local r,g,b=lr[idx],lg[idx],lb[idx];local fade=0
    if dx>0 or dy>0 then local d=min(1,sqrt(dx*dx+dy*dy)/MARGIN);fade=d*d*(3-2*d);r=round(r+(ir-r)*fade);g=round(g+(ig-g)*fade);b=round(b+(ib-b)*fade) end
    local off=(j*BW+i)*4
    writeu32(baseBuf,off,r+g*256+b*65536+4278190080)
    if ta>0 then writeu32(topBuf,off,topRGB+round(ta*(1-fade)*255)*16777216) end
   end
   if yield and os.clock()-slice>.002 then task.wait();slice=os.clock() end
  end
  local result={w=Wp,h=Hp,k=k,bw=BW,bh=BH,orbs={},lava={},veins={},textured=texture~=nil}
  result.base=newImage(BW,BH);result.base:WritePixelsBuffer(Vector2.zero,Vector2.new(BW,BH),baseBuf)
  result.top=newImage(BW,BH);result.top:WritePixelsBuffer(Vector2.zero,Vector2.new(BW,BH),topBuf)
  for i,orb in ipairs(orbData) do
   local sprite=orbSprites[i]
   result.orbs[#result.orbs+1]={frame=orb.frame,image=sprite.image,size=sprite.size}
  end
  for _,vein in ipairs(veinData) do
   local L=vein.frame.Size.X.Scale*Wp
   local length=ceil((vein.hi-vein.lo)*L/.7)+4
   result.veins[#result.veins+1]={length=length,buf=buffer.create(length*BLOCK*4),rows=newImage(length,BLOCK),cols=newImage(BLOCK,length)}
  end
  if texture then
   local tile=texture.Size.X/2
   for _,layer in ipairs(lavaLayers) do
    local label=layer.label;local scale=Wp/max(1e-3,label.ImageRectSize.X)
    local period=max(4,round(tile*scale));local s=period/tile
    local subs=tiled(period,period,128)
    for _,sub in ipairs(subs) do
     -- sub-pixel 0 of the tile is texel tile/2, keeping bilinear taps inside the 2x2 texture
     sub.image:DrawImageTransformed(Vector2.new(tile/2*s-sub.x,tile/2*s-sub.y),Vector2.new(s,s),0,texture,{CombineType=WRITE})
     sub.image:DrawRectangle(Vector2.zero,Vector2.new(sub.w,sub.h),resolve and resolve(label.ImageColor3) or label.ImageColor3,label.ImageTransparency,MUL)
    end
    result.lava[#result.lava+1]={label=label,scale=Wp/max(1e-3,label.ImageRectSize.X),period=period,anchor=tile/2,subs=subs}
    if yield then task.wait() end
   end
  end
  return result
 end
 local function release(set)
  if not set then return end
  set.base:Destroy();set.top:Destroy()
  for _,vein in ipairs(set.veins) do vein.rows:Destroy();vein.cols:Destroy() end
  for _,lava in ipairs(set.lava) do destroyTiles(lava.subs) end
 end
 local function panelSize() return Vector2.new(root.Size.X.Offset,root.Size.Y.Offset)*Layout.uiScale end
 m.panelSize=panelSize
 local function matches(set,size) return set~=nil and set.textured==(texture~=nil) and math.abs(set.w-size.X)<.5 and math.abs(set.h-size.Y)<.5 end
 -- A theme change recolours the backdrop instances; read their colours again,
 -- re-bake the orb glows in place and rebuild the per-size layers.
 -- resolve(colour) -> colour maps the window's current colours to the target
 -- palette (nil: read the live colours); onDone runs once the new marble is live.
 function m.recolor(resolve,onDone)
  m.recolorToken=(m.recolorToken or 0)+1
  local token=m.recolorToken
  local function res(c) if resolve then return resolve(c) end;return c end
  task.spawn(function()
   for i,orb in ipairs(orbData) do
    local ring=orb.frame:FindFirstChildWhichIsA('Frame')
    if ring then orb.color=res(ring.BackgroundColor3) end
    local sprite=orbSprites[i]
    if sprite then
     local buf=orbPixels(orb,sprite.size,sprite.D,true)
     if token~=m.recolorToken then return end
     sprite.image:WritePixelsBuffer(Vector2.zero,Vector2.new(sprite.size,sprite.size),buf)
    end
   end
   for _,vein in ipairs(veinData) do local c=res(vein.frame.BackgroundColor3);vein.rgb=byte(c.R)+byte(c.G)*256+byte(c.B)*65536 end
   for _,layer in ipairs(topLayers) do layer.color=res(layer.instance.BackgroundColor3) end
   local size=panelSize()
   local ok,new=pcall(build,size.X,size.Y,true,resolve)
   if not ok then return end
   if token~=m.recolorToken then release(new);return end
   local old=assets;assets=new
   if old then task.delay(1,release,old) end
   m.invalidateSheet()
   if onDone then onDone() end
  end)
 end
 Resize.recolorMaterial=m.recolor
 -- Fast recolour (Rainbow): re-tint the coloured layers with native image ops
 -- only: orb glows from their white copies, the lava tiles from the texture,
 -- veins and gloss by value. The base gradient is left as built (its tones are
 -- near-neutral); a full recolor() refreshes it now and then.
 function m.recolorFast(resolve,withLava)
  if not assets then return end
  for i,orb in ipairs(orbData) do
   local sprite=orbSprites[i]
   local ring=orb.frame:FindFirstChildWhichIsA('Frame')
   if sprite and sprite.white and ring then
    orb.color=resolve(ring.BackgroundColor3)
    local size=Vector2.new(sprite.size,sprite.size)
    sprite.image:DrawImageTransformed(size/2,Vector2.one,0,sprite.white,{CombineType=WRITE})
    sprite.image:DrawRectangle(Vector2.zero,size,orb.color,0,MUL)
   end
  end
  for _,vein in ipairs(veinData) do local c=resolve(vein.frame.BackgroundColor3);vein.rgb=byte(c.R)+byte(c.G)*256+byte(c.B)*65536 end
  for _,layer in ipairs(topLayers) do layer.color=resolve(layer.instance.BackgroundColor3) end
  -- lava strips are re-tinted a couple per frame (queued), the sheet refreshes on its own
  if texture and withLava and not (m.lavaQueue and #m.lavaQueue>0) then
   local queue={}
   for _,lava in ipairs(assets.lava) do
    local color=resolve(lava.label.ImageColor3)
    for _,piece in ipairs(lava.subs) do queue[#queue+1]={lava,piece,color} end
   end
   m.lavaQueue=queue;m.lavaAssets=assets
  end
 end
 track(RunService.Heartbeat:Connect(function()
  local queue=m.lavaQueue
  if not queue or #queue==0 or not texture then return end
  if m.lavaAssets~=assets then m.lavaQueue=nil;return end
  local tile=texture.Size.X/2
  do
   local item=table.remove(queue);if not item then return end
   local lava,piece,color=item[1],item[2],item[3]
   local s=lava.period/tile
   piece.image:DrawImageTransformed(Vector2.new(tile/2*s-piece.x,tile/2*s-piece.y),Vector2.new(s,s),0,texture,{CombineType=WRITE})
   piece.image:DrawRectangle(Vector2.zero,Vector2.new(piece.w,piece.h),color,lava.label.ImageTransparency,MUL)
  end
 end))
 Resize.recolorMaterialFast=m.recolorFast
 function m.prepare(size)
  if matches(assets,size) then return end
  local old=assets;assets=build(size.X,size.Y,false);release(old)
 end

 -- Draw every layer for panel-space origin (ox, oy) into a set of image tiles,
 -- limited to the region [x0,x1) x [y0,y1) in target pixels.
 -- Each vein is a soft band across a rotated frame: one 1-D strip per update,
 -- blitted every BLOCK rows (or columns for steep angles) at its sheared offset.
 local function prepareVeins(A,ox,oy)
  for i,vein in ipairs(veinData) do
   local strip=A.veins[i];local frame=vein.frame
   local angle=math.rad(frame.Rotation);local c,s=cos(angle),sin(angle)
   local L=frame.Size.X.Scale*A.w;local offset=vein.gradient.Offset.X
   local lo,hi=(vein.lo+offset-.5)*L,(vein.hi+offset-.5)*L
   local rowsMode=math.abs(c)>=math.abs(s);local dir=rowsMode and c or s
   local start=dir>0 and lo or hi
   local used=min(strip.length,ceil((hi-lo)/math.abs(dir))+2)
   local buf,lut,rgb,n=strip.buf,vein.lut,vein.rgb,strip.length
   buffer.fill(buf,0,0)
   for j=0,used-1 do
    local a=lut[round(((start+(j+.5)*dir)/L+.5-offset)*LUT)]
    if a and a>0 then
     local value=rgb+round(a*255)*16777216
     if rowsMode then for r=0,BLOCK-1 do writeu32(buf,(r*n+j)*4,value) end else for r=0,BLOCK-1 do writeu32(buf,(j*BLOCK+r)*4,value) end end
    end
   end
   if rowsMode then strip.rows:WritePixelsBuffer(Vector2.zero,Vector2.new(n,BLOCK),buf) else strip.cols:WritePixelsBuffer(Vector2.zero,Vector2.new(BLOCK,n),buf) end
   strip.rowsMode,strip.c,strip.s,strip.start,strip.used=rowsMode,c,s,start,used
   strip.ccx,strip.ccy=ox+frame.Position.X.Scale*A.w,oy+frame.Position.Y.Scale*A.h
  end
 end
 -- withTop=false leaves gloss/vignette to the panel's own GUI frames (plain vertical
 -- gradients drawn by the GPU on top of the composite).
 local scratchImage=nil
 local function smoothScratch(w,h)
  if not scratchImage or scratchImage.Size.X<w or scratchImage.Size.Y<h then
   if scratchImage then scratchImage:Destroy() end
   scratchImage=newImage(min(LIMIT,ceil(w/32)*32),min(LIMIT,ceil(h/32)*32))
  end
  scratchImage:DrawRectangle(Vector2.zero,scratchImage.Size,INK,1,WRITE)
  return scratchImage
 end
 -- smooth=true places the lava at sub-pixel positions (bilinear); used for the
 -- small idle bubble, where whole-pixel steps of the slow creep would show.
 local function compose(targetTiles,ox,oy,x0,y0,x1,y1,readback,stride,withTop,smooth,bubble)
  local A=assets;local Wp,Hp=A.w,A.h
  local bx,by=round(ox)-MARGIN,round(oy)-MARGIN
  prepareVeins(A,ox,oy)
  for _,T in ipairs(targetTiles) do
   local rx0,ry0,rx1,ry1=max(x0,T.x),max(y0,T.y),min(x1,T.x+T.w),min(y1,T.y+T.h)
   if rx1>rx0 and ry1>ry0 then
    local image,tx,ty=T.image,T.x,T.y
    image:DrawRectangle(Vector2.new(rx0-tx,ry0-ty),Vector2.new(rx1-rx0,ry1-ry0),INK,0,WRITE)
    image:DrawImage(Vector2.new(bx-tx,by-ty),A.base,WRITE)
    pace()
    for _,orb in ipairs(A.orbs) do
     local position=orb.frame.Position
     local cx0,cy0=ox+position.X.Scale*Wp+position.X.Offset*A.k,oy+position.Y.Scale*Hp+position.Y.Offset*A.k
     image:DrawImage(Vector2.new(round(cx0-orb.size/2)-tx,round(cy0-orb.size/2)-ty),orb.image,OVER)
    end
    pace()
    for _,strip in ipairs(A.veins) do
     if strip.rowsMode then
      for yb=ry0,ry1-1,BLOCK do
       local xs=round(strip.ccx+(strip.start-(yb+BLOCK/2-strip.ccy)*strip.s)/strip.c)
       if xs<rx1 and xs+strip.used>rx0 then image:DrawImage(Vector2.new(xs-tx,yb-ty),strip.rows,OVER) end
      end
     else
      for xb=rx0,rx1-1,BLOCK do
       local ys=round(strip.ccy+(strip.start-(xb+BLOCK/2-strip.ccx)*strip.c)/strip.s)
       if ys<ry1 and ys+strip.used>ry0 then image:DrawImage(Vector2.new(xb-tx,ys-ty),strip.cols,OVER) end
      end
     end
    end
    pace()
    for _,lava in ipairs(A.lava) do
     local rectOffset=lava.label.ImageRectOffset;local P=lava.period
     local gx,gy=ox+(lava.anchor-rectOffset.X)*lava.scale,oy+(lava.anchor-rectOffset.Y)*lava.scale
     if smooth then
      -- Tile the lava seamlessly at whole pixels into a scratch one pixel larger
      -- than the region on every side, then place that scratch once at the
      -- sub-pixel remainder. Only the scratch's own border is resampled, and it
      -- lies outside the region, so no seam can appear inside.
      local fx,fy=gx-floor(gx),gy-floor(gy)
      local sx0,sy0=rx0-1,ry0-1
      local scratch=smoothScratch(rx1-rx0+2,ry1-ry0+2)
      local ix,iy=floor(gx),floor(gy)
      for ky=floor((sy0-iy)/P),floor((ry1-iy)/P) do for kx=floor((sx0-ix)/P),floor((rx1-ix)/P) do
       for _,sub in ipairs(lava.subs) do scratch:DrawImage(Vector2.new(ix+kx*P+sub.x-sx0,iy+ky*P+sub.y-sy0),sub.image,WRITE) end
      end end
      local size=scratch.Size
      image:DrawImageTransformed(Vector2.new(sx0+fx+size.X/2-tx,sy0+fy+size.Y/2-ty),Vector2.one,0,scratch,{CombineType=OVER})
     else
      for ky=floor((ry0-gy)/P),floor((ry1-1-gy)/P) do for kx=floor((rx0-gx)/P),floor((rx1-1-gx)/P) do
       local px,py=round(gx+kx*P),round(gy+ky*P)
       for _,sub in ipairs(lava.subs) do image:DrawImage(Vector2.new(px+sub.x-tx,py+sub.y-ty),sub.image,OVER) end
      end end
     end
     pace()
    end
    -- twinkling stars (shared with the panel; the bubble adds its own)
    local stars=Liquid.stars
    if stars then
     local k=A.k
     for _,star in ipairs(stars.list) do stars.draw(image,star,ox+star.fx*Wp,oy+star.fy*Hp,k,tx,ty,rx0,ry0,rx1,ry1) end
     if bubble then for _,star in ipairs(stars.bubble) do stars.draw(image,star,ox+Wp/2+star.dx*k,oy+Hp/2+star.dy*k,k,tx,ty,rx0,ry0,rx1,ry1) end end
    end
    if withTop then image:DrawImage(Vector2.new(bx-tx,by-ty),A.top,OVER) end
    if readback then
     local w,h=rx1-rx0,ry1-ry0
     local data=image:ReadPixelsBuffer(Vector2.new(rx0-tx,ry0-ty),Vector2.new(w,h))
     for yy=0,h-1 do copy(readback,((ry0+yy)*stride+rx0)*4,data,yy*w*4,w*4) end
    end
   end
  end
 end

 -- Liquid canvas: one material target per cached surface, read back for the shader.
 local current=nil
 function m.bind(surface)
  if not surface.material then surface.material={tiles=tiled(surface.w,surface.h),pixels=buffer.create(surface.w*surface.h*4)} end
  current=surface.material
 end
 function m.unbind(surface) if surface.material then if surface.material==current then m.sheetTask=nil end;destroyTiles(surface.material.tiles);if surface.material.back then destroyTiles(surface.material.back.tiles) end;surface.material=nil end end
 -- During minimize/un-minimize the marble is built once per refresh in panel space
 -- (the panel plus SHEET_MARGIN around it) and every liquid frame reads it at
 -- the liquid's current offset. Layer blits cost the whole target image no matter
 -- how small the liquid is, so building it per frame wasted most of the time.
 -- It refreshes up to SHEET_RATE times a second from the live layers: the marble
 -- keeps flowing and drifts under a pixel between refreshes. The idle bubble
 -- (small canvas, sub-pixel lava) still composes every update.
 local SHEET_MARGIN,SHEET_RATE=96,12
 -- Two sheets: liquid pictures read `sheet` while the next one is built in
 -- `spare` by a background task (m.sheetTask, resumed by the transition loop
 -- under its own small slice of the frame budget) and swapped in when done.
 -- A refresh therefore never holds up a picture. Only a stale sheet (the
 -- first picture of a transition) is rebuilt inline.
 local sheet,spare=nil,nil
 m.sheetTask=nil
 function m.invalidateSheet()
  m.sheetTask=nil
  if sheet then sheet.time=-math.huge end
 end
 local function newSheet(SW,SH)
  -- short strips: every layer blit only touches one strip, so the work splits
  -- into small pieces the frame budget can spread out
  return {w=SW,h=SH,tiles=tiled(SW,SH,128),pixels=buffer.create(SW*SH*4),time=-math.huge}
 end
 local function composeSheet(ox,oy)
  local SW,SH=ceil(assets.w)+2*SHEET_MARGIN,ceil(assets.h)+2*SHEET_MARGIN
  if not sheet or sheet.w~=SW or sheet.h~=SH then
   m.sheetTask=nil
   if sheet then destroyTiles(sheet.tiles) end
   if spare then destroyTiles(spare.tiles);spare=nil end
   sheet=newSheet(SW,SH)
  end
  local now=os.clock()
  if now-sheet.time>.25 then
   m.sheetTask=nil
   sheet.time=now
   compose(sheet.tiles,SHEET_MARGIN,SHEET_MARGIN,0,0,SW,SH,sheet.pixels,SW,true,false)
  elseif now-sheet.time>=1/SHEET_RATE and not m.sheetTask then
   if not spare or spare.w~=SW or spare.h~=SH then if spare then destroyTiles(spare.tiles) end;spare=newSheet(SW,SH) end
   local target,front=spare,sheet
   m.sheetTask=coroutine.create(function()
    compose(target.tiles,SHEET_MARGIN,SHEET_MARGIN,0,0,SW,SH,target.pixels,SW,true,false)
    if sheet==front then target.time=os.clock();spare=front;sheet=target end
   end)
  end
  return sheet.pixels,round(ox)-SHEET_MARGIN,round(oy)-SHEET_MARGIN,SW,SH
 end
 -- The panel's own liquid pieces (edge droplets, header bubble) read the same
 -- live sheet: (px,py) is where the panel's top-left corner sits in their image.
 function m.sheetAt(px,py)
  if not assets then return nil end
  return composeSheet(px,py)
 end
 -- Idle bubble: the marble drifts slowly, so it is rebuilt BUBBLE_RATE times a
 -- second in the background (into a second buffer, swapped in when done) while
 -- the outline itself redraws every frame from the latest finished marble.
 local BUBBLE_RATE=24
 local function composeBubble()
  local target=current
  if not target.back then target.back={tiles=tiled(OW,OH),pixels=buffer.create(OW*OH*4)};target.time=-math.huge end
  local now=os.clock()
  if now-target.time>.25 or target.ox~=m.ox or target.oy~=m.oy then
   m.sheetTask=nil
   target.time=now;target.ox,target.oy=m.ox,m.oy
   compose(target.tiles,m.ox,m.oy,0,0,OW,OH,target.pixels,OW,true,true,true)
  elseif now-target.time>=1/BUBBLE_RATE and not m.sheetTask then
   -- the size is captured now: the task may still be running after the
   -- renderer has switched to another (larger) surface
   local back,ox,oy,w,h=target.back,m.ox,m.oy,OW,OH
   m.sheetTask=coroutine.create(function()
    compose(back.tiles,ox,oy,0,0,w,h,back.pixels,w,true,true,true)
    if current==target and target.back==back and target.ox==ox and target.oy==oy then
     target.back={tiles=target.tiles,pixels=target.pixels}
     target.tiles,target.pixels=back.tiles,back.pixels;target.time=os.clock()
    end
   end)
  end
  return target.pixels,0,0,OW,OH
 end
 function m.compose(x0,y0,x1,y1)
  if not assets or not current then return nil end
  if state=='morph' then return composeSheet(m.ox,m.oy) end
  if state=='bubble' then return composeBubble() end
  compose(current.tiles,m.ox,m.oy,x0,y0,x1,y1,current.pixels,OW,true,false)
  return current.pixels,0,0,OW,OH
 end

 function m.newTarget(w,h) return {tiles=tiled(w,h),pixels=buffer.create(w*h*4),w=w} end
 function m.freeTarget(target) destroyTiles(target.tiles) end
 function m.composeTarget(target,ox,oy,x0,y0,x1,y1,smooth)
  if not assets or not matches(assets,panelSize()) then return nil end
  compose(target.tiles,ox,oy,x0,y0,x1,y1,target.pixels,target.w,true,smooth)
  return target.pixels,0,0,target.w,#target.tiles>0 and buffer.len(target.pixels)/4/target.w or 0
 end

 -- Keep the static layers ready for the panel's current size, so a transition
 -- never has to build them. A resize is picked up once it has settled.
 local dirtySince=nil
 local elapsed=0
 track(RunService.RenderStepped:Connect(function(dt)
  if stopped or m.building then return end
  elapsed+=dt;if elapsed<CHECK then return end;elapsed=0
  local size=panelSize()
  if matches(assets,size) then dirtySince=nil;return end
  dirtySince=dirtySince or os.clock()
  if os.clock()-dirtySince<.35 or state~='panel' then return end
  m.building=true
  task.spawn(function()
   local ok,err=pcall(function()
    local built=build(size.X,size.Y,true)
    if stopped or matches(assets,size) then release(built) else local old=assets;assets=built;release(old) end
   end)
   if not ok then warn('[LiquidMaterial]',err) end
   m.building=false;dirtySince=nil
  end)
 end))

 task.spawn(function()
  local ok,err=pcall(function()
   local label=backdrop:FindFirstChild('MarbleLava1')
   if label then texture=AS:CreateEditableImageAsync(Content.fromUri(label.Image)) end
  end)
  if not ok then warn('[LiquidMaterial] lava texture unavailable',err) end
 end)
 function m.destroy()
  local stars=Liquid.stars
  if stars then Liquid.stars=nil;stars.free() end
  release(assets);assets=nil
  for _,sprite in ipairs(orbSprites) do sprite.image:Destroy() end
  m.sheetTask=nil
  if sheet then destroyTiles(sheet.tiles);sheet=nil end
  if spare then destroyTiles(spare.tiles);spare=nil end
  if scratchImage then scratchImage:Destroy();scratchImage=nil end
  if texture then texture:Destroy();texture=nil end
 end
 return m
end)()
-- Shared mask: scan-converted body and circles, separable blur, threshold, shaded rim.
-- Same field and shading as the approved prototype; the work is bounded to where
-- the field actually changes (the band around the outline), not the whole box.
local mask=table.create(W*H,0);local temp=table.create(W*H,0);local pixels=buffer.create(OW*OH*4)
local zeros=table.create(W*H,0);local ones=table.create(W,1)
local write,readu32=buffer.writeu32,buffer.readu32
local band,rshift=bit32.band,bit32.rshift
local baseColors,phaseX,phaseY={},{},{}
local phaseTint,shades={},{}
local phaseScale=4096/(2*math.pi)
for i=0,4095 do
 local tint=.5+.5*math.sin(i/phaseScale)
 phaseTint[i]=floor(tint*31+.5)
 baseColors[i]=floor(27+11*tint)+floor(23+7*tint)*256+floor(40+16*tint)*65536+184*16777216
end
for x=0,OW-1 do phaseX[x]=floor(x*.008*phaseScale) end
for y=0,OH-1 do phaseY[y]=floor(y*.006*phaseScale) end
local interiorRamp=buffer.create(2048*4)
for x=0,2047 do write(interiorRamp,x*4,baseColors[floor(x*.008*phaseScale)%4096]) end
-- rimWide keeps the rim at full light for one extra px before it falls off, so
-- liquid bubbles wear a rim 1px wider; rim-only overlays keep rimBase.
local rimBase,rimWide,broadLookup={},{},{}
for i=0,2048 do rimBase[i]=math.exp(-i/32*.8);rimWide[i]=math.exp(-math.max(0,i/32-1)*.8);broadLookup[i]=math.exp(-i/32*.13)*.22 end
local rimLookup=rimWide
for t=0,31 do for light=0,127 do
 local tint=t/31;local shine=light/127
 shades[t+light*32]=floor(27+11*tint+shine*195)+floor(23+7*tint+shine*189)*256+min(255,floor(40+16*tint+shine*205))*65536
end end
-- Rim light colour. The liquid blends toward it by `shine`; the open panel's rim
-- overlay uses the same colour with alpha = shine, so both produce equal pixels.
local RIM_R,RIM_G,RIM_B=226,214,246
Resize.themeHooks=Resize.themeHooks or {}
table.insert(Resize.themeHooks,function(T) local c=T.mist;RIM_R,RIM_G,RIM_B=math.round(c.R*255),math.round(c.G*255),math.round(c.B*255) end)
local rimMode=false
-- Material source for this render: buffer `mat` of matW x matH pixels whose
-- origin sits at (matX, matY) in output pixels. Outside it the liquid is ink.
local matX,matY,matW,matH=0,0,0,0
local INNER_SHADE=4
local INK_PIXEL=7+7*256+10*65536+255*16777216
local inkRow=buffer.create(4096*4)
for x=0,4095 do write(inkRow,x*4,INK_PIXEL) end
-- Past the edge of the material the texture is mirrored, never cut to ink, so a
-- liquid stretched beyond the material area shows no hard line.
local function mirror(v,n)
 if v<0 then v=-v-1 elseif v>=n then v=2*n-v-1 end
 if v<0 then return 0 elseif v>=n then return n-1 end
 return v
end
local function copyMaterial(mat,y,x,length)
 local dst=(y*OW+x)*4
 local base=mirror(y-matY,matH)*matW
 local sx0=x-matX;local sx1=sx0+length
 local a,b=max(0,sx0),min(matW,sx1)
 if b>a then copy(pixels,dst+(a-sx0)*4,mat,(base+a)*4,(b-a)*4) end
 for sx=sx0,min(sx1,0)-1 do write(pixels,dst+(sx-sx0)*4,readu32(mat,(base+mirror(sx,matW))*4)) end
 for sx=max(sx0,matW),sx1-1 do write(pixels,dst+(sx-sx0)*4,readu32(mat,(base+mirror(sx,matW))*4)) end
end
-- The blur is three box passes of about 6 px radius: BR cells at S px per cell.
-- KS is the combined kernel's reach in cells. edgeStep[z] is that kernel's response
-- to a cell-covered edge at distance z; it is piecewise linear between integers,
-- so interpolating it is exact. This replaces three passes per row.
local BR=S>=3 and 2 or 3
local KS,BN=3*BR,2*BR+1
local CO=floor(S/2)
local TX0=(CO+.5-S/2)/S
local edgeStep={}
do
 local kernel={[0]=1}
 for _=1,3 do
  local nextKernel={}
  for k,v in pairs(kernel) do for j=-BR,BR do nextKernel[k+j]=(nextKernel[k+j] or 0)+v/BN end end
  kernel=nextKernel
 end
 for z=-KS-1,KS+1 do local v=0;for k=-KS,KS do v+=kernel[k]*clamp(z-k+1,0,1) end;edgeStep[z]=v end
end
local function stepAt(z)
 if z<=-KS-1 then return 0 elseif z>=KS then return 1 end
 local f=floor(z);local a=edgeStep[f];return a+(edgeStep[f+1]-a)*(z-f)
end
-- Vertical radius-3 box pass over columns, skipping runs that are all 0 or all 1.
-- Deep interior: per column, the run of rows [colTop, colBot] whose blurred value
-- is exactly 1 after all three passes (every row within 3*BR is one plain span
-- covering the column with the blur's full reach). Those cells are pre-filled
-- with 1 and the passes jump over them.
local colTop,colBot,rowInL,rowInR={},{},{},{}
local function verticalPass(src,dst,left,right,top,bottom)
 for x=left,right do
  if (x-left)%24==23 then pace() end
  local dt,db=colTop[x],colBot[x]
  local sum=0;for y=top,min(bottom,top+BR-1) do sum+=src[y*W+x+1] end
  local y=top
  while y<=bottom do
   if dt and y>=dt and y<=db then
    y=db+1;if y>bottom then break end
    sum=0;for k=max(top,y-1-BR),min(bottom,y-1+BR) do sum+=src[k*W+x+1] end
   end
   if y+BR<=bottom then sum+=src[(y+BR)*W+x+1] end
   if y-BR-1>=top then sum-=src[(y-BR-1)*W+x+1] end
   if sum<1e-10 and sum>-1e-10 and y+BR+1<=bottom then
    local finish=y+BR+1
    while finish<=bottom and src[finish*W+x+1]==0 do finish+=1 end
    local last=finish-BR-1
    for yy=y,last do dst[yy*W+x+1]=0 end
    y=max(y,last);sum=0
   end
   dst[y*W+x+1]=sum/BN
   if sum>BN-1e-9 and y+BR+1<=bottom then
    local finish=y+BR+1
    while finish<=bottom and (not dt or finish<dt or finish>db) and src[finish*W+x+1]==1 do finish+=1 end
    local last=finish-BR-1
    for yy=y+1,last do dst[yy*W+x+1]=1 end
    y=max(y,last)
   end
   y+=1
  end
 end
end
local rowSpans={}
-- Rows where the outline starts or ends inside the cell (flat tops and bottoms)
-- are sampled at three sub-rows and averaged, so horizontal edges sit at their
-- true height instead of snapping to the 3 px cell grid.
local rowSub={}
local function addSpan(y,a,b)
 local list=rowSpans[y];if not list then list={};rowSpans[y]=list end
 list[#list+1]=a;list[#list+1]=b
 local sub=rowSub[y];if sub then for s=1,3 do local l=sub[s];l[#l+1]=a;l[#l+1]=b end end
end
-- Sort a row's spans and merge overlaps into a flat, ordered [a1,b1,a2,b2,...].
local function mergeRow(list)
 local n=#list/2
 if n>1 then
  local pairsList=table.create(n)
  for i=1,n do pairsList[i]={list[i*2-1],list[i*2]} end
  sort(pairsList,function(p,q) return p[1]<q[1] end)
  table.clear(list)
  local a,b=pairsList[1][1],pairsList[1][2]
  for i=2,n do local p=pairsList[i];if p[1]<=b then b=max(b,p[2]) else list[#list+1]=a;list[#list+1]=b;a,b=p[1],p[2] end end
  list[#list+1]=a;list[#list+1]=b
 end
 return list
end
local function shadeCells(iy,ix,endX,mat,phase)
 local row=iy*W+1
 while ix<=endX do
  local a,b,c,d=mask[row+ix],mask[row+ix+1],mask[row+ix+W],mask[row+ix+W+1]
  local low=min(a,b,c,d);local high=max(a,b,c,d)
  if high>.44 then
   local originX,originY=ix*S+CO,iy*S+CO
   if low>.98 then
    local runEnd=ix
    while runEnd<endX do
     local nextIndex=row+runEnd+2
     if mask[nextIndex]<=.98 or mask[nextIndex+W]<=.98 then break end
     runEnd+=1
    end
    if not rimMode then
     local length=(runEnd-ix+1)*S*4
     for dy=0,S-1 do local y=originY+dy
      if mat then copyMaterial(mat,y,originX,length/4)
      else copy(pixels,(y*OW+originX)*4,interiorRamp,((originX+floor(y*.75+clock*37.5))%785)*4,length) end
     end
    end
    ix=runEnd
   else
    -- Well inside the edge (centre more than INNER_SHADE px in) the light changes
    -- by under ~2 colour levels across a 2x2 cell: light the cell once and only
    -- blend each pixel with its own material.
    local gxc,gyc=((b-a)+(d-c))*.5/S,((c-a)+(d-b))*.5/S
    local slopec=sqrt(gxc*gxc+gyc*gyc)
    local vc=(a+b+c+d)*.25
    if mat and slopec>.006 and (vc-.47917)/slopec>INNER_SHADE then
     local distance=(vc-.47917)/slopec
     local light=(gxc*.6+gyc*.8)/slopec;if light<0 then light=0 elseif light>1 then light=1 end
     local key=floor(distance*32+.5);if key>2048 then key=2048 end
     local shine=rimLookup[key]*(.18+.82*light)*.8+broadLookup[key]*light;if shine>1 then shine=1 end
     -- packed blend: red+blue and green each in one multiply (8.8 fixed point)
     local s8=floor(shine*256+.5);local inv=256-s8
     local addRB=(RIM_R+RIM_B*65536)*s8+8388736;local addG=RIM_G*256*s8+32768
     -- unlit sides: under half a colour level of light, so copy natively
     if s8<=1 then for dy=0,S-1 do copyMaterial(mat,originY+dy,originX,S) end else
     for dy=0,S-1 do local y=originY+dy;local my=y-matY
      for dx=0,S-1 do local x=originX+dx;local mx=x-matX
       if mx<0 or my<0 or mx>=matW or my>=matH then mx,my=mirror(mx,matW),mirror(my,matH) end
       local base=readu32(mat,(my*matW+mx)*4)
       write(pixels,(y*OW+x)*4,band(rshift(band(base,16711935)*inv+addRB,8),16711935)+band(rshift(band(base,65280)*inv+addG,8),65280)+4278190080)
      end
     end
     end
    else
    for dy=0,S-1 do local y=originY+dy;local ty=TX0+dy/S
     local v0=a+(c-a)*ty;local v1=b+(d-b)*ty;local gx=(v1-v0)/S
     for dx=0,S-1 do local x=originX+dx;local tx=TX0+dx/S
      local v=v0+(v1-v0)*tx
      if v>.44 then
       local gy=((c-a)*(1-tx)+(d-b)*tx)/S
       local slope=sqrt(gx*gx+gy*gy);if slope<.006 then slope=.006 end
       local distance=(v-.47917)/slope
       local alpha=distance+.5
       if alpha>0 then
        if alpha>1 then alpha=1 end
        local light=(gx*.6+gy*.8)/slope;if light<0 then light=0 elseif light>1 then light=1 end
        local key=distance>0 and floor(distance*32+.5) or 0;if key>2048 then key=2048 end
        local shine=rimLookup[key]*(.18+.82*light)*.8+broadLookup[key]*light;if shine>1 then shine=1 end
        local off=(y*OW+x)*4
        if rimMode then
         write(pixels,off,16777215+floor(alpha*shine*255+.5)*16777216)
        elseif mat then
         local mx,my=x-matX,y-matY
         if mx<0 or my<0 or mx>=matW or my>=matH then mx,my=mirror(mx,matW),mirror(my,matH) end
         local base=readu32(mat,(my*matW+mx)*4)
         local s8=floor(shine*256+.5);local inv=256-s8
         write(pixels,off,band(rshift(band(base,16711935)*inv+(RIM_R+RIM_B*65536)*s8+8388736,8),16711935)+band(rshift(band(base,65280)*inv+RIM_G*256*s8+32768,8),65280)+floor(alpha*255+.5)*16777216)
        else
         local rgb=shades[phaseTint[(phaseX[x]+phaseY[y]+phase)%4096]+floor(shine*127+.5)*32]
         write(pixels,off,rgb+floor(alpha*(.72+shine*.26)*255+.5)*16777216)
        end
       end
      end
     end
    end
    end
   end
  end
  ix+=1
 end
end
local function render(points,drops)
 move(zeros,1,W*H,1,mask);move(zeros,1,W*H,1,temp)
 local left,top,right,bottom=W-1,H-1,0,0
 for _,p in ipairs(points) do left=min(left,p[1]/S);right=max(right,p[1]/S);top=min(top,p[2]/S);bottom=max(bottom,p[2]/S) end
 for _,d in ipairs(drops) do left=min(left,(d[1]-d[3])/S);right=max(right,(d[1]+d[3])/S);top=min(top,(d[2]-d[3])/S);bottom=max(bottom,(d[2]+d[3])/S) end
 left=max(0,floor(left)-KS-3);right=min(W-1,ceil(right)+KS+3);top=max(0,floor(top)-KS-3);bottom=min(H-1,ceil(bottom)+KS+3)
 table.clear(rowSpans);table.clear(rowSub)
 -- Even-odd polygon spans, then droplet circles, per mask row. Cuts are taken
 -- at three sub-rows per cell row (sub-row j samples y=(j+.5)*S/3).
 local cutRows={}
 local S3=S/3
 for i,p in ipairs(points) do
  local q=points[i%#points+1]
  if p[2]~=q[2] then
   local first=max(0,ceil(min(p[2],q[2])/S3-.5))
   local last=min(3*H-1,ceil(max(p[2],q[2])/S3-.5)-1)
   local slope=(q[1]-p[1])/(q[2]-p[2])
   for j=first,last do local cuts=cutRows[j];if not cuts then cuts={};cutRows[j]=cuts end;cuts[#cuts+1]=(p[1]+((j+.5)*S3-p[2])*slope)/S end
  end
 end
 do
  local seen={}
  for j in pairs(cutRows) do seen[j//3]=true end
  for y in pairs(seen) do
   local c0,c1,c2=cutRows[3*y],cutRows[3*y+1],cutRows[3*y+2]
   local n0,n1,n2=c0 and #c0 or 0,c1 and #c1 or 0,c2 and #c2 or 0
   if n0==n1 and n1==n2 then
    -- the outline crosses the whole row: its centre cuts are exact on average
    sort(c1);for i=1,#c1-1,2 do addSpan(y,c1[i],c1[i+1]) end
   else
    local sub={{},{},{}};local all={}
    for s,c in ipairs({c0 or {},c1 or {},c2 or {}}) do
     sort(c);local l=sub[s]
     for i=1,#c-1,2 do l[#l+1]=c[i];l[#l+1]=c[i+1];all[#all+1]=c[i];all[#all+1]=c[i+1] end
    end
    if #all>0 then rowSpans[y]=all;rowSub[y]=sub end
   end
  end
 end
 for _,d in ipairs(drops) do local x0,y0,r=d[1]/S,d[2]/S,d[3]/S
  for y=max(0,floor(y0-r)),min(H-1,ceil(y0+r)) do local dy=y+.5-y0;local rr=r*r-dy*dy;if rr>0 then local dx=sqrt(rr);addSpan(y,x0-dx,x0+dx) end end
 end
 -- Horizontal blur, solved per row from the span edges: interiors are filled
 -- natively and only the 19 cells around each edge are evaluated.
 local rowsDone=0
 for y,list in pairs(rowSpans) do
  rowsDone+=1;if rowsDone%24==0 then pace() end
  mergeRow(list)
  local row=y*W+1
  local sub=rowSub[y]
  if sub then
   -- partly covered row: average the three sub-row profiles over its whole reach
   for s=1,3 do mergeRow(sub[s]) end
   for x=max(left,ceil(list[1]-KS-1)),min(right,floor(list[#list]+KS)) do
    local v=0
    for s=1,3 do local l=sub[s];for j=1,#l,2 do v+=stepAt(x-l[j])-stepAt(x-l[j+1]) end end
    temp[row+x]=v/3
   end
  else
  for i=1,#list,2 do
   local first,last=ceil(list[i]+KS),floor(list[i+1]-KS-1)
   first=max(first,left);last=min(last,right)
   if last>=first then move(ones,1,last-first+1,row+first,temp) end
  end
  for i=1,#list do
   local e=list[i]
   for x=max(left,ceil(e-KS-1)),min(right,floor(e+KS)) do
    local v=0
    for j=1,#list,2 do v+=stepAt(x-list[j])-stepAt(x-list[j+1]) end
    temp[row+x]=v
   end
  end
  end
 end
 pace()
 -- Mark the deep interior (see verticalPass) and pre-fill it in mask; temp
 -- already holds 1 there from the horizontal pass.
 table.clear(colTop);table.clear(colBot);table.clear(rowInL);table.clear(rowInR)
 do
  local R3=3*BR
  for y=top,bottom do
   local l=rowSpans[y]
   if l and #l==2 and not rowSub[y] then rowInL[y]=max(left,ceil(l[1]+KS));rowInR[y]=min(right,floor(l[2]-KS-1)) end
  end
  -- Only columns entering or leaving the row's interior are touched; each column
  -- keeps its first run (a later re-entry is simply blurred normally).
  local pL,pR=1,0
  local lastY=bottom-R3
  for y=top+R3,lastY do
   local L,R=-math.huge,math.huge
   for r=y-R3,y+R3 do
    local a=rowInL[r];if not a then L,R=1,0;break end
    if a>L then L=a end;local b=rowInR[r];if b<R then R=b end
   end
   if not (L>=left and R<=right and R>=L) then L,R=1,0 end
   if R>=L then move(ones,1,R-L+1,y*W+L+1,mask) end
   -- leaving: in the previous range, not in this one
   for x=pL,min(pR,L-1) do if colBot[x]==-1 then colBot[x]=y-1 end end
   for x=max(pL,R+1),pR do if colBot[x]==-1 then colBot[x]=y-1 end end
   -- entering: in this range, not in the previous one
   for x=L,min(R,pL-1) do if not colTop[x] then colTop[x]=y;colBot[x]=-1 end end
   for x=max(L,pR+1),R do if not colTop[x] then colTop[x]=y;colBot[x]=-1 end end
   if pR<pL then for x=L,R do if not colTop[x] then colTop[x]=y;colBot[x]=-1 end end end
   pL,pR=L,R
  end
  for x,b in pairs(colBot) do if b==-1 then colBot[x]=lastY end end
 end
 pace()
 -- Vertical blur: three box passes, ending in mask.
 verticalPass(temp,mask,left,right,top,bottom);pace()
 verticalPass(mask,temp,left,right,top,bottom);pace()
 verticalPass(temp,mask,left,right,top,bottom);pace()
 local mat=nil
 if not rimMode and material.compose then mat,matX,matY,matW,matH=material.compose(max(0,(left-1)*S),max(0,(top-1)*S),min(OW,(right+2)*S),min(OH,(bottom+2)*S)) end
 pace()
 fill(pixels,0,0)
 local phase=floor(clock*.3*phaseScale)
 -- Each shaded row reads mask rows iy and iy+1, so the 19-tap kernel reaches
 -- spans from iy-9 to iy+10. Outside that the field is exactly 0; where every
 -- one of those rows fully covers a cell range it is exactly 1 (flat interior).
 local firstRow,lastRow=max(0,top-1),min(H-2,bottom)
 for iy=firstRow,lastRow do
  if (iy-firstRow)%4==3 then pace() end
  local lo,hi=math.huge,-math.huge
  local inL,inR=-math.huge,math.huge
  local single=true
  for r=iy-KS,iy+KS+1 do
   local list=rowSpans[r]
   if list then
    lo=min(lo,floor(list[1])-KS-1);hi=max(hi,floor(list[#list])+KS+1)
    if #list==2 and not rowSub[r] then inL=max(inL,ceil(list[1])+KS);inR=min(inR,floor(list[2])-KS-2) else single=false end
   else single=false end
  end
  if lo<=hi then
   local ix,endX=max(0,left-1,lo),min(W-2,right,hi)
   if single and inR-inL>=2 and inL>ix and inR<endX then
    shadeCells(iy,ix,inL-1,mat,phase)
    if not rimMode then
     local originX,originY=inL*S+CO,iy*S+CO;local length=(inR-inL+1)*S*4
     for dy=0,S-1 do local y=originY+dy
      if mat then copyMaterial(mat,y,originX,length/4)
      else copy(pixels,(y*OW+originX)*4,interiorRamp,((originX+floor(y*.75+clock*37.5))%785)*4,length) end
     end
    end
    shadeCells(iy,inR+1,endX,mat,phase)
   else
    shadeCells(iy,ix,endX,mat,phase)
   end
  end
 end
 for _,tile in ipairs(tiles) do
  -- keep the outgoing picture underneath so the new one can fade in over it
  if tile.under then tile.under:DrawImage(Vector2.zero,tile.image,Enum.ImageCombineType.Overwrite) end
  if tile.w==OW and tile.h==OH then tile.image:WritePixelsBuffer(Vector2.zero,Vector2.new(OW,OH),pixels)
  else for yy=0,tile.h-1 do copy(tile.pixels,yy*tile.w*4,pixels,((tile.y+yy)*OW+tile.x)*4,tile.w*4) end;tile.image:WritePixelsBuffer(Vector2.zero,Vector2.new(tile.w,tile.h),tile.pixels) end
 end
end

-- The open panel wears the liquid's own rim: render a rounded corner once through
-- the same shader (rim mode writes only the light) and 9-slice it over the
-- material. The old lens band and thin top rim are retired with it.
local panelRim=nil
local toastRim=nil
-- px the liquid's edge (threshold contour) lies outside the outline it is drawn
-- from; outlines are inset by this so the liquid edge sits exactly on the panel's.
local contourOut=0
do
 local k=Layout.uiScale
 local radius=Layout.radius*k
 local margin,pad=16,30
 local side=ceil(2*(radius+pad+margin)/(2*S))*2*S
 local saved={W,H,OW,OH,mask,temp,zeros,ones,pixels,tiles,P,cx,cy}
 OW,OH=side,side;W,H=side/S,side/S
 mask=table.create(W*H,0);temp=table.create(W*H,0);zeros=table.create(W*H,0);ones=table.create(W,1);pixels=buffer.create(OW*OH*4);tiles={}
 P={x=margin,y=margin,w=side-2*margin,h=side-2*margin,r=radius}
 -- sample the outline at the same spacing the real panel uses (N points around it)
 local panelSize=material.panelSize()
 local spacing=(2*(panelSize.X+panelSize.Y)-(8-2*pi)*radius)/N
 local count=max(16,floor((4*P.w-(8-2*pi)*radius)/spacing+.5))
 local outline={};for i=1,count do outline[i]=rectPoint((i-1)/count) end
 rimMode=true;rimLookup=rimBase;local ok,err=pcall(render,outline,{});rimMode=false;rimLookup=rimWide
 local function field(px,py)
  local gx,gy=px/S-.5,py/S-.5;local x0,y0=floor(gx),floor(gy);local fx,fy=gx-x0,gy-y0
  local i=y0*W+x0+1
  return (mask[i]*(1-fx)+mask[i+1]*fx)*(1-fy)+(mask[i+W]*(1-fx)+mask[i+W+1]*fx)*fy
 end
 local function crossing(f) local lo,hi=margin-12,margin+radius;for _=1,40 do local mid=(lo+hi)/2;if f(mid)>=.47917 then hi=mid else lo=mid end end;return hi end
 if ok then
  contourOut=clamp(margin-crossing(function(t) return field(t,side/2) end),0,4)
  if contourOut>.02 then
   local o=contourOut
   P={x=margin+o,y=margin+o,w=side-2*margin-2*o,h=side-2*margin-2*o,r=max(1,radius-o)}
   for i=1,count do outline[i]=rectPoint((i-1)/count) end
   rimMode=true;rimLookup=rimBase;ok,err=pcall(render,outline,{});rimMode=false;rimLookup=rimWide
  end
 end
 if ok then
  panelRim=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(side,side)})
  panelRim:WritePixelsBuffer(Vector2.zero,Vector2.new(side,side),pixels)
 end
 local contourRadius=nil
 if panelRim then
  local label=create('ImageLabel',{Name='LiquidRim',BackgroundTransparency=1,ImageColor3=Theme.mist,ImageContent=Content.fromObject(panelRim),ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(side/2-1,side/2-1,side/2+1,side/2+1),SliceScale=1/k,Position=UDim2.fromOffset(-margin/k,-margin/k),Size=UDim2.new(1,2*margin/k,1,2*margin/k),ZIndex=2,Parent=backdrop})
  passThrough(label)
  for _,name in ipairs({'Lens','Rim'}) do local item=panel:FindFirstChild(name);if item then item.Visible=false end end
 else warn('[LiquidIntegration] panel rim unavailable',err) end
 if ok then
  -- The blurred outline rounds corners more than the panel's UICorner; measure
  -- the liquid contour (straight edge and 45 degree corner point) and give the
  -- backdrop that exact radius so no dark corner pokes out past the rim.
  local edge=crossing(function(t) return field(t,side/2) end)
  local diagonal=crossing(function(t) return field(t,t) end)
  contourRadius=(diagonal-edge)*math.sqrt(2)/(math.sqrt(2)-1)
 end
 -- ESP card rim: the same liquid edge for the cards' corner radius, rendered
 -- now while the renderer is idle (cards are made later, at any time).
 local function cardRim(cardRadius)
  -- tight around the corner: a 9-slice corner must fit inside the small card
  local cardPad,cardMargin=4,4
  local eside=ceil(2*(cardRadius+cardPad+cardMargin)/(2*S))*2*S
  OW,OH=eside,eside;W,H=eside/S,eside/S
  mask=table.create(W*H,0);temp=table.create(W*H,0);zeros=table.create(W*H,0);ones=table.create(W,1);pixels=buffer.create(OW*OH*4);tiles={}
  local o=contourOut
  P={x=cardMargin+o,y=cardMargin+o,w=eside-2*cardMargin-2*o,h=eside-2*cardMargin-2*o,r=max(1,cardRadius-o)}
  local n=max(16,floor((4*P.w-(8-2*pi)*cardRadius)/spacing+.5))
  local cardOutline={};for i=1,n do cardOutline[i]=rectPoint((i-1)/n) end
  rimMode=true;rimLookup=rimBase;local cardOk=pcall(render,cardOutline,{});rimMode=false;rimLookup=rimWide
  if cardOk then
   local image=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(eside,eside)})
   -- the blurred edge rounds the corner more than the outline: measure the
   -- liquid contour's real corner radius so the card body can match it
   local function cardField(px,py)
    local gx,gy=px/S-.5,py/S-.5;local x0,y0=floor(gx),floor(gy);local fx,fy=gx-x0,gy-y0
    local i=y0*W+x0+1
    return (mask[i]*(1-fx)+mask[i+1]*fx)*(1-fy)+(mask[i+W]*(1-fx)+mask[i+W+1]*fx)*fy
   end
   local function cardCross(f) local lo,hi=max(1,cardMargin-4),cardMargin+cardRadius+cardPad;for _=1,40 do local mid=(lo+hi)/2;if f(mid)>=.47917 then hi=mid else lo=mid end end;return hi end
   local edge=cardCross(function(t) return cardField(t,eside/2) end)
   local diagonal=cardCross(function(t) return cardField(t,t) end)
   local measured=(diagonal-edge)*math.sqrt(2)/(math.sqrt(2)-1)
   -- keep the rim light on the card: nothing outside the liquid contour (the
   -- soft outer edge read as something behind the card where the light is
   -- strongest, top-left); the contour itself is antialiased over ~1 px
   for py=0,eside-1 do for px=0,eside-1 do
    local cx,cy=clamp(px+.5,S*.5+.01,eside-S*1.5-.01),clamp(py+.5,S*.5+.01,eside-S*1.5-.01)
    local f=cardField(cx,cy)
    local gx=cardField(min(cx+.5,eside-S*1.5-.01),cy)-cardField(max(cx-.5,S*.5+.01),cy)
    local gy=cardField(cx,min(cy+.5,eside-S*1.5-.01))-cardField(cx,max(cy-.5,S*.5+.01))
    local g=math.sqrt(gx*gx+gy*gy)
    local cover=g>1e-4 and clamp((f-.47917)/g+.5,0,1) or (f>=.47917 and 1 or 0)
    if cover<1 then
     local at=(py*eside+px)*4+3
     buffer.writeu8(pixels,at,floor(buffer.readu8(pixels,at)*cover+.5))
    end
   end end
   if image then image:WritePixelsBuffer(Vector2.zero,Vector2.new(eside,eside),pixels);return {image=image,side=eside,margin=cardMargin,radius=measured} end
  end
 end
 if ok then api.espRim=cardRim(14);toastRim=cardRim(18);Resize.beadRim=cardRim(12) end
 W,H,OW,OH,mask,temp,zeros,ones,pixels,tiles,P,cx,cy=table.unpack(saved,1,13)
 local backdropCorner=backdrop:FindFirstChildWhichIsA('UICorner')
 if contourRadius and backdropCorner then
  -- The dark body sits 1 px inside the liquid edge on every side: its own
  -- anti-aliased edge pixels (half dark) then fall under the rim instead of
  -- showing as a darker line just outside it. The rim stays where it was.
  local inset=1
  backdropCorner.CornerRadius=UDim.new(0,math.max(0,contourRadius-inset)/k)
  backdrop.Position+=UDim2.fromOffset(inset/k,inset/k);backdrop.Size+=UDim2.fromOffset(-2*inset/k,-2*inset/k)
  local rimLabel=backdrop:FindFirstChild('LiquidRim')
  if rimLabel then rimLabel.Position+=UDim2.fromOffset(-inset/k,-inset/k);rimLabel.Size+=UDim2.fromOffset(2*inset/k,2*inset/k) end
 end
end
-- The plain notification card (no parallel workers) wears the same liquid rim
-- as the window, 9-sliced at the card's own radius, and fades with the card.
-- setToastChrome hides it while the liquid morph draws its own card.
if toastRim and toast then
 local s,mg=toastRim.side,toastRim.margin
 local k=Layout.uiScale
 local rimLabel=create('ImageLabel',{Name='LiquidRim',BackgroundTransparency=1,ImageColor3=Theme.mist,ImageContent=Content.fromObject(toastRim.image),ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(s/2-1,s/2-1,s/2+1,s/2+1),SliceScale=1/k,Position=UDim2.fromOffset(-mg/k,-mg/k),Size=UDim2.new(1,2*mg/k,1,2*mg/k),ZIndex=10,Parent=toast})
 passThrough(rimLabel)
 table.insert(toastFade,{instance=rimLabel,property='ImageTransparency',base=0})
 for _,child in ipairs(toast:GetChildren()) do if child:IsA('UIStroke') then child:Destroy() end end
 local radius=UDim.new(0,math.max(0,toastRim.radius-1)/k)
 for _,item in ipairs(toast:GetDescendants()) do if item:IsA('UICorner') and item.Parent and item.Parent.Name~='StatusBadge' and item.Parent.Name~='Glint' then item.CornerRadius=radius end end
 local base=toast:FindFirstChild('MarbleBase')
 if base then base.Position=UDim2.fromOffset(1/k,1/k);base.Size=UDim2.new(1,-2/k,1,-2/k) end
end
local function releaseImages()
 for _,surface in ipairs(surfaces) do for _,tile in ipairs(surface.tiles) do tile.label:Destroy();tile.image:Destroy();tile.underLabel:Destroy();tile.under:Destroy() end;material.unbind(surface);if surface.holder then surface.holder:Destroy() end end
 table.clear(surfaces);table.clear(holderOf);tiles={}
end
-- allocate() switches the renderer to a surface for this canvas size; it never
-- changes what is on screen. showSurface() puts the current surface on screen,
-- so a handoff can keep the previous finished frame up until the next is ready.
local shownTiles=nil
local function placeHolder(list)
 local holder=holderOf[list]
 if holder then holder.Position=UDim2.fromOffset(origin.X-screenGui.AbsolutePosition.X,origin.Y-screenGui.AbsolutePosition.Y) end
 return holder
end
local function retireNow()
 local r=flow.retire;if not r then return end;flow.retire=nil
 if r.tiles~=shownTiles then
  local holder=holderOf[r.tiles];if holder then holder.Visible=false end
  for _,tile in ipairs(r.tiles) do tile.label.Visible=false;tile.underLabel.Visible=false;tile.label.Position=UDim2.fromOffset(tile.x,tile.y);tile.label.Size=UDim2.fromOffset(tile.w,tile.h);tile.underLabel.Position=tile.label.Position;tile.underLabel.Size=tile.label.Size end
 end
end
local function showSurface()
 retireNow()
 local holder=placeHolder(tiles)
 if shownTiles and shownTiles~=tiles then
  -- the outgoing picture stays exactly where it is, under the new one, for two
  -- frames while the new image's first upload reaches the screen
  local old=holderOf[shownTiles];if old then old.ZIndex=0 end
  flow.retire={tiles=shownTiles,frames=2}
 end
 if holder then holder.ZIndex=1;holder.Visible=true end
 for _,tile in ipairs(tiles) do tile.label.Visible=true;tile.label.ImageTransparency=0;tile.underLabel.Visible=false end
 shownTiles=tiles;flow.fadeLen=0;flow.fading=false
end
local function allocate(position,size)
 origin=position;local ow=max(S,ceil(size.X/S)*S);local oh=max(S,ceil(size.Y/S)*S)
 if OW==ow and OH==oh and #tiles>0 then return end
 OW,OH=ow,oh;W,H=OW/S,OH/S
 for _,surface in ipairs(surfaces) do
  if surface.w==OW and surface.h==OH then
   tiles=surface.tiles;mask=surface.mask;temp=surface.temp;zeros=surface.zeros;ones=surface.ones;pixels=surface.pixels
   material.bind(surface)
   return
  end
 end
 if #surfaces>=2 then
  local index=surfaces[1].tiles==shownTiles and 2 or 1
  local old=table.remove(surfaces,index);for _,tile in ipairs(old.tiles) do tile.label:Destroy();tile.image:Destroy();tile.underLabel:Destroy();tile.under:Destroy() end;material.unbind(old)
  if old.holder then holderOf[old.tiles]=nil;old.holder:Destroy() end
  if flow.retire and flow.retire.tiles==old.tiles then flow.retire=nil end
 end
 tiles={}
 local holder=create('Frame',{Name='LiquidHolder',BackgroundTransparency=1,Size=UDim2.fromOffset(OW,OH),ZIndex=0,Visible=false,Parent=canvas})
 passThrough(holder);holderOf[tiles]=holder
 mask=table.create(W*H,0);temp=table.create(W*H,0);zeros=table.create(W*H,0);ones=table.create(W,1);pixels=buffer.create(OW*OH*4)
 for x=0,OW-1 do phaseX[x]=floor(x*.008*phaseScale) end
 for y=0,OH-1 do phaseY[y]=floor(y*.006*phaseScale) end
 -- Tile rather than stretch when a resized panel exceeds EditableImage's limit.
 for y=0,OH-1,1024 do for x=0,OW-1,1024 do
  local w,h=min(1024,OW-x),min(1024,OH-y)
  local image=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(w,h)})
  assert(image,'EditableImage allocation unavailable')
  local under=game:GetService('AssetService'):CreateEditableImage({Size=Vector2.new(w,h)})
  assert(under,'EditableImage allocation unavailable')
  local underLabel=create('ImageLabel',{Name='LiquidUnder',BackgroundTransparency=1,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),ImageContent=Content.fromObject(under),ZIndex=0,Visible=false,Parent=holder})
  passThrough(underLabel)
  local label=create('ImageLabel',{Name='LiquidSurface',BackgroundTransparency=1,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),ImageContent=Content.fromObject(image),ZIndex=1,Visible=false,Parent=holder})
  passThrough(label)
  tiles[#tiles+1]={image=image,label=label,under=under,underLabel=underLabel,x=x,y=y,w=w,h=h,pixels=buffer.create(w*h*4)}
 end end
 surfaces[#surfaces+1]={w=OW,h=OH,tiles=tiles,mask=mask,temp=temp,zeros=zeros,ones=ones,pixels=pixels,holder=holder}
 material.bind(surfaces[#surfaces])
end
local function applyFade(entries,alpha)
 for _,entry in ipairs(entries) do if entry.instance.Parent then entry.instance[entry.property]=1-(1-entry.base)*alpha end end
end
local function snapshot(object,skip)
 local entries=collectFade(object,skip)
 for _,item in ipairs(object:GetDescendants()) do
  if (item:IsA('ImageLabel') or item:IsA('ImageButton')) and not item:IsDescendantOf(backdrop) then entries[#entries+1]={instance=item,property='ImageTransparency',base=item.ImageTransparency} end
 end
 return entries
end
local function fadePanel(alpha)
 root.Visible=alpha>0
 applyFade(panelEntries,alpha)
end
local function fadeIcon(alpha)
 bubble.Visible=alpha>0
 applyFade(iconEntries,alpha)
end
local function bubbleCenter() return bubble.AbsolutePosition+bubble.AbsoluteSize/2 end
local function preparePanel()
 panelScale.Scale=Layout.uiScale
 local pos,size=root.AbsolutePosition,root.AbsoluteSize
 local center=bubbleCenter();local pad=100
 local low=Vector2.new(floor(min(pos.X,center.X-60)-pad),floor(min(pos.Y,center.Y-60)-pad))
 local high=Vector2.new(ceil(max(pos.X+size.X,center.X+60)+pad),ceil(max(pos.Y+size.Y,center.Y+60)+pad))
 allocate(low,high-low)
 local o=contourOut
 P={x=pos.X-origin.X+o,y=pos.Y-origin.Y+o,w=size.X-2*o,h=size.Y-2*o,r=max(1,min(Layout.radius*Layout.uiScale,min(size.X,size.Y)/2)-o)}
 cx,cy=P.x+P.w/2,P.y+P.h/2
 bx,by=center.X-origin.X,center.Y-origin.Y;R=BUBBLE*Layout.uiScale/2
 material.prepare(material.panelSize())
 table.clear(rect);table.clear(angles)
 for i=1,N do rect[i]=rectPoint((i-1)/N);angles[i]=math.atan2(rect[i][2]-cy,rect[i][1]-cx) end
end
local function prepareIdle()
 local center=bubbleCenter();local margin=ceil(BUBBLE*Layout.uiScale/2+80)
 allocate(center-Vector2.new(margin,margin),Vector2.new(margin*2,margin*2))
 bx,by=margin,margin
 material.prepare(material.panelSize())
end
local function restoreBackgrounds()
 for _,item in ipairs(backgrounds) do if item[1].Parent then item[1].Visible=item[2] end end
 table.clear(backgrounds)
end
local function hideBackgrounds()
 if #backgrounds>0 then return end
 for _,name in ipairs({'Backdrop','Lens','Rim'}) do local item=panel:FindFirstChild(name);if item then backgrounds[#backgrounds+1]={item,item.Visible};item.Visible=false end end
end
local function hideBubbleBody()
 bubble.BackgroundTransparency=1
 for _,item in ipairs(bubble:GetChildren()) do
  if item:IsA('GuiObject') and item~=iconHolder then item.Visible=false elseif item:IsA('UIStroke') then item.Transparency=1 end
 end
end
local function warp(now)
 local list=shownTiles;if not list then return end
 local a,b=flow.a,flow.b
 local sx,sy,tx,ty=1,1,0,0
 if state=='morph' and a and b and list==tiles and b[5]-a[5]>.004 then
  -- follow the motion at 60%, never more than one picture ahead, and fade the
  -- effect in and out at both ends of the morph where the motion turns sharply.
  -- The body box is scaled about its own centre, so the scale limit can never
  -- turn into a jump.
  local T=morph and morph.t or 0
   local weight=clamp(min(T/.04,(1-T)/.15),0,1)*.6
  local u=clamp((now-b[5])/(b[5]-a[5]),0,1)*weight
  local cx0,cy0=(b[1]+b[3])/2,(b[2]+b[4])/2
  local dx=clamp(((b[1]+b[3])-(a[1]+a[3]))/2*u,-40,40)
  local dy=clamp(((b[2]+b[4])-(a[2]+a[4]))/2*u,-40,40)
  local bw,bh=max(1,b[3]-b[1]),max(1,b[4]-b[2])
  sx=clamp((bw+(bw-(a[3]-a[1]))*u)/bw,.92,1.08)
  sy=clamp((bh+(bh-(a[4]-a[2]))*u)/bh,.92,1.08)
  tx=cx0+dx-cx0*sx;ty=cy0+dy-cy0*sy
 end
 if sx==1 and sy==1 and tx==0 and ty==0 then
  if not flow.warped then return end
  flow.warped=false
 else flow.warped=true end
 for _,tile in ipairs(list) do
  local position,size=UDim2.fromOffset(tile.x*sx+tx,tile.y*sy+ty),UDim2.fromOffset(tile.w*sx,tile.h*sy)
  tile.label.Position=position;tile.label.Size=size
  if tile.underLabel then tile.underLabel.Position=position;tile.underLabel.Size=size end
 end
end
-- Crossfade: each new picture fades in over the previous one for about one
-- update interval, so the shape flows between pictures instead of stepping.
local function blend(now)
 local list=shownTiles;if not list then return end
 local a=flow.fadeLen>0 and clamp((now-flow.fadeStart)/flow.fadeLen,0,1) or 1
 if a>=1 and not flow.fading then return end
 flow.fading=a<1
 for _,tile in ipairs(list) do
  tile.label.ImageTransparency=1-a
  if tile.underLabel then tile.underLabel.Visible=a<1 end
 end
end
local function resetFlow()
 flow.a=nil;flow.b=nil;flow.lead=0;flow.fadeLen=0;flow.fading=true
 if shownTiles then warp(0);blend(0) end
end
local CONTENT_FADE_SECONDS=.25
local instantFinish=false
local contentFadingIn=false
local function runPending()
 if pending~=nil then local value=pending;pending=nil;task.defer(function() if not stopped then Resize.setMinimized(value) end end) end
end
local function finish(minimized)
 state=minimized and 'bubble' or 'panel'
 Resize.animating=not minimized and not instantFinish
 resetFlow();flow.hideIn=nil;flow.handoff=nil;material.sheetTask=nil
 applyFade(panelEntries,if minimized or instantFinish then 1 else 0);restoreBackgrounds()
 root.Visible=not minimized;bubble.Visible=minimized;applyFade(iconEntries,1)
 if minimized then
  idle={};nextIdle=clock+.6;prepareIdle();canvas.Visible=true
  if instantFinish then step(0);showSurface() else step(0,true);pacing.onDone=showSurface end
  runPending()
 else
  canvas.Visible=false
  if instantFinish then
   runPending()
  else
   contentFadingIn=true
   local began=os.clock()
   local connection: RBXScriptConnection?
   connection=RunService.RenderStepped:Connect(function()
    if stopped then if connection then connection:Disconnect() end;return end
    local alpha=clamp((os.clock()-began)/CONTENT_FADE_SECONDS,0,1)
    applyFade(panelEntries,alpha)
    if alpha>=1 then
     if connection then connection:Disconnect() end
     contentFadingIn=false;Resize.animating=false
     runPending()
    end
   end)
   track(connection)
  end
 end
end
function api.start(minimized,instant)
 if state=='morph' or contentFadingIn then pending=minimized;return end
 if api.pauseField then api.pauseField() end
 if instant or PERF.instant then
  if minimized then preparePanel();morph=newMorph(1);morph.t=1;hideBubbleBody();iconEntries=snapshot(iconHolder) end
  instantFinish=true;finish(minimized);instantFinish=false;return
 end
 material.sheetTask=nil -- a pending marble rebuild belongs to the old surface
 preparePanel()
 panelEntries=snapshot(panel,{[backdrop]=true});iconEntries=snapshot(iconHolder)
 morph=newMorph(minimized and 1 or -1);state='morph';Resize.animating=true
 -- minimize plays ~30% slower than un-minimize (same motion, more time)
 if minimized then morph.pace*=1.3 end
 resetFlow()
 idle={}
 -- The restored panel's backdrop has no content fade; keep it hidden from the
 -- first frame instead of letting it flash beside the still-visible bubble.
 if not minimized then hideBackgrounds() end
  -- Start each liquid surface at its actual endpoint. Hold that shape until its
  -- first picture replaces the panel or bubble, so rendering latency cannot
  -- make either endpoint jump ahead of the morph.
  local started=os.clock()
  local lead=0
 flow.clickTime=started
 flow.shotTime=started+lead;flow.lead=lead;flow.resetElapsed=true;flow.panelAlpha=nil;flow.iconAlpha=nil;flow.hideIn=nil;flow.revealed=false;flow.handoff=nil
 flow.finalRefreshStarted=false;flow.freshReady=false
 local function reveal()
  flow.firstLatency=flow.firstLatency*.5+min(.08,os.clock()-started)*.5
   showSurface();canvas.Visible=true;flow.revealed=true
   flow.shotTime=os.clock();flow.lead=0;flow.resetElapsed=true
  -- The backdrop (or bubble body) stays two more frames, until the liquid's first
  -- upload is certainly on screen; hiding it in the same frame showed one empty frame.
  flow.hideIn=2
 end
 step(lead,true);pacing.onDone=reveal
end
api.shared={pacing=pacing,material=material}
function api.stats() return {mode=state,material=material,width=P.w,height=P.h,canvasWidth=OW,canvasHeight=OH,frames=count,meanMs=totalMs/max(1,count),maxMs=maximumMs} end
function api.destroy()
 if stopped then return end;stopped=true;Resize.animating=false
 applyFade(panelEntries,1);restoreBackgrounds();releaseImages();material.destroy();if panelRim then panelRim:Destroy() end;if api.espRim then api.espRim.image:Destroy() end;canvas:Destroy()
end
step=function(dt,paced)
 pacing.task=nil
 clock+=dt
 if state=='panel' then return end
 if state=='bubble' then
  local center=bubbleCenter();origin=Vector2.new(center.X-bx,center.Y-by)
  if shownTiles==tiles then placeHolder(tiles) end
  R=bubble.AbsoluteSize.X/2
 end
 local pts,drops={},{}
 local completed=nil
  if state=='morph' and ((morph.dir==1 and flow.freshReady and os.clock()-flow.clickTime>=CONTENT_FADE_SECONDS)
   or (morph.dir==-1 and flow.revealed and not flow.hideIn)) then morph.t=min(1,morph.t+dt*speed/morph.pace) end
  local T=state=='bubble' and 1 or (morph.dir==1 and morph.t or 1-morph.t)
  local g=ease(T);local mx=cx+(bx-cx)*g+morph.bend[1]*sin(pi*g)*.5;local my=cy+(by-cy)*g+morph.bend[2]*sin(pi*g)*.5
  local roundK=.85*ease(clamp(T/.3,0,1));local rx,ry=P.w*.5,P.h*.5
  for i,p in ipairs(rect) do local ti=clamp((T-morph.delay[i])/(1-morph.maxDelay),0,1);local e=ease(ti);local a=angles[i]+morph.swirl*sin(pi*e)
   local px,py=p[1],p[2];if roundK>0 then px+=(cx+cos(angles[i])*rx-px)*roundK;py+=(cy+sin(angles[i])*ry-py)*roundK end;local sx=px+(mx-cx)*e*.15;local sy=py+(my-cy)*e*.15
   local w=state=='bubble' and idleWave(angles[i],clock*.6)*.9 or morph.wave(angles[i],clock)*sin(pi*ti)+idleWave(angles[i],clock*.6)*.9*e*e*(3-2*e)
   pts[i]={sx+(mx+cos(a)*R-sx)*e+cos(a)*w,sy+(my+sin(a)*R-sy)*e+sin(a)*w}
  end
  if state=='morph' then for _,d in ipairs(morph.drops) do local u=(T-d.at)/d.life;if u>0 and u<1 then local reach=u<.45 and (1-(1-u/.45)^3) or (u<.6 and 1 or max(-.08,1-((u-.6)/.4)^2*1.15));local p=pts[d.idx];local a=math.atan2(p[2]-my,p[1]-mx);local grow=clamp(u/.18,0,1);local fall=clamp((1-u)/.3,0,1);drops[#drops+1]={p[1]+cos(a)*reach*d.out,p[2]+sin(a)*reach*d.out,d.r*(1-.3*reach)*grow*grow*(3-2*grow)*fall*fall*(3-2*fall)} end end end
  if state=='bubble' then
   if clock>=nextIdle then spawnIdle();nextIdle=clock+rand(1.2,3.2) end
   for i=#idle,1,-1 do local d=idle[i];local t=clock-d.start
    if t>=d.bud+d.float+d.back then table.remove(idle,i) elseif t>=0 then
     local a,dist,r,sep,spin=d.a,0,d.r,0,0
     if t<d.bud then dist=R-4+(1-(1-t/d.bud)^3)*d.out
     elseif t<d.bud+d.float then local u=(t-d.bud)/d.float;a+=d.spin*(t-d.bud);dist=R-4+d.out+sin((t-d.bud)*d.bob*2+d.phase)*5;r*=1+.08*sin((t-d.bud)*5)
      if d.split then local s=sin(pi*min(1,u*1.15));sep=s*r*1.5;spin=(t-d.bud)*d.splitSpin;r=max(8,r*(1-.12*s)) end
     else local k=(t-d.bud-d.float)/d.back;local pull=-(cos(pi*min(1,k*1.05))-1)/2;a+=d.spin*d.float+d.spin*.4*d.back*(1-(1-k)^2);dist=R-4+d.out*(1-pull)+sin((t-d.bud)*d.bob*2+d.phase)*5*(1-pull)
       local sink=clamp((k-.55)/.45,0,1);sink=sink*sink*(3-2*sink);dist-=sink*(r+3);r*=1-.5*sink end
     local x,y=bx+cos(a)*dist,by+sin(a)*dist
     if sep>0 then for _,o in ipairs({0,pi}) do drops[#drops+1]={x+cos(spin+o)*sep,y+sin(spin+o)*sep,r} end else drops[#drops+1]={x,y,r} end
    end
   end
  end
  if state=='morph' and morph.t>=1 then completed=morph.dir==1 end
 
 if completed~=nil then
  if completed then
   -- Finish the last circle picture before switching to the idle renderer.
   -- Pace it so the handoff cannot add a synchronous frame spike.
   material.ox,material.oy=mx-P.w/2,my-P.h/2
   drops={}
   flow.shot=nil
   pacing.task=coroutine.create(render);pacing.args={pts,drops};pacing.work=0
   pacing.onDone=function() showSurface();finish(true) end
   return
  end
  finish(false);return
 end
 material.ox,material.oy=mx-P.w/2,my-P.h/2
 do
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,p in ipairs(pts) do local x,y=p[1],p[2];if x<x0 then x0=x end;if x>x1 then x1=x end;if y<y0 then y0=y end;if y>y1 then y1=y end end
  flow.shot={x0,y0,x1,y1,flow.shotTime,os.clock()}
 end
 if paced then
  pacing.task=coroutine.create(render);pacing.args={pts,drops};pacing.work=0
 else
  local started=os.clock();render(pts,drops);local ms=(os.clock()-started)*1000
  count+=1;totalMs+=ms;maximumMs=max(maximumMs,ms)
 end
end
resumeRender=function()
 local task=pacing.task
 pacing.resumedAt=os.clock()
 pacing.budget=sliceBudget(state=='morph' and PERF.morph or PERF.idle);pacing.start=pacing.frameStart
 -- the first minimize picture gets the full morph slice even when the game is
 -- busy, so the liquid takes over as soon as possible
 if state=='morph' and not flow.revealed and morph and morph.dir==1 then pacing.budget=max(pacing.budget,PERF.morph) end
 local ok,err
 if pacing.args then local args=pacing.args;pacing.args=nil;ok,err=coroutine.resume(task,args[1],args[2]) else ok,err=coroutine.resume(task) end
 local sliceStart=pacing.start
 pacing.budget=nil;pacing.work+=os.clock()-max(sliceStart,pacing.resumedAt or sliceStart)
 if not ok then pacing.task=nil;error(err,0) end
 if coroutine.status(task)=='dead' and pacing.task==task then
  pacing.task=nil;local ms=pacing.work*1000;count+=1;totalMs+=ms;maximumMs=max(maximumMs,ms)
  local shot=flow.shot
  if shot then
   flow.latency=flow.latency*.7+min(.08,os.clock()-shot[6]+flow.frameDt)*.3
   if state=='morph' then flow.a=flow.b;flow.b=shot else flow.a=nil;flow.b=nil end
  end
  do
   local now=os.clock()
   if flow.doneAt then flow.interval=flow.interval*.7+min(.1,now-flow.doneAt)*.3 end
    flow.doneAt=now;flow.fadeStart=now
    -- A long overlap leaves the previous displaced outline visible.
    -- a bubble that redraws every frame needs no crossfade (it would only trail)
    flow.fadeLen=state=='morph' and clamp(flow.interval*.45,.008,.024) or (flow.interval<.014 and 0 or clamp(flow.interval*.7,.01,.035))
    flow.fading=true
  end
  if pacing.onDone then local done=pacing.onDone;pacing.onDone=nil;done() end
 end
end
local elapsed=0
track(RunService.RenderStepped:Connect(function(dt)
 if stopped then return end
 pacing.frameStart=os.clock()
 -- the game's own frame time: this frame's length minus what the liquid used in it
 flow.gameTime=flow.gameTime*.9+clamp(dt-flow.ourWork,0,.1)*.1;flow.ourWork=0
 if state=='panel' then
  pacing.task=nil
  if flow.retire then retireNow() end
  -- the open panel's liquid pieces read the live marble sheet; its next copy
  -- builds in the background on a small slice, like during a transition
  local sheetTask=material.sheetTask
  if sheetTask then
   pacing.budget=.0015;pacing.start=os.clock()
   local good,problem=coroutine.resume(sheetTask)
   pacing.budget=nil
   if not good then material.sheetTask=nil;warn('[LiquidMaterial]',problem)
   elseif coroutine.status(sheetTask)=='dead' and material.sheetTask==sheetTask then material.sheetTask=nil end
  end
  pacing.limit=sliceBudget(PERF.idle)
  if api.service then
   local ok,err=xpcall(api.service,debug.traceback,dt)
   if not ok then warn('[LiquidField]',err);api.service=nil end
  end
  flow.ourWork=os.clock()-pacing.frameStart
  return
 end
 if flow.resetElapsed then flow.resetElapsed=false;elapsed=0 end
 elapsed+=dt;flow.frameDt=flow.frameDt*.9+min(dt,.05)*.1
 local ok,err=xpcall(function()
   if flow.hideIn then flow.hideIn-=1;if flow.hideIn<=0 then
    flow.hideIn=nil
    if morph.dir==-1 or (flow.freshReady and os.clock()-flow.clickTime>=CONTENT_FADE_SECONDS) then hideBackgrounds() end
    hideBubbleBody()
    if state=='morph' and morph and morph.dir==-1 then flow.shotTime=os.clock();flow.resetElapsed=true end
   end end
  if flow.retire then flow.retire.frames-=1;if flow.retire.frames<=0 then retireNow() end end
  -- The next marble sheet builds in the background on its own small slice.
  -- During a transition it goes first and the picture gets what is left of
  -- this frame's budget. For the idle bubble it goes last, on whatever the
  -- outline left over: the outline then never waits a frame for the marble
  -- (the marble is only rebuilt 24 times a second anyway).
  local function runSheet(budget)
   local sheetTask=material.sheetTask
   if not sheetTask then return end
   if state=='panel' then material.sheetTask=nil;return end
   pacing.budget=budget;pacing.start=os.clock()
   local good,problem=coroutine.resume(sheetTask)
   pacing.budget=nil
   if not good then material.sheetTask=nil;warn('[LiquidMaterial]',problem)
   elseif coroutine.status(sheetTask)=='dead' and material.sheetTask==sheetTask then material.sheetTask=nil end
  end
  if state~='bubble' then runSheet(.0015) end
   -- Keep the live panel backdrop visible during the content fade; the first
   -- liquid picture waits underneath until the shape is ready to take over.
   local waitingForContent=state=='morph' and morph and
    ((morph.dir==1 and (os.clock()-flow.clickTime<CONTENT_FADE_SECONDS or not flow.freshReady))
     or (morph.dir==-1 and (not flow.revealed or flow.hideIn)))
   if state=='morph' and morph.dir==1 and flow.revealed and not flow.hideIn and not waitingForContent then hideBackgrounds() end
   if waitingForContent then elapsed=0 end
   -- finish the update in flight before starting the next one
   if pacing.task then resumeRender()
   elseif waitingForContent and morph.dir==1 and flow.revealed and not flow.finalRefreshStarted
    and os.clock()-flow.clickTime>=CONTENT_FADE_SECONDS*.6 then
    -- Rebuild the panel-shaped picture from the current marble near the end of
    -- the fade. The live backdrop stays visible until this picture is ready.
    flow.finalRefreshStarted=true
    material.invalidateSheet()
    flow.shotTime=os.clock()
    step(0,true)
    pacing.onDone=function() flow.freshReady=true end
    if pacing.task then resumeRender() end
    -- Keep the idle liquid border in step with the per-frame icon gradient.
   elseif not waitingForContent and not flow.handoff and ((state=='bubble' and elapsed>=PERF.bubbleGap) or elapsed>=1/60) then
   -- draw for when this picture will be on screen, not for now
   local lead=state=='morph' and min(.06,flow.latency) or 0
   local duration=elapsed+lead-flow.lead;elapsed=0;flow.lead=lead
   flow.shotTime=os.clock()+lead
   step(clamp(duration,0,.1),true)
   if pacing.task then resumeRender() end
  end
  if state=='bubble' then runSheet(clamp(sliceBudget(PERF.idle)-(os.clock()-pacing.frameStart),.0008,.0015)) end
  if state=='morph' or flow.warped then warp(os.clock()) end
  blend(os.clock())
  -- The panel contents fade out before minimize and in after restore. The
  -- bubble icon still follows the morph clock.
  if state=='morph' and morph then
    local vt=if (morph.dir==1 and (os.clock()-flow.clickTime<CONTENT_FADE_SECONDS or not flow.freshReady))
     or (morph.dir==-1 and (not flow.revealed or flow.hideIn)) then 0
    else clamp(morph.t+(os.clock()-flow.shotTime)*speed/morph.pace,0,1)
   local VT=morph.dir==1 and vt or 1-vt
   -- Minimize fades the contents before the shape moves. Restore fades in after it returns.
   local pa=if morph.dir==1
    then clamp(1-(os.clock()-flow.clickTime)/CONTENT_FADE_SECONDS,0,1)
    else .001
   -- until the liquid is on screen the panel/bubble must stay (only its content fades)
   local ia=clamp((VT-.65)/.35,0,1)
    if not flow.revealed or flow.hideIn or (morph.dir==1 and not flow.freshReady) then if morph.dir==1 then pa=max(pa,.001) else ia=max(ia,.001) end end
   if pa~=flow.panelAlpha then flow.panelAlpha=pa;fadePanel(pa) end
   if ia~=flow.iconAlpha then flow.iconAlpha=ia;fadeIcon(ia) end
   -- Un-minimize hand-off: in the last stretch the shape is all but the panel,
   -- and those are the slowest pictures to draw. The real panel comes back under
   -- the liquid (Root draws above the liquid layer) and the liquid fades out
   -- every frame instead; no more liquid pictures are drawn.
   if morph.dir==-1 and flow.revealed and not flow.hideIn then
    if not flow.handoff and VT<.1 then flow.handoff=true;restoreBackgrounds() end
    if flow.handoff then
     local fade=clamp(1-VT/.1,0,1)
     if shownTiles then for _,tile in ipairs(shownTiles) do tile.label.ImageTransparency=max(tile.label.ImageTransparency,fade);tile.underLabel.Visible=false end end
     if vt>=1 then finish(false) end
    end
   end
  end
 end,debug.traceback)
 flow.ourWork=os.clock()-pacing.frameStart
 if not ok then
  warn('[LiquidIntegration]',err)
  pacing.task=nil;pacing.onDone=nil;canvas.Visible=false;Resize.animating=false;applyFade(panelEntries,1);restoreBackgrounds();root.Visible=true;bubble.Visible=false;state='panel';Resize.minimized=false
 end
end))
track(api.destroy)
return api
end)()
Resize.liquid=liquid
-- Liquid pieces living on the open panel: the header logo bubble, droplets that
-- bud from the panel edge, and the resize grip. They run the same shader as the
-- transition through their own copy of the renderer state, share its frame
-- budget, and only update while the panel is open.
local liquidField=nil
do local fieldOk,fieldError=pcall(function() liquidField=(function()
local min,max,floor,ceil,sqrt=math.min,math.max,math.floor,math.ceil,math.sqrt
local move,sort,copy,fill=table.move,table.sort,buffer.copy,buffer.fill
local pi,sin,cos,clamp=math.pi,math.sin,math.cos,math.clamp
local W,H,S=1,1,2
local OW,OH=2,2
local tiles={}
local clock=0
local epoch=os.clock()
local clearRow=nil
local postProcess=nil
local shared=liquid.shared
local pacing=shared.pacing
local function pace()
 if pacing.budget and os.clock()-pacing.start>pacing.budget then coroutine.yield() end
end
local material={compose=nil}
-- Shared mask: scan-converted body and circles, separable blur, threshold, shaded rim.
-- Same field and shading as the approved prototype; the work is bounded to where
-- the field actually changes (the band around the outline), not the whole box.
local mask=table.create(W*H,0);local temp=table.create(W*H,0);local pixels=buffer.create(OW*OH*4)
local zeros=table.create(W*H,0);local ones=table.create(W,1)
local write,readu32=buffer.writeu32,buffer.readu32
local band,rshift=bit32.band,bit32.rshift
local baseColors,phaseX,phaseY={},{},{}
local phaseTint,shades={},{}
local phaseScale=4096/(2*math.pi)
for i=0,4095 do
 local tint=.5+.5*math.sin(i/phaseScale)
 phaseTint[i]=floor(tint*31+.5)
 baseColors[i]=floor(27+11*tint)+floor(23+7*tint)*256+floor(40+16*tint)*65536+184*16777216
end
for x=0,OW-1 do phaseX[x]=floor(x*.008*phaseScale) end
for y=0,OH-1 do phaseY[y]=floor(y*.006*phaseScale) end
local interiorRamp=buffer.create(2048*4)
for x=0,2047 do write(interiorRamp,x*4,baseColors[floor(x*.008*phaseScale)%4096]) end
local rimLookup,broadLookup={},{}
for i=0,2048 do rimLookup[i]=math.exp(-i/32*.8);broadLookup[i]=math.exp(-i/32*.13)*.22 end
for t=0,31 do for light=0,127 do
 local tint=t/31;local shine=light/127
 shades[t+light*32]=floor(27+11*tint+shine*195)+floor(23+7*tint+shine*189)*256+min(255,floor(40+16*tint+shine*205))*65536
end end
-- Rim light colour. The liquid blends toward it by `shine`; the open panel's rim
-- overlay uses the same colour with alpha = shine, so both produce equal pixels.
local RIM_R,RIM_G,RIM_B=226,214,246
Resize.themeHooks=Resize.themeHooks or {}
table.insert(Resize.themeHooks,function(T) local c=T.mist;RIM_R,RIM_G,RIM_B=math.round(c.R*255),math.round(c.G*255),math.round(c.B*255) end)
local rimMode=false
-- Material source for this render: buffer `mat` of matW x matH pixels whose
-- origin sits at (matX, matY) in output pixels. Outside it the liquid is ink.
local matX,matY,matW,matH=0,0,0,0
local INNER_SHADE=4
local INK_PIXEL=7+7*256+10*65536+255*16777216
local inkRow=buffer.create(4096*4)
for x=0,4095 do write(inkRow,x*4,INK_PIXEL) end
-- Past the edge of the material the texture is mirrored, never cut to ink, so a
-- liquid stretched beyond the material area shows no hard line.
local function mirror(v,n)
 if v<0 then v=-v-1 elseif v>=n then v=2*n-v-1 end
 if v<0 then return 0 elseif v>=n then return n-1 end
 return v
end
local function copyMaterial(mat,y,x,length)
 local dst=(y*OW+x)*4
 local base=mirror(y-matY,matH)*matW
 local sx0=x-matX;local sx1=sx0+length
 local a,b=max(0,sx0),min(matW,sx1)
 if b>a then copy(pixels,dst+(a-sx0)*4,mat,(base+a)*4,(b-a)*4) end
 for sx=sx0,min(sx1,0)-1 do write(pixels,dst+(sx-sx0)*4,readu32(mat,(base+mirror(sx,matW))*4)) end
 for sx=max(sx0,matW),sx1-1 do write(pixels,dst+(sx-sx0)*4,readu32(mat,(base+mirror(sx,matW))*4)) end
end
-- The blur is three box passes of about 6 px radius: BR cells at S px per cell.
-- KS is the combined kernel's reach in cells. edgeStep[z] is that kernel's response
-- to a cell-covered edge at distance z; it is piecewise linear between integers,
-- so interpolating it is exact. This replaces three passes per row.
local BR=S>=3 and 2 or 3
local KS,BN=3*BR,2*BR+1
local CO=floor(S/2)
local TX0=(CO+.5-S/2)/S
local edgeStep={}
do
 local kernel={[0]=1}
 for _=1,3 do
  local nextKernel={}
  for k,v in pairs(kernel) do for j=-BR,BR do nextKernel[k+j]=(nextKernel[k+j] or 0)+v/BN end end
  kernel=nextKernel
 end
 for z=-KS-1,KS+1 do local v=0;for k=-KS,KS do v+=kernel[k]*clamp(z-k+1,0,1) end;edgeStep[z]=v end
end
local function stepAt(z)
 if z<=-KS-1 then return 0 elseif z>=KS then return 1 end
 local f=floor(z);local a=edgeStep[f];return a+(edgeStep[f+1]-a)*(z-f)
end
-- Vertical radius-3 box pass over columns, skipping runs that are all 0 or all 1.
-- Deep interior: per column, the run of rows [colTop, colBot] whose blurred value
-- is exactly 1 after all three passes (every row within 3*BR is one plain span
-- covering the column with the blur's full reach). Those cells are pre-filled
-- with 1 and the passes jump over them.
local colTop,colBot,rowInL,rowInR={},{},{},{}
local function verticalPass(src,dst,left,right,top,bottom)
 for x=left,right do
  if (x-left)%24==23 then pace() end
  local dt,db=colTop[x],colBot[x]
  local sum=0;for y=top,min(bottom,top+BR-1) do sum+=src[y*W+x+1] end
  local y=top
  while y<=bottom do
   if dt and y>=dt and y<=db then
    y=db+1;if y>bottom then break end
    sum=0;for k=max(top,y-1-BR),min(bottom,y-1+BR) do sum+=src[k*W+x+1] end
   end
   if y+BR<=bottom then sum+=src[(y+BR)*W+x+1] end
   if y-BR-1>=top then sum-=src[(y-BR-1)*W+x+1] end
   if sum<1e-10 and sum>-1e-10 and y+BR+1<=bottom then
    local finish=y+BR+1
    while finish<=bottom and src[finish*W+x+1]==0 do finish+=1 end
    local last=finish-BR-1
    for yy=y,last do dst[yy*W+x+1]=0 end
    y=max(y,last);sum=0
   end
   dst[y*W+x+1]=sum/BN
   if sum>BN-1e-9 and y+BR+1<=bottom then
    local finish=y+BR+1
    while finish<=bottom and (not dt or finish<dt or finish>db) and src[finish*W+x+1]==1 do finish+=1 end
    local last=finish-BR-1
    for yy=y+1,last do dst[yy*W+x+1]=1 end
    y=max(y,last)
   end
   y+=1
  end
 end
end
local rowSpans={}
-- Rows where the outline starts or ends inside the cell (flat tops and bottoms)
-- are sampled at three sub-rows and averaged, so horizontal edges sit at their
-- true height instead of snapping to the 3 px cell grid.
local rowSub={}
local function addSpan(y,a,b)
 local list=rowSpans[y];if not list then list={};rowSpans[y]=list end
 list[#list+1]=a;list[#list+1]=b
 local sub=rowSub[y];if sub then for s=1,3 do local l=sub[s];l[#l+1]=a;l[#l+1]=b end end
end
-- Sort a row's spans and merge overlaps into a flat, ordered [a1,b1,a2,b2,...].
local function mergeRow(list)
 local n=#list/2
 if n>1 then
  local pairsList=table.create(n)
  for i=1,n do pairsList[i]={list[i*2-1],list[i*2]} end
  sort(pairsList,function(p,q) return p[1]<q[1] end)
  table.clear(list)
  local a,b=pairsList[1][1],pairsList[1][2]
  for i=2,n do local p=pairsList[i];if p[1]<=b then b=max(b,p[2]) else list[#list+1]=a;list[#list+1]=b;a,b=p[1],p[2] end end
  list[#list+1]=a;list[#list+1]=b
 end
 return list
end
local function shadeCells(iy,ix,endX,mat,phase)
 local row=iy*W+1
 while ix<=endX do
  local a,b,c,d=mask[row+ix],mask[row+ix+1],mask[row+ix+W],mask[row+ix+W+1]
  local low=min(a,b,c,d);local high=max(a,b,c,d)
  if high>.44 then
   local originX,originY=ix*S+CO,iy*S+CO
   if low>.98 then
    local runEnd=ix
    while runEnd<endX do
     local nextIndex=row+runEnd+2
     if mask[nextIndex]<=.98 or mask[nextIndex+W]<=.98 then break end
     runEnd+=1
    end
    if not rimMode then
     local length=(runEnd-ix+1)*S*4
     for dy=0,S-1 do local y=originY+dy
      if mat then copyMaterial(mat,y,originX,length/4)
      else copy(pixels,(y*OW+originX)*4,interiorRamp,((originX+floor(y*.75+clock*37.5))%785)*4,length) end
     end
    end
    ix=runEnd
   else
    -- Well inside the edge (centre more than INNER_SHADE px in) the light changes
    -- by under ~2 colour levels across a 2x2 cell: light the cell once and only
    -- blend each pixel with its own material.
    local gxc,gyc=((b-a)+(d-c))*.5/S,((c-a)+(d-b))*.5/S
    local slopec=sqrt(gxc*gxc+gyc*gyc)
    local vc=(a+b+c+d)*.25
    if mat and slopec>.006 and (vc-.47917)/slopec>INNER_SHADE then
     local distance=(vc-.47917)/slopec
     local light=(gxc*.6+gyc*.8)/slopec;if light<0 then light=0 elseif light>1 then light=1 end
     local key=floor(distance*32+.5);if key>2048 then key=2048 end
     local shine=rimLookup[key]*(.18+.82*light)*.8+broadLookup[key]*light;if shine>1 then shine=1 end
     -- packed blend: red+blue and green each in one multiply (8.8 fixed point)
     local s8=floor(shine*256+.5);local inv=256-s8
     local addRB=(RIM_R+RIM_B*65536)*s8+8388736;local addG=RIM_G*256*s8+32768
     -- unlit sides: under half a colour level of light, so copy natively
     if s8<=1 then for dy=0,S-1 do copyMaterial(mat,originY+dy,originX,S) end else
     for dy=0,S-1 do local y=originY+dy;local my=y-matY
      for dx=0,S-1 do local x=originX+dx;local mx=x-matX
       if mx<0 or my<0 or mx>=matW or my>=matH then mx,my=mirror(mx,matW),mirror(my,matH) end
       local base=readu32(mat,(my*matW+mx)*4)
       write(pixels,(y*OW+x)*4,band(rshift(band(base,16711935)*inv+addRB,8),16711935)+band(rshift(band(base,65280)*inv+addG,8),65280)+4278190080)
      end
     end
     end
    else
    for dy=0,S-1 do local y=originY+dy;local ty=TX0+dy/S
     local v0=a+(c-a)*ty;local v1=b+(d-b)*ty;local gx=(v1-v0)/S
     for dx=0,S-1 do local x=originX+dx;local tx=TX0+dx/S
      local v=v0+(v1-v0)*tx
      if v>.44 then
       local gy=((c-a)*(1-tx)+(d-b)*tx)/S
       local slope=sqrt(gx*gx+gy*gy);if slope<.006 then slope=.006 end
       local distance=(v-.47917)/slope
       local alpha=distance+.5
       if alpha>0 then
        if alpha>1 then alpha=1 end
        local light=(gx*.6+gy*.8)/slope;if light<0 then light=0 elseif light>1 then light=1 end
        local key=distance>0 and floor(distance*32+.5) or 0;if key>2048 then key=2048 end
        local shine=rimLookup[key]*(.18+.82*light)*.8+broadLookup[key]*light;if shine>1 then shine=1 end
        local off=(y*OW+x)*4
        if rimMode then
         write(pixels,off,16777215+floor(alpha*shine*255+.5)*16777216)
        elseif mat then
         local mx,my=x-matX,y-matY
         if mx<0 or my<0 or mx>=matW or my>=matH then mx,my=mirror(mx,matW),mirror(my,matH) end
         local base=readu32(mat,(my*matW+mx)*4)
         local s8=floor(shine*256+.5);local inv=256-s8
         write(pixels,off,band(rshift(band(base,16711935)*inv+(RIM_R+RIM_B*65536)*s8+8388736,8),16711935)+band(rshift(band(base,65280)*inv+RIM_G*256*s8+32768,8),65280)+floor(alpha*255+.5)*16777216)
        else
         local rgb=shades[phaseTint[(phaseX[x]+phaseY[y]+phase)%4096]+floor(shine*127+.5)*32]
         write(pixels,off,rgb+floor(alpha*(.72+shine*.26)*255+.5)*16777216)
        end
       end
      end
     end
    end
    end
   end
  end
  ix+=1
 end
end
local function render(points,drops,focus)
 move(zeros,1,W*H,1,mask);move(zeros,1,W*H,1,temp)
 local left,top,right,bottom=W-1,H-1,0,0
 for _,p in ipairs(points) do left=min(left,p[1]/S);right=max(right,p[1]/S);top=min(top,p[2]/S);bottom=max(bottom,p[2]/S) end
 for _,d in ipairs(drops) do left=min(left,(d[1]-d[3])/S);right=max(right,(d[1]+d[3])/S);top=min(top,(d[2]-d[3])/S);bottom=max(bottom,(d[2]+d[3])/S) end
 left=max(0,floor(left)-KS-3);right=min(W-1,ceil(right)+KS+3);top=max(0,floor(top)-KS-3);bottom=min(H-1,ceil(bottom)+KS+3)
 if focus then left=max(left,focus[1]);top=max(top,focus[2]);right=min(right,focus[3]);bottom=min(bottom,focus[4]) end
 table.clear(rowSpans);table.clear(rowSub)
 -- Even-odd polygon spans, then droplet circles, per mask row. Cuts are taken
 -- at three sub-rows per cell row (sub-row j samples y=(j+.5)*S/3).
 local cutRows={}
 local S3=S/3
 for i,p in ipairs(points) do
  local q=points[i%#points+1]
  if p[2]~=q[2] then
   local first=max(0,ceil(min(p[2],q[2])/S3-.5))
   local last=min(3*H-1,ceil(max(p[2],q[2])/S3-.5)-1)
   local slope=(q[1]-p[1])/(q[2]-p[2])
   for j=first,last do local cuts=cutRows[j];if not cuts then cuts={};cutRows[j]=cuts end;cuts[#cuts+1]=(p[1]+((j+.5)*S3-p[2])*slope)/S end
  end
 end
 do
  local seen={}
  for j in pairs(cutRows) do seen[j//3]=true end
  for y in pairs(seen) do
   local c0,c1,c2=cutRows[3*y],cutRows[3*y+1],cutRows[3*y+2]
   local n0,n1,n2=c0 and #c0 or 0,c1 and #c1 or 0,c2 and #c2 or 0
   if n0==n1 and n1==n2 then
    -- the outline crosses the whole row: its centre cuts are exact on average
    sort(c1);for i=1,#c1-1,2 do addSpan(y,c1[i],c1[i+1]) end
   else
    local sub={{},{},{}};local all={}
    for s,c in ipairs({c0 or {},c1 or {},c2 or {}}) do
     sort(c);local l=sub[s]
     for i=1,#c-1,2 do l[#l+1]=c[i];l[#l+1]=c[i+1];all[#all+1]=c[i];all[#all+1]=c[i+1] end
    end
    if #all>0 then rowSpans[y]=all;rowSub[y]=sub end
   end
  end
 end
 for _,d in ipairs(drops) do local x0,y0,r=d[1]/S,d[2]/S,d[3]/S
  for y=max(0,floor(y0-r)),min(H-1,ceil(y0+r)) do local dy=y+.5-y0;local rr=r*r-dy*dy;if rr>0 then local dx=sqrt(rr);addSpan(y,x0-dx,x0+dx) end end
 end
 -- Horizontal blur, solved per row from the span edges: interiors are filled
 -- natively and only the 19 cells around each edge are evaluated.
 local rowsDone=0
 for y,list in pairs(rowSpans) do
  rowsDone+=1;if rowsDone%24==0 then pace() end
  mergeRow(list)
  local row=y*W+1
  local sub=rowSub[y]
  if sub then
   -- partly covered row: average the three sub-row profiles over its whole reach
   for s=1,3 do mergeRow(sub[s]) end
   for x=max(left,ceil(list[1]-KS-1)),min(right,floor(list[#list]+KS)) do
    local v=0
    for s=1,3 do local l=sub[s];for j=1,#l,2 do v+=stepAt(x-l[j])-stepAt(x-l[j+1]) end end
    temp[row+x]=v/3
   end
  else
  for i=1,#list,2 do
   local first,last=ceil(list[i]+KS),floor(list[i+1]-KS-1)
   first=max(first,left);last=min(last,right)
   if last>=first then move(ones,1,last-first+1,row+first,temp) end
  end
  for i=1,#list do
   local e=list[i]
   for x=max(left,ceil(e-KS-1)),min(right,floor(e+KS)) do
    local v=0
    for j=1,#list,2 do v+=stepAt(x-list[j])-stepAt(x-list[j+1]) end
    temp[row+x]=v
   end
  end
  end
 end
 pace()
 -- Mark the deep interior (see verticalPass) and pre-fill it in mask; temp
 -- already holds 1 there from the horizontal pass.
 table.clear(colTop);table.clear(colBot);table.clear(rowInL);table.clear(rowInR)
 do
  local R3=3*BR
  for y=top,bottom do
   local l=rowSpans[y]
   if l and #l==2 and not rowSub[y] then rowInL[y]=max(left,ceil(l[1]+KS));rowInR[y]=min(right,floor(l[2]-KS-1)) end
  end
  -- Only columns entering or leaving the row's interior are touched; each column
  -- keeps its first run (a later re-entry is simply blurred normally).
  local pL,pR=1,0
  local lastY=bottom-R3
  for y=top+R3,lastY do
   local L,R=-math.huge,math.huge
   for r=y-R3,y+R3 do
    local a=rowInL[r];if not a then L,R=1,0;break end
    if a>L then L=a end;local b=rowInR[r];if b<R then R=b end
   end
   if not (L>=left and R<=right and R>=L) then L,R=1,0 end
   if R>=L then move(ones,1,R-L+1,y*W+L+1,mask) end
   -- leaving: in the previous range, not in this one
   for x=pL,min(pR,L-1) do if colBot[x]==-1 then colBot[x]=y-1 end end
   for x=max(pL,R+1),pR do if colBot[x]==-1 then colBot[x]=y-1 end end
   -- entering: in this range, not in the previous one
   for x=L,min(R,pL-1) do if not colTop[x] then colTop[x]=y;colBot[x]=-1 end end
   for x=max(L,pR+1),R do if not colTop[x] then colTop[x]=y;colBot[x]=-1 end end
   if pR<pL then for x=L,R do if not colTop[x] then colTop[x]=y;colBot[x]=-1 end end end
   pL,pR=L,R
  end
  for x,b in pairs(colBot) do if b==-1 then colBot[x]=lastY end end
 end
 pace()
 -- Vertical blur: three box passes, ending in mask.
 verticalPass(temp,mask,left,right,top,bottom);pace()
 verticalPass(mask,temp,left,right,top,bottom);pace()
 verticalPass(temp,mask,left,right,top,bottom);pace()
 local mat=nil
 if not rimMode and material.compose then mat,matX,matY,matW,matH=material.compose(max(0,(left-1)*S),max(0,(top-1)*S),min(OW,(right+2)*S),min(OH,(bottom+2)*S)) end
 pace()
 if clearRow then for y=0,OH-1 do copy(pixels,y*OW*4,clearRow,0,OW*4) end else fill(pixels,0,0) end
 local phase=floor(clock*.3*phaseScale)
 -- Each shaded row reads mask rows iy and iy+1, so the 19-tap kernel reaches
 -- spans from iy-9 to iy+10. Outside that the field is exactly 0; where every
 -- one of those rows fully covers a cell range it is exactly 1 (flat interior).
 local firstRow,lastRow=max(0,top-1),min(H-2,bottom)
 for iy=firstRow,lastRow do
  if (iy-firstRow)%4==3 then pace() end
  local lo,hi=math.huge,-math.huge
  local inL,inR=-math.huge,math.huge
  local single=true
  for r=iy-KS,iy+KS+1 do
   local list=rowSpans[r]
   if list then
    lo=min(lo,floor(list[1])-KS-1);hi=max(hi,floor(list[#list])+KS+1)
    if #list==2 and not rowSub[r] then inL=max(inL,ceil(list[1])+KS);inR=min(inR,floor(list[2])-KS-2) else single=false end
   else single=false end
  end
  if lo<=hi then
   local ix,endX=max(0,left-1,lo),min(W-2,right,hi)
   if single and inR-inL>=2 and inL>ix and inR<endX then
    shadeCells(iy,ix,inL-1,mat,phase)
    if not rimMode then
     local originX,originY=inL*S+CO,iy*S+CO;local length=(inR-inL+1)*S*4
     for dy=0,S-1 do local y=originY+dy
      if mat then copyMaterial(mat,y,originX,length/4)
      else copy(pixels,(y*OW+originX)*4,interiorRamp,((originX+floor(y*.75+clock*37.5))%785)*4,length) end
     end
    end
    shadeCells(iy,inR+1,endX,mat,phase)
   else
    shadeCells(iy,ix,endX,mat,phase)
   end
  end
 end
 if postProcess then postProcess() end
 for _,tile in ipairs(tiles) do
  -- keep the outgoing picture underneath so the new one can fade in over it
  if tile.under then tile.under:DrawImage(Vector2.zero,tile.image,Enum.ImageCombineType.Overwrite) end
  if tile.w==OW and tile.h==OH then tile.image:WritePixelsBuffer(Vector2.zero,Vector2.new(OW,OH),pixels)
  else for yy=0,tile.h-1 do copy(tile.pixels,yy*tile.w*4,pixels,((tile.y+yy)*OW+tile.x)*4,tile.w*4) end;tile.image:WritePixelsBuffer(Vector2.zero,Vector2.new(tile.w,tile.h),tile.pixels) end
 end
end

local AS=game:GetService('AssetService')
local WRITE=Enum.ImageCombineType.Overwrite
local REF_R=29          -- radius the bubble's droplet tuning was made for (px)
local rng=Random.new()
local function rand(a,b) return rng:NextNumber(a,b) end
local function harmonics(n,lo,hi,klo,khi)
 local hs={};for i=1,n do hs[i]={rng:NextInteger(klo or 2,khi or 9),rand(lo,hi),rand(0,2*pi),rand(1.2,5)*(rand(0,1)<.5 and -1 or 1)} end
 return function(a,t) local v=0;for _,h in ipairs(hs) do v+=h[2]*sin(h[1]*a+h[3]+h[4]*t) end;return v end
end
local function newSurface(w,h)
 local surface={OW=w,OH=h,W=w/2,H=h/2,pixels=buffer.create(w*h*4)}
 surface.mask=table.create(surface.W*surface.H,0);surface.temp=table.create(surface.W*surface.H,0)
 surface.zeros=table.create(surface.W*surface.H,0);surface.ones=table.create(surface.W,1)
 surface.image=AS:CreateEditableImage({Size=Vector2.new(w,h)})
 surface.tiles={{image=surface.image,x=0,y=0,w=w,h=h}}
 return surface
end
local function use(surface)
 OW,OH,W,H=surface.OW,surface.OH,surface.W,surface.H
 mask,temp,zeros,ones,pixels,tiles=surface.mask,surface.temp,surface.zeros,surface.ones,surface.pixels,surface.tiles
 for x=0,OW-1 do if not phaseX[x] then phaseX[x]=floor(x*.008*phaseScale) end end
 for y=0,OH-1 do if not phaseY[y] then phaseY[y]=floor(y*.006*phaseScale) end end
end
-- Transparent pixels carry the rim colour so the native 2x reductions below
-- bleed toward the bright edge instead of darkening it.
local function bleedRow(w)
 local row=buffer.create(w*4)
 for x=0,w-1 do buffer.writeu32(row,x*4,RIM_R+RIM_G*256+RIM_B*65536) end
 return row
end
-- Exact 2x2 box reduction per step (bilinear sampled at texel corners).
local function reductionChain(w,h,steps)
 local chain={}
 for i=1,steps do w,h=w/2,h/2;chain[i]=AS:CreateEditableImage({Size=Vector2.new(w,h)}) end
 return chain
end
local function reduce(source,chain)
 for _,image in ipairs(chain) do
  local size=image.Size
  image:DrawImageTransformed(size/2,Vector2.new(.5,.5),0,source,{CombineType=WRITE})
  source=image
 end
end
-- Idle droplet life cycle shared by the logo bubble: bud on a neck, float free
-- (sometimes splitting and rejoining), then get pulled back in. Same equations
-- as the minimized bubble, with lengths scaled to this bubble's radius.
local function idleDrops(state,cx,cy,R,limit,list)
 local scale=R/REF_R
 if clock>=state.nextIdle then
  local room=limit-#state.idle
  if room>0 then
   local n=min(room,rand(0,1)<.18 and 2 or 1);local a=rand(0,2*pi)
   for i=1,n do table.insert(state.idle,{start=clock+(i-1)*rand(.1,.3),bud=rand(.7,1.1),float=rand(1.4,3.6),back=rand(1.6,2.6),a=a+rand(-.6,.6),out=rand(.7,1.15)*R,r=rand(8,9.5),spin=rand(.25,.7)*(rand(0,1)<.5 and -1 or 1),bob=rand(.6,1.4),phase=rand(0,2*pi),split=rand(0,1)<.4,splitSpin=rand(2.5,4.5)}) end
  end
  state.nextIdle=clock+rand(1.2,3.2)
 end
 local bob=5*scale
 for i=#state.idle,1,-1 do local d=state.idle[i];local t=clock-d.start
  if t>=d.bud+d.float+d.back then table.remove(state.idle,i) elseif t>=0 then
   local a,dist,r,sep,spin=d.a,0,d.r,0,0
   if t<d.bud then dist=R-4*scale+(1-(1-t/d.bud)^3)*d.out
   elseif t<d.bud+d.float then local u=(t-d.bud)/d.float;a+=d.spin*(t-d.bud);dist=R-4*scale+d.out+sin((t-d.bud)*d.bob*2+d.phase)*bob;r*=1+.08*sin((t-d.bud)*5)
    if d.split then local s=sin(pi*min(1,u*1.15));sep=s*r*1.5;spin=(t-d.bud)*d.splitSpin;r=max(8,r*(1-.12*s)) end
   else local k=(t-d.bud-d.float)/d.back;local pull=-(cos(pi*min(1,k*1.05))-1)/2;a+=d.spin*d.float+d.spin*.4*d.back*(1-(1-k)^2);dist=R-4*scale+d.out*(1-pull)+sin((t-d.bud)*d.bob*2+d.phase)*bob*(1-pull)
     local sink=clamp((k-.55)/.45,0,1);sink=sink*sink*(3-2*sink);dist-=sink*(r+3*scale);r*=1-.5*sink end
   local x,y=cx+cos(a)*dist,cy+sin(a)*dist
   if sep>0 then for _,o in ipairs({0,pi}) do list[#list+1]={x+cos(spin+o)*sep,y+sin(spin+o)*sep,r} end else list[#list+1]={x,y,r} end
  end
 end
end

local k=Layout.uiScale
local function panelPixels() return root.AbsoluteSize end
local function contourRadius()
 local corner=backdrop:FindFirstChildWhichIsA('UICorner')
 return (corner and corner.CornerRadius.Offset or Layout.radius)*k
end
-- Point and outward normal on the panel's rounded outline at arc length d.
local function outlineAt(d,w,h,r)
 local sw,sh=w-2*r,h-2*r;local arc=pi*r/2
 local L=2*sw+2*sh+4*arc
 d=d%L
 local seg={{sw/2,w/2,0,1,0},{arc,w-r,r,-pi/2},{sh,w,r,0,1},{arc,w-r,h-r,0},{sw,w-r,h,-1,0},{arc,r,h-r,pi/2},{sh,0,h-r,0,-1},{arc,r,r,pi},{sw/2,r,0,1,0}}
 for _,v in ipairs(seg) do
  if d<=v[1] then
   if #v==5 then return v[2]+v[4]*d,v[3]+v[5]*d,v[5],-v[4] end
   local a=v[4]+d/r;return v[2]+cos(a)*r,v[3]+sin(a)*r,cos(a),sin(a)
  end
  d-=v[1]
 end
 return w/2,0,0,-1
end
local function perimeter(w,h,r) return 2*(w-2*r)+2*(h-2*r)+2*pi*r end

local jobs={}
local stopped=false

-- Header logo: a tiny copy of the minimized bubble, rendered 4x larger and
-- reduced natively, playing with up to two droplets of its own (3 bodies max).
do
 local logo=header:FindFirstChildWhichIsA('Frame')
 for _,child in ipairs(header:GetChildren()) do if child:IsA('Frame') and child.Size==UDim2.fromOffset(10,10) then logo=child end end
 local SCALE,SIZE=4,144
 local displayRadius=logo.Size.X.Offset*k/2
 local R=displayRadius*SCALE
 local surface=newSurface(SIZE,SIZE)
 local chain=reductionChain(SIZE,SIZE,2)
 local target=shared.material.newTarget(SIZE,SIZE)
 local bleed=bleedRow(SIZE)
 local label=create('ImageLabel',{Name='LogoBubble',BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(logo.Position.X.Offset+logo.Size.X.Offset/2,logo.Position.Y.Offset+logo.Size.Y.Offset/2),Size=UDim2.fromOffset(SIZE/SCALE/k,SIZE/SCALE/k),ImageContent=Content.fromObject(chain[#chain]),ZIndex=logo.ZIndex,Parent=header})
 passThrough(label)
 logo.Visible=false
 local state={idle={},nextIdle=.6,wave=harmonics(3,.6,1.6)}
 jobs[#jobs+1]={name='logo',interval=0,elapsed=1,surfaces={surface},chain=chain,target=target,label=label,
  active=function() return root.Visible end,
  run=function()
   local c=SIZE/2;local scale=R/REF_R
   local points={}
   for i=1,48 do local a=(i-1)/48*2*pi;local radius=R+state.wave(a,clock*.6)*.9*scale;points[i]={c+cos(a)*radius,c+sin(a)*radius} end
   local drops={};idleDrops(state,c,c,R,2,drops)
   local size=panelPixels()
   use(surface);clearRow=bleed;postProcess=nil
   material.compose=function() return shared.material.sheetAt(c-size.X/2,c-size.Y/2) end
   render(points,drops)
   reduce(surface.image,chain)
  end}
end

-- Panel edge droplets: the open panel is the "core" bubble; droplets bud from its
-- outline, drift along it, float off and get pulled back, like the minimized
-- bubble's. Each renders in a small window that includes the panel edge it grows
-- from, faded into the panel at the window border so the rim stays continuous.
do
 local MAX,WINDOW,MARGIN,FADE=4,208,40,10  -- at most 4 border bubbles at once (drips are separate and not counted)
 local drops={}
  -- Tab-bar lava drip (one at a time): liquid gathers under the tab bar, hangs on a
  -- stretching neck, lets go, falls under gravity behind the controls, and on
  -- reaching the bottom edge becomes an edge droplet that keeps its impact speed.
  local drip,nextDrip=nil,nil
  local falling,doubled={},false   -- drops in the air; first drip at launch is always followed by a second
  local DRIP_G=1150   -- px/s^2
 local nextSpawn=1.5
 local outline,outlineKey={},nil
 local pool={}
 local function slot()
  local item=table.remove(pool)
  if item then return item end
  item={surface=newSurface(WINDOW,WINDOW),target=shared.material.newTarget(WINDOW,WINDOW)}
  item.label=create('ImageLabel',{Name='EdgeDroplet',BackgroundTransparency=1,Size=UDim2.fromOffset(WINDOW/k,WINDOW/k),ImageContent=Content.fromObject(item.surface.image),ZIndex=1,Visible=false,Parent=panel})
  passThrough(item.label)
  return item
 end
 local function clearAll()
  for _,d in ipairs(drops) do d.slot.label.Visible=false;pool[#pool+1]=d.slot end
  table.clear(drops)
   if drip then drip.slot.label.Visible=false;pool[#pool+1]=drip.slot;drip=nil end
   for _,f in ipairs(falling) do f.slot.label.Visible=false;pool[#pool+1]=f.slot end;table.clear(falling)
 end
 local grip=panel:FindFirstChild('ResizeGrip')
 local function spawn(w,h,r,L)
  -- keep away from other droplets and from the resize grip corner
  for _=1,8 do
   local arc=rand(0,L)
   local x,y,_,ny=outlineAt(arc,w,h,r)
   -- sides and top only: the bottom edge belongs to the landing lava drips
   local clear=not (x>w-60 and y>h-60) and ny<.5
   for _,d in ipairs(drops) do local gap=math.abs((d.arc-arc+L/2)%L-L/2);if gap<150 then clear=false end end
   if clear then
    drops[#drops+1]={slot=slot(),start=clock,bud=rand(.7,1.1),float=rand(1.4,3.6),back=rand(1.6,2.6),arc=arc,out=rand(.7,1.15)*REF_R,r=rand(8.5,11.5),speed=rand(.25,.7)*REF_R*(rand(0,1)<.5 and -1 or 1),bob=rand(.6,1.4),phase=rand(0,2*pi),split=rand(0,1)<.4,splitSpin=rand(2.5,4.5)}
    return
   end
  end
 end
 -- window-border fade (alpha only), inside the region that was rendered
 local fadeBox
 local function feather()
  local x0,y0,x1,y1=fadeBox[1],fadeBox[2],fadeBox[3],fadeBox[4]
  local readu32,writeu32=buffer.readu32,buffer.writeu32
  -- Shading reads one cell past the focus box, where the blurred field was never
  -- computed; the sudden drop to zero there lights a false rim one pixel outside
  -- the box. Clear that ring (and a little more) so it never shows.
  local ax0,ay0,ax1,ay1=max(0,x0-3),max(0,y0-3),min(OW,x1+3),min(OH,y1+3)
  for y=ay0,ay1-1 do
   if y<y0 or y>=y1 then fill(pixels,(y*OW+ax0)*4,0,(ax1-ax0)*4)
   else
    if x0>ax0 then fill(pixels,(y*OW+ax0)*4,0,(x0-ax0)*4) end
    if ax1>x1 then fill(pixels,(y*OW+x1)*4,0,(ax1-x1)*4) end
   end
  end
  for y=y0,y1-1 do
   local dy=min(y-y0,y1-1-y)
   local full=dy>=MARGIN
   local x=x0
   while x<x1 do
    local dx=min(x-x0,x1-1-x)
    if full and dx>=MARGIN then x=x1-MARGIN else
     local edge=min(dx,dy)
     local w=clamp((edge-(MARGIN-FADE))/FADE,0,1)
     if w<1 then local off=(y*OW+x)*4;local v=readu32(pixels,off);local a=floor(v/16777216);if a>0 then writeu32(pixels,off,v%16777216+floor(a*w+.5)*16777216) end end
     x+=1
    end
   end
  end
 end


 -- The drip is drawn in the same marble as the panel behind it, so on its own only
 -- its top-lit rim shows (a hanging drop, merged into the tab bar above, was nearly
 -- invisible). This lifts the colour inside the drip's circles a little toward the
 -- rim light, with a soft 2 px edge, so it reads as a glossy bead the whole way.
 local DRIP_TINT=.16
 local function tintCircles(circles,amount)
  if amount<=0 then return end
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,c in ipairs(circles) do x0=min(x0,c[1]-c[3]);y0=min(y0,c[2]-c[3]);x1=max(x1,c[1]+c[3]);y1=max(y1,c[2]+c[3]) end
  x0,y0,x1,y1=max(0,floor(x0)),max(0,floor(y0)),min(OW-1,ceil(x1)),min(OH-1,ceil(y1))
  local readu32,writeu32=buffer.readu32,buffer.writeu32
  for y=y0,y1 do
   for x=x0,x1 do
    local f=0
    for _,c in ipairs(circles) do
     local dx,dy=x+.5-c[1],y+.5-c[2]
     local inside=(c[3]-sqrt(dx*dx+dy*dy))/2
     if inside>f then f=inside end
    end
    if f>0 then
     if f>1 then f=1 end
     local off=(y*OW+x)*4;local v=readu32(pixels,off);local a=floor(v/16777216)
     if a>0 then
      local s=f*amount;local r,g,b=v%256,floor(v/256)%256,floor(v/65536)%256
      r=floor(r+(RIM_R-r)*s+.5);g=floor(g+(RIM_G-g)*s+.5);b=floor(b+(RIM_B-b)*s+.5)
      writeu32(pixels,off,r+g*256+b*65536+a*16777216)
     end
    end
   end
  end
 end

 -- Drips sit behind the controls; the glass rows are ~94% transparent, so a drop
 -- showed straight through them. Where a visible control (row, card, pill, the
 -- Biolink button) covers the drip, the drip is frosted instead: blurred and
 -- slightly faded, following each control's rounded corners with a soft edge, so
 -- it reads as liquid passing BEHIND frosted glass.
 local occl,occlAt={},-1
 local function occluders()
  if clock-occlAt<.4 then return occl end
  occlAt=clock;table.clear(occl)
  local pp=panel.AbsolutePosition
  local pages=panel:FindFirstChild('Pages')
  local function add(o,cx0,cy0,cx1,cy1)
   local a,s=o.AbsolutePosition-pp,o.AbsoluteSize
   if s.X<4 or s.Y<4 then return end
   local x0,y0,x1,y1=max(a.X,cx0),max(a.Y,cy0),min(a.X+s.X,cx1),min(a.Y+s.Y,cy1)
   if x1<=x0 or y1<=y0 then return end
   local c=o:FindFirstChildWhichIsA('UICorner');local rad=0
   if c then rad=c.CornerRadius.Scale*min(s.X,s.Y)+c.CornerRadius.Offset*k end
   occl[#occl+1]={a.X,a.Y,a.X+s.X,a.Y+s.Y,min(rad,s.X/2,s.Y/2),x0,y0,x1,y1}
  end
  if pages then
   local a,s=pages.AbsolutePosition-pp,pages.AbsoluteSize
   for _,o in ipairs(pages:GetDescendants()) do
    if o:IsA('GuiObject') and o.Visible and o.BackgroundTransparency<.99 then
     local shown=true;local q=o.Parent
     while q and q~=pages do if q:IsA('GuiObject') and not q.Visible then shown=false;break end;q=q.Parent end
     if shown then add(o,a.X,a.Y,a.X+s.X,a.Y+s.Y) end
    end
   end
  end
  local bio=panel:FindFirstChild('Biolink')
  if bio and bio.Visible then add(bio,-math.huge,-math.huge,math.huge,math.huge) end
  return occl
 end
 local FROST_R,FROST_ALPHA=4,.72   -- blur radius (px) and opacity kept behind glass
 -- bounding box (window px) of a list of {x,y,r} circles
 local function circleBox(circles)
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,c in ipairs(circles) do x0=min(x0,c[1]-c[3]);y0=min(y0,c[2]-c[3]);x1=max(x1,c[1]+c[3]);y1=max(y1,c[2]+c[3]) end
  return {x0-3,y0-3,x1+3,y1+3}
 end
 local fA,fR,fG,fB,fT={},{},{},{},{}
 -- one box-blur pass over a w*h grid (horizontal or vertical), edge-clamped
 local function boxPass(src,dst,w,h,horizontal)
  local r=FROST_R;local inv=1/(2*r+1)
  if horizontal then
   for y=0,h-1 do
    local base=y*w;local sum=0
    for p=-r,r do sum+=src[base+clamp(p,0,w-1)+1] end
    for x=0,w-1 do
     dst[base+x+1]=sum*inv
     sum+=src[base+min(x+r+1,w-1)+1]-src[base+max(x-r,0)+1]
    end
   end
  else
   for x=0,w-1 do
    local sum=0
    for p=-r,r do sum+=src[clamp(p,0,h-1)*w+x+1] end
    for y=0,h-1 do
     dst[y*w+x+1]=sum*inv
     sum+=src[min(y+r+1,h-1)*w+x+1]-src[max(y-r,0)*w+x+1]
    end
   end
  end
 end
 -- Frost the drip where controls cover it. Only the drip's own small box is
 -- blurred (not the whole overlap with the row), so it runs inside one frame.
 local function occlude(ox,oy,box)
  local list=occluders();if #list==0 then return end
  local readu32,writeu32=buffer.readu32,buffer.writeu32
  for _,o in ipairs(list) do
   local x0,y0=max(0,floor(o[6]-ox),floor(box[1])),max(0,floor(o[7]-oy),floor(box[2]))
   local x1,y1=min(OW,ceil(o[8]-ox),ceil(box[3])),min(OH,ceil(o[9]-oy),ceil(box[4]))
   if x1>x0 and y1>y0 then
    local bx0,by0,bx1,by1=max(0,x0-FROST_R),max(0,y0-FROST_R),min(OW,x1+FROST_R),min(OH,y1+FROST_R)
    local bw,bh=bx1-bx0,by1-by0;local n=bw*bh
    local any=false
    for i=1,n do fA[i]=0;fR[i]=0;fG[i]=0;fB[i]=0 end
    for y=by0,by1-1 do local row=(y-by0)*bw-bx0+1
     for x=bx0,bx1-1 do local v=readu32(pixels,(y*OW+x)*4);local al=floor(v/16777216)
      if al>0 then any=true;local i=row+x;fA[i]=al;fR[i]=(v%256)*al;fG[i]=(floor(v/256)%256)*al;fB[i]=(floor(v/65536)%256)*al end
     end
    end
    if any then
     local orig={}
     for _,ch in ipairs({fA,fR,fG,fB}) do
      local keep=table.create(n);table.move(ch,1,n,1,keep);orig[#orig+1]=keep
      boxPass(ch,fT,bw,bh,true);boxPass(fT,ch,bw,bh,false)
      boxPass(ch,fT,bw,bh,true);boxPass(fT,ch,bw,bh,false)
     end
     local oA,oR,oG,oB=orig[1],orig[2],orig[3],orig[4]
     local L,T,R,B,rad=o[1]-ox,o[2]-oy,o[3]-ox,o[4]-oy,o[5]
     local s=FROST_ALPHA
     for y=y0,y1-1 do
      local py=y+.5;local dy=max(T+rad-py,py-(B-rad))
      for x=x0,x1-1 do
       local px=x+.5;local dx=max(L+rad-px,px-(R-rad))
       local qx,qy=max(dx,0),max(dy,0)
       local d=sqrt(qx*qx+qy*qy)+min(max(dx,dy),0)-rad
       local cover=clamp(.5-d,0,1)
       if cover>0 then
        local i=(y-by0)*bw+(x-bx0)+1
        local fa=oA[i]+(fA[i]*s-oA[i])*cover
        if fa>.5 then
         local fr=oR[i]+(fR[i]*s-oR[i])*cover
         local fg=oG[i]+(fG[i]*s-oG[i])*cover
         local fb=oB[i]+(fB[i]*s-oB[i])*cover
         writeu32(pixels,(y*OW+x)*4,min(255,floor(fr/fa+.5))+min(255,floor(fg/fa+.5))*256+min(255,floor(fb/fa+.5))*65536+min(255,floor(fa+.5))*16777216)
        else
         writeu32(pixels,(y*OW+x)*4,0)
        end
       end
      end
     end
    end
   end
  end
 end
 local function updateDrip(w,h,r)
  local tb=tabBar
  if not (tb and tb.Parent and tb.Visible and tb.AbsoluteSize.X>0) then return end
  local p=tb.AbsolutePosition-panel.AbsolutePosition;local s=tb.AbsoluteSize
  local lo,hi=p.X+s.Y/2+8,min(p.X+s.X-s.Y/2-8,w-r-70)
  local ey=p.Y+s.Y
  -- drops in the air (more than one can be falling at once)
  for i=#falling,1,-1 do
   local f=falling[i];local R=f.R;local item=f.slot
   local tau=clock-f.t0
   local x=f.x;local y=f.y1+f.v0*tau+.5*DRIP_G*tau*tau;local v=f.v0+DRIP_G*tau
   if y+R>=h-3 then
    -- landing: becomes an edge droplet on the bottom edge, carrying its momentum
    local sw,sh,q=w-2*r,h-2*r,pi*r/2
    drops[#drops+1]={slot=item,start=clock,bud=1,float=rand(1.2,2.2),back=rand(1.6,2.4),arc=sw/2+q+sh+q+(w-r-x),out=rand(.75,1)*REF_R,r=R,speed=rand(.12,.3)*REF_R*(rand(0,1)<.5 and -1 or 1),bob=rand(.6,1.2),phase=0,split=false,splitSpin=3,impact={off=y-h,v=v*.22}}
    table.remove(falling,i)
   else
    -- a small trailing bead stretches the drop into a teardrop as it speeds up
    local tail=min(v*.014,R*1.2)
    local ox,oy=floor((x-WINDOW/2)/S)*S,floor((y-WINDOW/2)/S)*S
    local bodies={{x-ox,y-oy,R},{x-ox,y-tail-oy,R*.55}}
    use(item.surface);clearRow=nil
    postProcess=function() tintCircles(bodies,DRIP_TINT);occlude(ox,oy,circleBox(bodies)) end
    material.compose=function() return shared.material.sheetAt(-ox,-oy) end
    render({},bodies,nil)
    postProcess=nil
    item.label.Position=UDim2.fromOffset(ox/k,oy/k);item.label.Visible=true
   end
  end
  -- the drip gathering under the bar (one at a time)
  if not drip then
   if not nextDrip then nextDrip=clock+rand(3,6) end
   if clock<nextDrip or hi<=lo then return end
   nextDrip=clock+rand(9,16)
   drip={slot=slot(),start=clock,fx=rand(0,1),F=rand(1.1,1.55),Sd=rand(.5,.72),R=rand(8.5,10.5),spread=rand(16,24)}
  end
  local item=drip.slot;local R=drip.R
  local t=clock-drip.start
  if t>=drip.F+drip.Sd then
   -- pinch-off: hand it to the falling list; sometimes (always the first time)
   -- another drip starts gathering right away
   falling[#falling+1]={slot=item,R=R,x=drip.x,y1=drip.y1,v0=52/drip.Sd,t0=clock}
   if not doubled or rand(0,1)<.2 then doubled=true;nextDrip=clock+rand(.15,.4) end
   drip=nil
   return
  end
  -- hanging: gather under the edge, then sag on a thinning neck until it pinches off
  local x=lo+(hi-lo)*drip.fx
  local bodies={};local cy,rr
  if t<drip.F then
   local u=t/drip.F;local e=1-(1-u)^3
   rr=R*(.3+.7*e)*(1+.05*sin(t*6));cy=ey+rr*.55+3*e
   -- liquid gathering: two side beads slide in along the underside and merge
   local gap=drip.spread*(1-e);local sr=R*(.55-.25*e)
   if gap>1 then bodies[#bodies+1]={x-gap,ey+sr*.35,sr};bodies[#bodies+1]={x+gap,ey+sr*.35,sr} end
  else
   local u=(t-drip.F)/drip.Sd
   rr=R*(1-.06*u);cy=ey+R*.55+3+26*u*u
   for i=1,3 do local f=i/4;local nr=R*(.6-.48*u)*(1-.25*f);if nr>.8 then bodies[#bodies+1]={x,ey+(cy-ey)*f*.9,nr} end end
  end
  bodies[#bodies+1]={x,cy,rr}
  drip.x,drip.y1=x,cy
  local ox,oy=floor((x-WINDOW/2)/S)*S,floor((ey-64)/S)*S
  -- the tab bar's underside as the parent body; rows above it are erased afterwards
  local band={{x-70-ox,ey-30-oy},{x+70-ox,ey-30-oy},{x+70-ox,ey-oy},{x-70-ox,ey-oy}}
  local local_={};for j,b in ipairs(bodies) do local_[j]={b[1]-ox,b[2]-oy,b[3]} end
  use(item.surface);clearRow=nil
  local top=floor((ey-oy)/S)+1
  local clipBytes=min(OH,top*S+2)*OW*4
  postProcess=function() fill(pixels,0,0,clipBytes);tintCircles(local_,DRIP_TINT);occlude(ox,oy,circleBox(local_)) end
  material.compose=function() return shared.material.sheetAt(-ox,-oy) end
  render(band,local_,nil)
  postProcess=nil
  item.label.Position=UDim2.fromOffset(ox/k,oy/k);item.label.Visible=true
 end
 jobs[#jobs+1]={name='edge',interval=0,elapsed=0,
  active=function() return root.Visible and not Resize.dragging end,
  reset=clearAll,
  run=function(dt)
   local size=panelPixels();local w,h=size.X,size.Y;local r=contourRadius();local L=perimeter(w,h,r)
   local key=w..'x'..h..'x'..r
   if key~=outlineKey then
    outlineKey=key;table.clear(outline)
    local count=120
    for i=1,count do local x,y=outlineAt((i-1)/count*L,w,h,r);outline[i]={x,y} end
   end
   if clock>=nextSpawn then local border=0;for _,d in ipairs(drops) do if not d.impact then border+=1 end end;if border<MAX then spawn(w,h,r,L) end;nextSpawn=clock+rand(.55,1.6) end
   for i=#drops,1,-1 do
    local d=drops[i];local t=clock-d.start
    if t>=d.bud+d.float+d.back then d.slot.label.Visible=false;pool[#pool+1]=d.slot;table.remove(drops,i) else
     local arc,off,radius,sep,spin=d.arc,0,d.r,0,0
      if t<d.bud and d.impact then
       -- landed drip: splashes out past its resting distance, wobbles, settles (damped spring)
       local im=d.impact;local rest=-4+d.out;local w0,z=12,.34;local wd=w0*sqrt(1-z*z)
       local A=im.off-rest;local B=(im.v+z*w0*A)/wd;local decay=math.exp(-z*w0*t)
       local settle=1-clamp((t/d.bud-.75)/.25,0,1)
       off=rest+decay*(A*cos(wd*t)+B*sin(wd*t))*settle;radius*=1+.12*math.exp(-4*t)*sin(w0*1.3*t)
     elseif t<d.bud then off=-4+(1-(1-t/d.bud)^3)*d.out
     elseif t<d.bud+d.float then local u=(t-d.bud)/d.float;arc+=d.speed*(t-d.bud);off=-4+d.out+sin((t-d.bud)*d.bob*2+d.phase)*5;radius*=1+.08*sin((t-d.bud)*5)
      if d.split then local s=sin(pi*min(1,u*1.15));sep=s*radius*1.5;spin=(t-d.bud)*d.splitSpin;radius=max(8,radius*(1-.12*s)) end
     else local q=(t-d.bud-d.float)/d.back;local pull=-(cos(pi*min(1,q*1.05))-1)/2;arc+=d.speed*d.float+d.speed*.4*d.back*(1-(1-q)^2);off=-4+d.out*(1-pull)+sin((t-d.bud)*d.bob*2+d.phase)*5*(1-pull)
       -- last stretch: shrink and sink fully inside the edge, so removing the droplet changes nothing on screen (it used to vanish while still bulging = a snap)
       local sink=clamp((q-.55)/.45,0,1);sink=sink*sink*(3-2*sink);off-=sink*(radius+3);radius*=1-.5*sink end
     local ex,ey,nx,ny=outlineAt(arc,w,h,r)
     local cx0,cy0=ex+nx*off,ey+ny*off
     local bodies={}
     if sep>0 then for _,o in ipairs({0,pi}) do bodies[#bodies+1]={cx0+cos(spin+o)*sep,cy0+sin(spin+o)*sep,radius} end else bodies[1]={cx0,cy0,radius} end
     -- window: centred between the edge point and the droplet
     -- snapped to the mask grid (S px), so the panel edge inside the window is
     -- rasterised identically wherever the window sits (no 1 px edge jitter)
     local ox,oy=floor(((ex+cx0)/2-WINDOW/2)/S)*S,floor(((ey+cy0)/2-WINDOW/2)/S)*S
     local x0,y0,x1,y1=ex,ey,ex,ey
     for _,b in ipairs(bodies) do x0=min(x0,b[1]-b[3]);y0=min(y0,b[2]-b[3]);x1=max(x1,b[1]+b[3]);y1=max(y1,b[2]+b[3]) end
     x0,y0=max(0,floor(x0-ox-MARGIN)),max(0,floor(y0-oy-MARGIN));x1,y1=min(WINDOW,ceil(x1-ox+MARGIN)),min(WINDOW,ceil(y1-oy+MARGIN))
     local points={};for j,p in ipairs(outline) do points[j]={p[1]-ox,p[2]-oy} end
     local local_={};for j,b in ipairs(bodies) do local_[j]={b[1]-ox,b[2]-oy,b[3]} end
     local item=d.slot
     use(item.surface);clearRow=nil
     fadeBox={x0,y0,x1,y1};postProcess=feather
     if d.impact then
      local fadeTint=DRIP_TINT*(1-clamp(t/(d.bud+d.float*.5),0,1))
      local own={};for j,b in ipairs(bodies) do own[j]={b[1]-ox,b[2]-oy,b[3]} end
      postProcess=function() feather();tintCircles(own,fadeTint);occlude(ox,oy,circleBox(own)) end
     end
     material.compose=function() return shared.material.sheetAt(-ox,-oy) end
     render(points,local_,{floor(x0/S),floor(y0/S),ceil(x1/S)-1,ceil(y1/S)-1})
     postProcess=nil
     item.label.Position=UDim2.fromOffset(ox/k,oy/k);item.label.Visible=true
    end
   end
   updateDrip(w,h,r)
  end}
end

-- Notification morph, on parallel workers. The card is FILLED by simulated
-- liquid (particle fluid): it squeezes out of the panel edge, rushes across,
-- slams the far wall, sloshes back and floods the card; the neck snaps back and
-- the surface settles into the clean card, which stays as the notification's
-- body while the text shows. Closing drains it back through a wide neck.
-- The work runs on Roblox Parallel Luau actors (the executor's run_on_actor /
-- create_comm_channel / get_comm_channel): one actor simulates the liquid, two
-- draw half the picture each, at the same time on separate cores. The main
-- thread only sends the marble under the window and uploads finished pixels.
-- No actor support (or the workers don't answer) = toastMorph.ready() stays
-- false and notifications use the plain slide-in animation instead.
local toastMorph=nil
do
 local W_,H_=256,116
 local SIM_SRC=[==[
local id=...
local ch=get_comm_channel(id)
local floor,min,max,sqrt=math.floor,math.min,math.max,math.sqrt
local rng=Random.new()
local function rand(a,b) return rng:NextNumber(a,b) end
local function clamp01(v) if v<0 then return 0 elseif v>1 then return 1 end return v end
local FL={h=15,rho0=3,k=.65,kn=2.3,sig=.32,beta=.14,maxV=6.5,count=260,rush=5.6,rate=8}
local function sdRound(x,y,x0,y0,x1,y1,r)
 local qx=math.abs(x-(x0+x1)/2)-((x1-x0)/2-r);local qy=math.abs(y-(y0+y1)/2)-((y1-y0)/2-r)
 local ox,oy=max(qx,0),max(qy,0)
 return sqrt(ox*ox+oy*oy)+min(max(qx,qy),0)-r
end
local function newSim(g) return {visc=1,g=g,xs={},ys={},vx={},vy={},px={},py={},t=0,injected=0,neckOpen=true,neckH=3,mode='fill',snapAt=-1,suck=false,absorb=false} end
local function sdAllowed(sim,x,y)
 local g=sim.g
 local d=sdRound(x,y,g.gap,g.cy-g.ch/2,g.gap+g.cw,g.cy+g.ch/2,g.rad)
 if sim.neckOpen then d=min(d,sdRound(x,y,-10,g.cy-sim.neckH,g.gap+12,g.cy+sim.neckH,min(9,sim.neckH))) end
 return d
end
local function inject(sim,n,speed,spread)
 for _=1,n do local i=#sim.xs+1
  sim.xs[i]=-4.5+rand(0,2.2);sim.ys[i]=sim.g.cy+rand(-1,1)*spread
  sim.vx[i]=speed*rand(.9,1.1);sim.vy[i]=rand(-1,1)*speed*.08;sim.px[i]=0;sim.py[i]=0 end
 sim.injected+=n
end
local function removeAt(sim,i)
 local last=#sim.xs
 for _,arr in ipairs({sim.xs,sim.ys,sim.vx,sim.vy,sim.px,sim.py}) do arr[i]=arr[last];arr[last]=nil end
end
local function buildGrid(xs,ys,h)
 local grid={}
 for i=1,#xs do local key=floor(xs[i]/h)+floor(ys[i]/h)*4096;local c=grid[key];if not c then c={};grid[key]=c end;c[#c+1]=i end
 return grid
end
local function substep(sim,dt)
 local xs,ys,vx,vy,px,py=sim.xs,sim.ys,sim.vx,sim.vy,sim.px,sim.py
 -- drop any particle that went invalid (NaN or infinite) instead of poisoning the grid
 for i=#xs,1,-1 do if not (math.abs(xs[i])<1e5 and math.abs(ys[i])<1e5 and math.abs(vx[i])<1e5 and math.abs(vy[i])<1e5) then removeAt(sim,i) end end
 local n=#xs;if n==0 then return end
 local h=FL.h;local g=sim.g
 local grid=buildGrid(xs,ys,h)
 if sim.suck then for i=1,n do local e=(ys[i]-g.cy)/(g.ch/2);vx[i]-=.5*dt*(1+.9*e*e);if xs[i]<g.gap+16 then vy[i]+=(g.cy-ys[i])*.025*dt end end end
 for i=1,n do
  local cx,cy=floor(xs[i]/h),floor(ys[i]/h)
  for oy=-1,1 do for ox=-1,1 do local cell=grid[cx+ox+(cy+oy)*4096]
   if cell then for _,j in ipairs(cell) do if j>i then
    local dx,dy=xs[j]-xs[i],ys[j]-ys[i];local r=sqrt(dx*dx+dy*dy)
    if r>0 and r<h then local q=r/h;local ux,uy=dx/r,dy/r;local u=(vx[i]-vx[j])*ux+(vy[i]-vy[j])*uy
     if u>0 then local I=dt*(1-q)*(FL.sig*sim.visc*u+FL.beta*sim.visc*u*u)/2;if I>u*.5 then I=u*.5 end;vx[i]-=I*ux;vy[i]-=I*uy;vx[j]+=I*ux;vy[j]+=I*uy end end
   end end end end end
 end
 for i=1,n do
  local s=sqrt(vx[i]*vx[i]+vy[i]*vy[i]);if s>FL.maxV then vx[i]*=FL.maxV/s;vy[i]*=FL.maxV/s end
  px[i],py[i]=xs[i],ys[i];xs[i]+=vx[i]*dt;ys[i]+=vy[i]*dt
 end
 grid=buildGrid(xs,ys,h)
 local rho,rhoN=table.create(n,0),table.create(n,0)
 local pI,pJ,pQ={},{},{}
 for i=1,n do
  local cx,cy=floor(xs[i]/h),floor(ys[i]/h)
  for oy=-1,1 do for ox=-1,1 do local cell=grid[cx+ox+(cy+oy)*4096]
   if cell then for _,j in ipairs(cell) do if j>i then
    local dx,dy=xs[j]-xs[i],ys[j]-ys[i];local r=sqrt(dx*dx+dy*dy)
    if r<h then local q=1-r/h;local q2=q*q;local q3=q2*q
     rho[i]+=q2;rho[j]+=q2;rhoN[i]+=q3;rhoN[j]+=q3
     if r>1e-6 then local c=#pI+1;pI[c]=i;pJ[c]=j;pQ[c]=q end end
   end end end end end
 end
 local dt2=dt*dt
 for c=1,#pI do
  local i,j,q=pI[c],pJ[c],pQ[c]
  local dx,dy=xs[j]-xs[i],ys[j]-ys[i];local r=sqrt(dx*dx+dy*dy)
  if r>1e-6 then
   local P=FL.k*((rho[i]+rho[j])/2-FL.rho0);local Pn=FL.kn*(rhoN[i]+rhoN[j])/2
   local D=dt2*(P*q+Pn*q*q)/2;local ux,uy=dx/r*D,dy/r*D
   xs[j]+=ux;ys[j]+=uy;xs[i]-=ux;ys[i]-=uy
  end
 end
 for i=n,1,-1 do
  if not (math.abs(xs[i])<1e5 and math.abs(ys[i])<1e5) or (xs[i]<-6 and (sim.absorb or not sim.neckOpen)) then removeAt(sim,i) else
   if xs[i]<-6 then xs[i]=-6 end
   local d=sdAllowed(sim,xs[i],ys[i])+2
   if d>0 then
    local e=.5
    local gx=sdAllowed(sim,xs[i]+e,ys[i])-sdAllowed(sim,xs[i]-e,ys[i])
    local gy=sdAllowed(sim,xs[i],ys[i]+e)-sdAllowed(sim,xs[i],ys[i]-e)
    local gl=sqrt(gx*gx+gy*gy);if gl<1e-6 then gl=1 end
    xs[i]-=gx/gl*d;ys[i]-=gy/gl*d;px[i]+=(xs[i]-px[i])*.25
   end
  end
 end
 for i=1,#xs do vx[i]=(xs[i]-px[i])/dt;vy[i]=(ys[i]-py[i])/dt end
end
local function simFrame(sim)
 sim.t+=1/60
 local g=sim.g
 if sim.mode=='fill' then
  -- after the rush hits the far wall the liquid thickens: one clean slosh, no jiggling
  sim.visc=1+1.6*clamp01((sim.t-.55)/.35)
  -- the opening widens from a thin bud to the full stream
  local grow=clamp01((sim.t-.12)/.4);sim.neckH=3+8*grow*grow*(3-2*grow)
  if sim.t<.3 then if rand(0,1)<.55 then inject(sim,1,1.1,.8) end
  elseif sim.injected<FL.count then inject(sim,min(FL.rate,FL.count-sim.injected),FL.rush,min(4.6,sim.neckH*.45))
  elseif sim.snapAt<0 then sim.snapAt=sim.t+.12 end
  if sim.snapAt>0 and sim.t>=sim.snapAt and sim.neckOpen then
   sim.neckOpen=false
   for i=1,#sim.xs do if sim.xs[i]<g.gap+2 then sim.vx[i]=-3.3 end end
  end
  if not sim.neckOpen then for i=1,#sim.xs do if sim.xs[i]<g.gap-.5 then sim.vx[i]=min(sim.vx[i],-2.8) end end end
 end
 substep(sim,.5);substep(sim,.5)
end
local function fullSim(g)
 local sim=newSim(g);local d=6.6;local row=0
 local y=g.cy-g.ch/2+3.3
 while y<g.cy+g.ch/2-2 do
  local x=g.gap+3.3+(row%2)*d/2
  while x<g.gap+g.cw-2 do
   if sdRound(x,y,g.gap,g.cy-g.ch/2,g.gap+g.cw,g.cy+g.ch/2,g.rad)<-2.5 then
    local jx,jy=x+rand(-1.2,1.2),y+rand(-1.2,1.2)
    local i=#sim.xs+1;sim.xs[i]=jx;sim.ys[i]=jy;sim.vx[i]=0;sim.vy[i]=0;sim.px[i]=jx;sim.py[i]=jy end
   x+=d
  end
  y+=d*.866;row+=1
 end
 sim.injected=FL.count;sim.mode='drain';sim.neckOpen=true;sim.neckH=g.ch*.32;sim.suck=true;sim.absorb=true
 return sim
end
local sim,simClock=nil,0
local conn
conn=ch.Event:Connect(function(tag,a)
 if tag=='quit' then conn:Disconnect();sim=nil;return end
 if tag=='simOpen' then sim=newSim(a);simClock=os.clock()
 elseif tag=='simClose' then sim=fullSim(a);simClock=os.clock()
 elseif tag=='simStop' then sim=nil
 elseif tag=='tick' and sim then
  task.desynchronize()
  local now=os.clock();local due=floor((now-simClock)*60)
  if due>4 then simClock=now-4/60;due=4 end
  for _=1,due do simFrame(sim);simClock+=1/60 end
  local n=#sim.xs;local buf=buffer.create(math.max(1,n)*8)
  for i=1,n do buffer.writef32(buf,(i-1)*8,sim.xs[i]);buffer.writef32(buf,(i-1)*8+4,sim.ys[i]) end
  local neck,st,snap=sim.neckOpen,sim.t,sim.snapAt
  task.synchronize()
  ch:Fire('pos',buf,n,neck,st,snap)
 end
end)
ch:Fire('ready')
]==]
 local RENDER_SRC=[==[
local id,part,parts,W,H=...
local ch=get_comm_channel(id)
local floor,min,max,sqrt,exp,abs=math.floor,math.min,math.max,math.sqrt,math.exp,math.abs
local readu32,writeu32,readf32=buffer.readu32,buffer.writeu32,buffer.readf32
local RIM_R,RIM_G,RIM_B=226,214,246
local FW,FH=W//2+1,H//2+1
-- rim light falloffs as tables (16 steps per px) instead of two exp() per pixel
local RIM_NEAR,RIM_BROAD={},{}
for i=0,1024 do RIM_NEAR[i]=exp(-i/16*.8)*.8;RIM_BROAD[i]=exp(-i/16*.13)*.22 end
local lastMat=nil
local field,tmp,pf,cf=table.create(FW*FH,0),table.create(FW*FH,0),table.create(FW*FH,0),table.create(FW*FH,0)
-- 1-2-1 smoothing pass over a 2 px grid array
local function smooth(a)
 for j=0,FH-1 do local row=j*FW
  tmp[row+1]=a[row+1];tmp[row+FW]=a[row+FW]
  for i=1,FW-2 do tmp[row+i+1]=(a[row+i]+2*a[row+i+1]+a[row+i+2])*.25 end end
 for i=0,FW-1 do
  a[i+1]=tmp[i+1];a[(FH-1)*FW+i+1]=tmp[(FH-1)*FW+i+1]
  for j=1,FH-2 do a[j*FW+i+1]=(tmp[(j-1)*FW+i+1]+2*tmp[j*FW+i+1]+tmp[(j+1)*FW+i+1])*.25 end end
end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function sdRR(x,y,x0,y0,x1,y1,r)
 local qx=abs(x-(x0+x1)/2)-((x1-x0)/2-r);local qy=abs(y-(y0+y1)/2)-((y1-y0)/2-r)
 local ox,oy=max(qx,0),max(qy,0)
 return sqrt(ox*ox+oy*oy)+min(max(qx,qy),0)-r
end
local y0,y1=floor(H*(part-1)/parts),floor(H*part/parts)
local conn
conn=ch.Event:Connect(function(tag,fid,ox,oy,w,h,r,dir,ex,g,cardScale,pos,n,mat,maskMode,rimAmount)
 if tag=='quit' then conn:Disconnect();lastMat=nil;return end
 -- the marble crop is only sent when it changed
 if tag=='tick' then if mat then lastMat=mat else mat=lastMat end;if not mat and not maskMode then return end end
 if tag=='rim' then RIM_R,RIM_G,RIM_B=fid,ox,oy;return end
 if tag~='tick' then return end
 task.desynchronize()
 -- field on a 2 px grid: the panel itself, the settling card, the particles
 local cx0,hw,hh,cr=0,0,0,0
 if cardScale>0 then cx0=ex+dir*(g.gap+g.cw/2);hw,hh,cr=g.cw*cardScale/2,g.ch*cardScale/2,g.rad*cardScale end
 for j=0,FH-1 do
  local py=oy+j*2;local row=j*FW
  for i=0,FW-1 do
   local px=ox+i*2
   local f=0
   if (dir>0 and px<w+14) or (dir<0 and px>-14) then
    local sd=sdRR(px,py,0,0,w,h,r)
    f=sd<=0 and clamp(.5-sd/5,0,6) or clamp(.5-sd/24,0,.5)
   end
   local c=0
   if cardScale>0 and px>cx0-hw-4 and px<cx0+hw+4 then c=clamp(.5-sdRR(px,py,cx0-hw,g.cy-hh,cx0+hw,g.cy+hh,cr)/5,0,6) end
   -- pf keeps the window's own share of the field, so its outline is never drawn
   -- cf keeps the card's share: only the window and the card wear the rim light
   if c>f then field[row+i+1]=c;pf[row+i+1]=0;cf[row+i+1]=c else field[row+i+1]=f;pf[row+i+1]=f;cf[row+i+1]=0 end
  end
 end
 if pos and n>0 then
  local R=3.6;local R2=R*R
  for p=0,n-1 do
   local X=ex+dir*readf32(pos,p*8);local Y=readf32(pos,p*8+4)
   local cx,cy=(X-ox)/2,(Y-oy)/2
   local i0,i1=max(0,floor(cx-R)),min(FW-1,math.ceil(cx+R))
   local j0,j1=max(0,floor(cy-R)),min(FH-1,math.ceil(cy+R))
   for j=j0,j1 do local dy=j-cy;local row=j*FW
    for i=i0,i1 do local dx=i-cx;local d2=dx*dx+dy*dy
     if d2<R2 then local k=1-d2/R2;field[row+i+1]+=k*k*.72 end end end
  end
  -- two smoothing passes: the particles read as one surface
  smooth(field);smooth(field)
 end
 -- shade this worker's rows: anti-aliased edge, Mercury's rim light, marble inside
 -- (each grid row's first/last cell above the edge threshold bounds the work)
 local jA,jB=floor(y0/2),math.min(FH-1,floor((y1-1)/2)+1)
 local spanLo,spanHi={},{}
 for j=jA,jB do
  local row=j*FW;local lo,hi=FW,-1
  for i=0,FW-1 do if field[row+i+1]>.2 then lo=i;break end end
  if lo<FW then for i=FW-1,lo,-1 do if field[row+i+1]>.2 then hi=i;break end end end
  spanLo[j],spanHi[j]=lo,hi
 end
 local out=buffer.create((y1-y0)*W*4)
 for y=y0,y1-1 do
  local fy=y/2;local jy=floor(fy);local ty=fy-jy;if jy>=FH-1 then jy=FH-2;ty=1 end
  local orow=(y-y0)*W
  local lo=min(spanLo[jy] or FW,spanLo[jy+1] or FW);local hi=max(spanHi[jy] or -1,spanHi[jy+1] or -1)
  for x=max(0,lo*2-2),min(W-1,hi*2+2) do
   local fx=x/2;local ix=floor(fx);local tx=fx-ix;if ix>=FW-1 then ix=FW-2;tx=1 end
   local i00=jy*FW+ix+1
   local a00,a10=field[i00],field[i00+1]
   local a01,a11=field[i00+FW],field[i00+FW+1]
   if not (rimAmount and rimAmount>0) and a00>=6 and a10>=6 and a01>=6 and a11>=6 and pf[i00]==0 and pf[i00+1]==0 and pf[i00+FW]==0 and pf[i00+FW+1]==0 then
    -- deep inside (flat plateau): no rim light, the marble shows as is
    local edge=min(min(x,W-1-x),min(y,H-1-y))
    local a=edge<22 and floor(edge/22*255+.5) or 255
    if maskMode then writeu32(out,(orow+x)*4,a*16777216) else writeu32(out,(orow+x)*4,readu32(mat,(y*W+x)*4)%16777216+a*16777216) end
    continue
   end
   local v=(a00*(1-tx)+a10*tx)*(1-ty)+(a01*(1-tx)+a11*tx)*ty
   if v>.2 then
    local pv=(pf[i00]*(1-tx)+pf[i00+1]*tx)*(1-ty)+(pf[i00+FW]*(1-tx)+pf[i00+FW+1]*tx)*ty
    local cv=(cf[i00]*(1-tx)+cf[i00+1]*tx)*(1-ty)+(cf[i00+FW]*(1-tx)+cf[i00+FW+1]*tx)*ty
    local gx=((a10-a00)*(1-ty)+(a11-a01)*ty)/2
    local gy=((a01-a00)*(1-tx)+(a11-a10)*tx)/2
    local gl=sqrt(gx*gx+gy*gy)+1e-6
    local dist=(v-.5)/gl
    local alpha=dist+.5
    if alpha>0 then
     if alpha>1 then alpha=1 end
     -- Rim light comes from the card's final outline only (the flowing liquid has
     -- none), faded in by rimAmount while the card settles: the last animation
     -- frame and the still card then have the very same border.
     local shine=0
     if rimAmount and rimAmount>0 then
      local px,py=ox+x+.5,oy+y+.5
      if dir*(px-ex)>g.gap-.5 then
       local mid=ex+dir*(g.gap+g.cw/2)
       local cx0,cy0,cx1,cy1=mid-g.cw/2,g.cy-g.ch/2,mid+g.cw/2,g.cy+g.ch/2
       local sd=sdRR(px,py,cx0,cy0,cx1,cy1,g.rad)
       if sd<.5 then
        local nx=sdRR(px+.5,py,cx0,cy0,cx1,cy1,g.rad)-sdRR(px-.5,py,cx0,cy0,cx1,cy1,g.rad)
        local ny=sdRR(px,py+.5,cx0,cy0,cx1,cy1,g.rad)-sdRR(px,py-.5,cx0,cy0,cx1,cy1,g.rad)
        local nl=sqrt(nx*nx+ny*ny)+1e-6
        local light=(-nx*.6-ny*.8)/nl;if light<0 then light=0 elseif light>1 then light=1 end
        local dd=-sd;if dd<0 then dd=0 end
        -- field just outside the card edge along its normal: liquid there means this edge is inside the liquid
        local qx,qy=(px+nx/nl*(dd+3)-ox)/2,(py+ny/nl*(dd+3)-oy)/2
        local qi,qj=floor(qx),floor(qy)
        local open=1
        if qi>=0 and qj>=0 and qi<FW-1 and qj<FH-1 then
         local fx2,fy2=qx-qi,qy-qj;local q00=qj*FW+qi+1
         local vo=(field[q00]*(1-fx2)+field[q00+1]*fx2)*(1-fy2)+(field[q00+FW]*(1-fx2)+field[q00+FW+1]*fx2)*fy2
         open=clamp((.5-vo)/.3,0,1)
        end
        local key=floor(dd*16);if key>1024 then key=1024 end
        shine=(RIM_NEAR[key]*(.18+.82*light)+RIM_BROAD[key]*light)*rimAmount*open;if shine>1 then shine=1 end
       end
      end
     end
     local edge=min(min(x,W-1-x),min(y,H-1-y));if edge<22 then alpha*=edge/22 end
     -- At the window the liquid is drawn only where the flowing liquid joins it:
     -- there the window's own edge and rim light bend smoothly into the stream
     -- (the merged outline), and they fade back to the real window around it.
     if pv>.02 then
      local joined=clamp((v-pv-cv-.08)/.25,0,1)
      alpha*=joined
      if joined>0 then
       local light=(gx*.6+gy*.8)/gl;if light<0 then light=0 elseif light>1 then light=1 end
       local dd=dist>0 and dist or 0
       local key=floor(dd*16);if key>1024 then key=1024 end
       local ps=RIM_NEAR[key]*(.18+.82*light)+RIM_BROAD[key]*light
       if ps>shine then shine=ps>1 and 1 or ps end
      end
     end
     -- on the card side the card's own outline bounds the liquid: blobs never bulge past it
     local px=ox+x+.5
     if dir*(px-ex)>g.gap+.5 then
      local mid=ex+dir*(g.gap+g.cw/2)
      local sc=sdRR(px,oy+y+.5,mid-g.cw/2,g.cy-g.ch/2,mid+g.cw/2,g.cy+g.ch/2,g.rad)
      if sc>-.5 then alpha*=clamp(.5-sc,0,1) end
     end
     if maskMode then
      -- the settled card's shape: alpha, and the rim light's strength in red
      writeu32(out,(orow+x)*4,floor(shine*255+.5)+floor(alpha*255+.5)*16777216)
      continue
     end
     local base=readu32(mat,(y*W+x)*4)
     local br,bg,bb=base%256,floor(base/256)%256,floor(base/65536)%256
     writeu32(out,(orow+x)*4,floor(br+(RIM_R-br)*shine+.5)+floor(bg+(RIM_G-bg)*shine+.5)*256+floor(bb+(RIM_B-bb)*shine+.5)*65536+floor(alpha*255+.5)*16777216)
    end
   end
  end
 end
 task.synchronize()
 ch:Fire('img',fid,part,y0,y1,out)
end)
ch:Fire('ready')
]==]
 local ready,readyCount=false,0
 local simChannel,drawChannel=nil,nil
 local image,label=nil,nil
 local m=nil
 local simState={got=false,n=0,neckOpen=true,t=0,snapAt=-1,buf=nil}
 local frameId,shownId=0,0
 local pending={}
 local crop=buffer.create(W_*H_*4)
 local function geometry(h)
  local cw,ch=TOAST_SIZE.X*k,TOAST_SIZE.Y*k
  return {gap=Layout.gap*k,cw=cw,ch=ch,cy=h-ch/2,rad=18*k}
 end
 local function mirror(v,n) if v<0 then v=-v-1 elseif v>=n then v=2*n-v-1 end;if v<0 then return 0 elseif v>=n then return n-1 end;return v end
 -- the marble under the window, cropped (mirrored past the sheet's edges) into
 -- a W x H buffer whose top-left sits at (ox, oy) in panel pixels
 local function cropInto(dest,W,H,ox,oy,mat,mx,my,mw,mh)
  local readu32,writeu32=buffer.readu32,buffer.writeu32
  for y=0,H-1 do
   local sy=mirror(y-my,mh)*mw
   local a,b=max(0,mx),min(W,mx+mw)
   if b>a then buffer.copy(dest,(y*W+a)*4,mat,(sy+a-mx)*4,(b-a)*4) end
   for x=0,min(a,W)-1 do writeu32(dest,(y*W+x)*4,readu32(mat,(sy+mirror(x-mx,mw))*4)) end
   for x=max(b,0),W-1 do writeu32(dest,(y*W+x)*4,readu32(mat,(sy+mirror(x-mx,mw))*4)) end
  end
 end
 -- the workers' crop: rebuilt (and sent) only when the marble sheet or the
 -- origin changed; returns nil when the workers' copy is still current
 local cropKey=nil
 local function cropMaterial(ox,oy)
  local mat,mx,my,mw,mh=shared.material.sheetAt(-ox,-oy)
  if not mat then if cropKey=='none' then return nil end;cropKey='none';buffer.fill(crop,0,0);return crop end
  local key=tostring(mat)..'|'..mx..'|'..my..'|'..ox..'|'..oy
  if key==cropKey then return nil end
  cropKey=key
  local fresh=buffer.create(W_*H_*4)
  cropInto(fresh,W_,H_,ox,oy,mat,mx,my,mw,mh)
  return fresh
 end
 -- While the card is up nothing about its shape changes. The workers draw its
 -- shape once (alpha + rim strength); from then on each frame only copies the
 -- marble under it into the card's pixels (no worker frames), and the rim light
 -- sits on top as a fixed overlay. Same image, same edge: nothing swaps.
 local live=nil -- {x0,y0,w,h,alpha={},shine={},index={},key,buf}
 local function liveBegin(maskBuf)
  -- bounding box of the card's pixels, their alpha and rim-light strength (0-256)
  local x0,y0,x1,y1=W_,H_,-1,-1
  for y=0,H_-1 do for x=0,W_-1 do
   if buffer.readu32(maskBuf,(y*W_+x)*4)>=16777216 then if x<x0 then x0=x end;if x>x1 then x1=x end;if y<y0 then y0=y end;if y>y1 then y1=y end end
  end end
  if x1<x0 then return false end
  local w,h=x1-x0+1,y1-y0+1
  local alpha,shine=table.create(w*h,0),table.create(w*h,0)
  for y=0,h-1 do for x=0,w-1 do
   local p=buffer.readu32(maskBuf,((y+y0)*W_+x+x0)*4)
   alpha[y*w+x+1]=(p//16777216)*16777216
   shine[y*w+x+1]=floor((p%256)/255*256+.5)
  end end
  live={x0=x0,y0=y0,w=w,h=h,alpha=alpha,shine=shine,key=nil,buf=buffer.create(w*h*4),index=table.create(w*h,0)}
  return true
 end
 local function liveDraw(ox,oy)
  local mat,mx,my,mw,mh=shared.material.sheetAt(-ox,-oy)
  if not mat then return end
  local w,h,x0,y0=live.w,live.h,live.x0,live.y0
  -- source index per card pixel (mirrored past the sheet), rebuilt when the sheet's geometry changes
  local key=mx..'|'..my..'|'..mw..'|'..mh
  local index=live.index
  if key~=live.key then
   live.key=key
   for y=0,h-1 do
    local sy=mirror(y+y0-my,mh)*mw
    for x=0,w-1 do index[y*w+x+1]=(sy+mirror(x+x0-mx,mw))*4 end
   end
  end
  local readu32,writeu32,buf,alpha,shine=buffer.readu32,buffer.writeu32,live.buf,live.alpha,live.shine
  local band=bit32.band
  local c=Theme.mist
  local rimRB=math.round(c.R*255)+math.round(c.B*255)*65536;local rimG=math.round(c.G*255)*256
  for i=1,w*h do
   local a=alpha[i]
   if a>0 then
    local base=readu32(mat,index[i])
    local s8=shine[i]
    if s8>0 then
     -- same blend as the workers: marble toward the rim colour by the rim strength
     local inv=256-s8
     base=band((band(base,16711935)*inv+rimRB*s8+8388736)//256,16711935)+band((band(base,65280)*inv+rimG*s8+32768)//256,65280)
    else
     base=base%16777216
    end
    writeu32(buf,(i-1)*4,base+a)
   end
  end
  image:WritePixelsBuffer(Vector2.new(x0,y0),Vector2.new(w,h),buf)
  label.Position=UDim2.fromOffset(ox/k,oy/k)
 end
 local function liveShow(on) end
 local function onSim(tag,buf,n,neck,st,snap)
  if tag=='ready' then readyCount+=1;ready=readyCount>=3
  elseif tag=='pos' then simState.got=true;simState.buf=buf;simState.n=n;simState.neckOpen=neck;simState.t=st;simState.snapAt=snap end
 end
 local function onDraw(tag,fid,part,y0,y1,buf)
  if tag=='ready' then readyCount+=1;ready=readyCount>=3;return end
  if tag~='img' or not image or fid<=shownId then return end
  local entry=pending[fid];if not entry then entry={};pending[fid]=entry end
  entry[part]={y0,y1,buf}
  if entry[1] and entry[2] then
   shownId=fid
   for f in pairs(pending) do if f<=fid then pending[f]=nil end end
   if entry.mask then
    if not (m and m.maskWanted) then return end
    m.maskWanted=nil
    local maskBuf=buffer.create(W_*H_*4)
    for _,piece in ipairs(entry) do buffer.copy(maskBuf,piece[1]*W_*4,piece[3],0,buffer.len(piece[3])) end
    if liveBegin(maskBuf) then
     -- clear the last animation frame first: liquid around the card from the
     -- settling flow would otherwise stay on screen behind it
     image:WritePixelsBuffer(Vector2.zero,Vector2.new(W_,H_),buffer.create(W_*H_*4))
     m.liveOn=true;liveDraw(entry.ox,entry.oy);liveShow(true)
    end
    return
   end
   if not m or m.liveOn then return end
   for _,piece in ipairs(entry) do image:WritePixelsBuffer(Vector2.new(0,piece[1]),Vector2.new(W_,piece[2]-piece[1]),piece[3]) end
   label.Position=UDim2.fromOffset(entry.ox/k,entry.oy/k);label.Visible=true
   liveShow(false) -- worker frames again (closing): the overlay goes
  end
 end
 local origins={}
 local function boot()
  local run,make,get=executorEnv.run_on_actor,executorEnv.create_comm_channel,executorEnv.get_comm_channel
  if typeof(run)~='function' or typeof(make)~='function' or typeof(get)~='function' then return end
  local ok,err=pcall(function()
   local holder=LocalPlayer:FindFirstChildOfClass('PlayerScripts') or LocalPlayer:WaitForChild('PlayerScripts',5)
   local simId,simCh=make();local drawId,drawCh=make()
   simChannel,drawChannel=simCh,drawCh
   track(simCh.Event:Connect(onSim));track(drawCh.Event:Connect(onDraw))
   -- this window's worker scripts stop when it closes (the actors are kept for the next window)
   track(function() pcall(function() simCh:Fire('quit');drawCh:Fire('quit') end) end)
   -- Each actor needs a running script to wake up; an empty LocalScript does it
   -- (the engine logs one line per actor for its empty body). The pool is kept for
   -- the whole game session and reused by every window, so that happens once.
   local reg=typeof(executorEnv.getgenv)=='function' and executorEnv.getgenv() or _G
   local actors=reg.__MercuryLiquidWorkers
   local alive=type(actors)=='table' and #actors==3
   if alive then for i=1,3 do if typeof(actors[i])~='Instance' or not actors[i]:IsDescendantOf(game) then alive=false end end end
   if not alive then
    actors={}
    for i=1,3 do
     local actor=Instance.new('Actor');actor.Name='MercuryLiquidWorker'..i;actor.Parent=holder
     local idle=Instance.new('LocalScript');idle.Name='Idle';idle.Parent=actor
     actors[i]=actor
    end
    reg.__MercuryLiquidWorkers=actors
    task.wait(.3)
   end
   run(actors[1],SIM_SRC,simId)
   run(actors[2],RENDER_SRC,drawId,1,2,W_,H_)
   run(actors[3],RENDER_SRC,drawId,2,2,W_,H_)
   local function sendRim(T) local c=T.mist;drawCh:Fire('rim',math.round(c.R*255),math.round(c.G*255),math.round(c.B*255)) end
   Resize.themeHooks=Resize.themeHooks or {};table.insert(Resize.themeHooks,sendRim)
   task.delay(.5,sendRim,Theme)
   image=AS:CreateEditableImage({Size=Vector2.new(W_,H_)})
   label=create('ImageLabel',{Name='ToastMorph',BackgroundTransparency=1,Size=UDim2.fromOffset(W_/k,H_/k),ImageContent=Content.fromObject(image),ZIndex=9,Visible=false,Parent=panel})
   passThrough(label)
   track(function() if image then image:Destroy() end end)
  end)
  if not ok then warn('[Mercury] parallel workers unavailable, using the simple notification: '..tostring(err));ready=false end
 end
 if Layout.performance~='Low' then task.spawn(boot) end
 local function finish()
  local cb=m and m.onDone;m=nil;if label then label.Visible=false end;liveShow(false);if cb then cb() end
 end
 track(RunService.Heartbeat:Connect(function()
  if not m or not ready then return end
  if not root.Visible then local held=m.hold;finish();if held then toast.Visible=false end;return end
  local now=os.clock()
  local size=panelPixels();local w,h=size.X,size.Y;local r=contourRadius()
  local g=m.g;local dir=m.onRight and 1 or -1;local ex=m.onRight and w or 0
  local ox=m.onRight and floor((ex-30)/2)*2 or floor((ex-g.gap-g.cw-30)/2)*2
  local oy=floor((g.cy-H_/2)/2)*2
  local cardScale,usePos,rim=0,true,0
  if m.opening then
   if m.hold then
    if m.liveOn then liveDraw(ox,oy);return end
    if m.maskWanted then return end -- the shape is on its way; the last frame stays up
    if now-(m.drawn or 0)<.012 then return end
    m.drawn=now;cardScale,usePos,rim=1,false,1
   else
    local total=Layout.transitionTime or 1.05
    if not m.settleAt and simState.got and not simState.neckOpen and now>=m.openClock+total-.3 then m.settleAt=now end
    local settle=m.settleAt and clamp((now-m.settleAt)/.3,0,1) or 0
    if settle>=1 then
     m.hold=true;m.drawn=now;simChannel:Fire('simStop');cardScale,usePos=1,false
     local cb=m.onDone;m.onDone=nil;if cb then cb() end
     -- the card is settled: ask the workers for its shape once, then go live
     m.maskWanted=true
     frameId+=1
     pending[frameId]={ox=ox,oy=oy,mask=true}
     drawChannel:Fire('tick',frameId,ox,oy,w,h,r,dir,ex,g,1,nil,0,nil,true,1)
     return
    else
     cardScale=settle>0 and (.9+.1*settle) or 0
     rim=settle
     simChannel:Fire('tick')
    end
   end
  else
   if now<m.start then
    if m.liveFrom then liveDraw(ox,oy);return end
    if now-(m.drawn or 0)<.012 then return end
    m.drawn=now;cardScale,usePos,rim=1,false,1
   else
    if not m.started then m.started=now;simState.got=false;simChannel:Fire('simClose',g) end
    rim=max(0,1-(now-m.started)/.25) -- the border fades as the card starts to drain
    simChannel:Fire('tick')
    if simState.got and simState.n==0 and now-m.started>.15 then finish();return end
   end
  end
  local fresh=cropMaterial(ox,oy)
  frameId+=1
  local entry=pending[frameId] or {};entry.ox,entry.oy=ox,oy;pending[frameId]=entry
  drawChannel:Fire('tick',frameId,ox,oy,w,h,r,dir,ex,g,cardScale,usePos and simState.buf or nil,usePos and simState.n or 0,fresh,false,rim)
 end))
 toastMorph={
  ready=function() return ready end,
  open=function(onRight,onDone)
   local h=panelPixels().Y
   simState.got=false;simState.n=0;simState.neckOpen=true;cropKey=nil
   m={opening=true,onRight=onRight,onDone=onDone,g=geometry(h),openClock=os.clock()}
   simChannel:Fire('simOpen',m.g)
  end,
  close=function(onRight,onDone)
   local h=panelPixels().Y
   cropKey=nil
   local wasLive=m and m.liveOn
   m={opening=false,onRight=onRight,onDone=onDone,g=geometry(h),start=os.clock()+.18,liveFrom=wasLive}
  end,
 }
end

-- Resize grip: a wide, softly tapered boomerang hugging the outside of the
-- bottom-right corner, in the liquid's own glass. Rendered once, 4x, reduced.
local gripImage=nil
do
 local grip=panel:FindFirstChild('ResizeGrip')
 if grip then
  local SCALE,SIZE=4,192
  local r=contourRadius()
  local inner=(r+3)*SCALE
  local surface=newSurface(SIZE,SIZE)
  local corner=24  -- corner-arc centre inside the render (render px)
  local points={}
  local function thickness(u) return (2.6+2.6*math.sin(pi*u)^.7)*SCALE end
  local A0,A1=math.rad(12),math.rad(78);local steps=28
  for i=0,steps do local u=i/steps;local a=A0+(A1-A0)*u;points[#points+1]={corner+cos(a)*inner,corner+sin(a)*inner} end
  for i=steps,0,-1 do local u=i/steps;local a=A0+(A1-A0)*u;local radius=inner+thickness(u);points[#points+1]={corner+cos(a)*radius,corner+sin(a)*radius} end
  use(surface);clearRow=bleedRow(SIZE);postProcess=nil;material.compose=nil
  local ok,err=pcall(render,points,{})
  if ok then
   local chain=reductionChain(SIZE,SIZE,2);reduce(surface.image,chain);gripImage=chain
   do -- themes: re-tint the baked grip from its original pixels
    local top=chain[#chain];local tsize=top.Size;local count=tsize.X*tsize.Y
    local original=top:ReadPixelsBuffer(Vector2.zero,tsize)
    Resize.themeHooks=Resize.themeHooks or {}
    table.insert(Resize.themeHooks,function()
     local tint=Resize.themeTint
     if not tint or tint.default then top:WritePixelsBuffer(Vector2.zero,tsize,original);return end
     local out=buffer.create(count*4)
     for i=0,count-1 do
      local p=buffer.readu32(original,i*4);local a=p//16777216
      if a>0 then
       local h,s,v=Color3.fromRGB(p%256,(p//256)%256,(p//65536)%256):ToHSV()
       local c=Color3.fromHSV(tint.hue,math.clamp(s*tint.sat,0,1),math.clamp(v*tint.value,0,1))
       buffer.writeu32(out,i*4,math.round(c.R*255)+math.round(c.G*255)*256+math.round(c.B*255)*65536+a*16777216)
      end
     end
     top:WritePixelsBuffer(Vector2.zero,tsize,out)
    end)
   end
   for _,child in ipairs(grip:GetChildren()) do if child:IsA('GuiObject') then child.Visible=false end end
   local box=grip.Size.X.Offset
   -- corner-arc centre in grip coordinates (logical): grip box is centred on the panel corner
   local cornerX=box/2-r/k
   local label=create('ImageLabel',{Name='LiquidGrip',BackgroundTransparency=1,ImageTransparency=.12,Position=UDim2.fromOffset(cornerX-corner/SCALE/k,cornerX-corner/SCALE/k),Size=UDim2.fromOffset(SIZE/SCALE/k,SIZE/SCALE/k),ImageContent=Content.fromObject(chain[#chain]),ZIndex=grip.ZIndex,Parent=grip})
   passThrough(label)
   local lit=false;local hovered=false
   local function paint()
    local want=hovered or Resize.dragging
    if want==lit then return end;lit=want
    tween(label,.18,{ImageTransparency=if want then 0 else .12})
   end
   track(grip.MouseEnter:Connect(function() hovered=true;paint() end))
   track(grip.MouseLeave:Connect(function() hovered=false;paint() end))
   jobs[#jobs+1]={name='grip',interval=0,elapsed=0,active=function() paint();return false end}
  else warn('[LiquidField] grip',err) end
  surface.image:Destroy()
 end
end

-- Drag skeleton, "Ghost Slab": tinted glass body with the panel's live marble
-- showing faintly through, the liquid rim, carved rows, one light sweep, the
-- violet glow kept for emphasis and brighter on the side it is moving toward,
-- and two faint outlines trailing behind.
do
 local outline=skeletonGroup and skeletonGroup:FindFirstChild('Outline')
 if outline then
  local radius=contourRadius()/k
  local outlineCorner=outline:FindFirstChildWhichIsA('UICorner')
  if outlineCorner then outlineCorner.CornerRadius=UDim.new(0,radius) end
  -- faint live marble: a copy of the backdrop layers, kept in step every frame
  local marble=backdrop:Clone()
  local layerPairs={}
  local originals,copies=backdrop:GetChildren(),marble:GetChildren()
  for i,original in ipairs(originals) do
   local copy=copies[i]
   if copy and copy.Name==original.Name and copy.ClassName==original.ClassName and original:IsA('GuiObject') then
    if original.Name=='LiquidRim' then copy:Destroy()
    else layerPairs[#layerPairs+1]={original,copy,original:FindFirstChildWhichIsA('UIGradient'),copy:FindFirstChildWhichIsA('UIGradient')} end
   end
  end
  marble.Name='Marble';marble.Visible=true;marble.GroupTransparency=.82;marble.ZIndex=1
  marble.Position=UDim2.fromScale(0,0);marble.Size=UDim2.fromScale(1,1);marble.Parent=outline
  -- liquid rim at full strength
  local rim=backdrop:FindFirstChild('LiquidRim')
  if rim then rim=rim:Clone();rim.ZIndex=2;rim.Parent=outline end
  -- one light sweep across the slab; the panel's render loop drives its offset
  local sweepClip=create('CanvasGroup',{Name='Sweep',BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=5,Parent=outline})
  passThrough(sweepClip)
  create('UICorner',{CornerRadius=UDim.new(0,radius),Parent=sweepClip})
  local sheen=create('Frame',{BackgroundColor3=Theme.spec,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=5,Parent=sweepClip})
  passThrough(sheen)
  local sweep=create('UIGradient',{Rotation=12,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.42,1),NumberSequenceKeypoint.new(.5,.85),NumberSequenceKeypoint.new(.58,1),NumberSequenceKeypoint.new(1,1)}),Parent=sheen})
  table.clear(boneGradients);table.insert(boneGradients,sweep)
  -- leading-edge glow: a second copy of the glow, pushed toward the motion
  local lead=skeletonGlow and skeletonGlow:Clone()
  if lead then lead.Name='LeadGlow';lead.ImageTransparency=1;lead.Parent=skeletonGhost end
  local leadBase=lead and lead.Position
  -- Trailing outlines, drawn only OUTSIDE the skeleton. A trail is the ghost's
  -- rectangle lagging behind it; the part outside the ghost is two axis-aligned
  -- bands (the side it trails on, and the top or bottom it trails on), so each
  -- trail is shown through two clipping frames that cover exactly those bands.
  local GLOW_REACH=40   -- px of glow kept outside the trail's own edge
  local trails={}
  -- chained: each trail follows the one ahead of it (the first follows the
  -- skeleton) at the same rate, and no link stretches past TRAIL_GAP, so the
  -- three stay evenly spaced however fast the drag is
  local TRAIL_GAP=22
  for i,spec in ipairs({{alpha=.55,glow=.22,rate=18},{alpha=.38,glow=.14,rate=18},{alpha=.22,glow=.08,rate=18}}) do
   local parts={}
   for j=1,2 do
    local clip=create('Frame',{Name='DragTrail'..i..'_'..j,BackgroundTransparency=1,ClipsDescendants=true,Visible=false,ZIndex=19-i,Parent=screenGui})
    passThrough(clip)
    local body=create('Frame',{BackgroundTransparency=1,ZIndex=19-i,Parent=clip})
    create('UICorner',{CornerRadius=UDim.new(0,radius*k),Parent=body})
    local stroke=create('UIStroke',{Color=Color3.new(1,1,1),Thickness=1.5,Transparency=1,Parent=body})
    create('UIGradient',{Rotation=45,Color=ColorSequence.new(Theme.lilac,Theme.violet),Parent=stroke})
    local glow=nil
    if skeletonGlow then
     glow=skeletonGlow:Clone();glow.Name='TrailGlow';glow.ImageTransparency=1
     local position,size=skeletonGlow.Position,skeletonGlow.Size
     glow.Position=UDim2.fromOffset(position.X.Offset*k,position.Y.Offset*k)
     glow.Size=UDim2.new(1,size.X.Offset*k,1,size.Y.Offset*k)
     glow.SliceScale=skeletonGlow.SliceScale*k;glow.ZIndex=body.ZIndex;glow.Parent=body
    end
    parts[j]={clip=clip,body=body,stroke=stroke,glow=glow}
   end
   trails[i]={parts=parts,alpha=spec.alpha,glowAlpha=spec.glow,rate=spec.rate,position=nil}
  end
  local function hideTrail(t) for _,part in ipairs(t.parts) do part.clip.Visible=false end end
  -- place one band: screen rect (x0,y0)-(x1,y1); the trail body keeps its own spot
  local function band(part,x0,y0,x1,y1,trailPosition,size,origin)
   if x1-x0<1 or y1-y0<1 then part.clip.Visible=false;return end
   part.clip.Position=UDim2.fromOffset(x0-origin.X,y0-origin.Y);part.clip.Size=UDim2.fromOffset(x1-x0,y1-y0)
   part.body.Position=UDim2.fromOffset(trailPosition.X-x0,trailPosition.Y-y0);part.body.Size=UDim2.fromOffset(size.X,size.Y)
   part.clip.Visible=true
  end
  local last,velocity=nil,Vector2.zero
  track(RunService.RenderStepped:Connect(function(dt)
   if not skeletonGhost.Visible then
    if last then last=nil;velocity=Vector2.zero;for _,t in ipairs(trails) do hideTrail(t);t.position=nil end end
    return
   end
   for _,pair in ipairs(layerPairs) do
    local original,copy=pair[1],pair[2]
    copy.Position=original.Position;copy.Rotation=original.Rotation;copy.Size=original.Size
    if original:IsA('ImageLabel') then copy.ImageRectOffset=original.ImageRectOffset;copy.ImageRectSize=original.ImageRectSize;copy.ImageTransparency=original.ImageTransparency end
    if pair[3] and pair[4] then pair[4].Offset=pair[3].Offset;pair[4].Rotation=pair[3].Rotation end
   end
   local position,size=skeletonGhost.AbsolutePosition,skeletonGhost.AbsoluteSize
   local fade=1-skeletonGroup.GroupTransparency
   if last and dt>0 then velocity=velocity:Lerp((position-last)/dt,min(1,dt*12)) end
   last=position
   local speed=min(1,velocity.Magnitude/900)
   if lead and leadBase then
    local push=speed>.01 and velocity.Unit*10*speed or Vector2.zero
    lead.Position=leadBase+UDim2.fromOffset(push.X/k,push.Y/k)
    lead.ImageTransparency=1-(1-GLOW_SPRITE.visibleTransparency)*speed*fade
   end
   local origin=screenGui.AbsolutePosition
   local leader=position
   for _,t in ipairs(trails) do
    local p=t.position and t.position:Lerp(leader,min(1,dt*t.rate)) or leader
    local link=p-leader
    if link.Magnitude>TRAIL_GAP then p=leader+link.Unit*TRAIL_GAP end
    t.position=p;leader=p
    local T,G,m=t.position,position,GLOW_REACH
    local d=G-T
    local lag=min(1,d.Magnitude/12)
    if lag<.02 then hideTrail(t) else
     -- side band: the columns of the trail that lie beside the ghost
     local sx0,sx1,hx0,hx1
     if d.X>0 then sx0,sx1,hx0,hx1=T.X-m,G.X,G.X,T.X+size.X+m
     elseif d.X<0 then sx0,sx1,hx0,hx1=G.X+size.X,T.X+size.X+m,T.X-m,G.X+size.X
     else sx0,sx1,hx0,hx1=0,0,T.X-m,T.X+size.X+m end
     band(t.parts[1],sx0,T.Y-m,sx1,T.Y+size.Y+m,T,size,origin)
     -- top/bottom band: the rows of the trail above or below the ghost
     local hy0,hy1
     if d.Y>0 then hy0,hy1=T.Y-m,G.Y elseif d.Y<0 then hy0,hy1=G.Y+size.Y,T.Y+size.Y+m else hy0,hy1=0,0 end
     band(t.parts[2],hx0,hy0,hx1,hy1,T,size,origin)
     for _,part in ipairs(t.parts) do
      part.stroke.Transparency=1-t.alpha*lag*fade
      if part.glow then part.glow.ImageTransparency=1-t.glowAlpha*lag*fade end
     end
    end
   end
  end))
 end
end

-- Smooth scrolling: the mouse wheel over one of the panel's scrolling lists is
-- handled here. Each notch moves the list a fixed distance and the move eases in
-- over a few frames; Roblox's own wheel step for that moment is ignored so the two
-- never fight. Dragging the scrollbar, touch and code-driven scrolling are left
-- exactly as they are.
do
 local WHEEL_STEP=110  -- px per wheel notch
 local UserInput=game:GetService('UserInputService')
 local scrollers={}
 local wheelUntil=-math.huge
 local function attach(frame)
  if scrollers[frame] then return end
  local entry={current=frame.CanvasPosition,target=nil,setting=false}
  scrollers[frame]=entry
  track(frame:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
   if entry.setting then return end
   if entry.target and os.clock()<wheelUntil then
    -- Roblox's own wheel step while ours runs: undo it
    entry.setting=true;frame.CanvasPosition=entry.current;entry.setting=false
   else
    entry.current=frame.CanvasPosition;entry.target=nil
   end
  end))
 end
 local function shown(item)
  while item and item~=screenGui do
   if item:IsA('GuiObject') and not item.Visible then return false end
   item=item.Parent
  end
  return true
 end
 local function limitOf(frame)
  return Vector2.new(max(0,frame.AbsoluteCanvasSize.X-frame.AbsoluteWindowSize.X),max(0,frame.AbsoluteCanvasSize.Y-frame.AbsoluteWindowSize.Y))
 end
 for _,item in ipairs(root:GetDescendants()) do if item:IsA('ScrollingFrame') then attach(item) end end
 track(root.DescendantAdded:Connect(function(item) if item:IsA('ScrollingFrame') then attach(item) end end))
 track(UserInput.InputChanged:Connect(function(input)
  if input.UserInputType~=Enum.UserInputType.MouseWheel or input.Position.Z==0 then return end
  -- the innermost visible, scrollable list under the cursor
  local mouse=UserInput:GetMouseLocation()-Vector2.new(0,game:GetService('GuiService'):GetGuiInset().Y)
  local best,bestArea=nil,math.huge
  for frame in pairs(scrollers) do
   if frame.Parent and frame.ScrollingEnabled and limitOf(frame).Y>0 then
    local p,sz=frame.AbsolutePosition,frame.AbsoluteSize
    if mouse.X>=p.X and mouse.Y>=p.Y and mouse.X<=p.X+sz.X and mouse.Y<=p.Y+sz.Y and shown(frame) and sz.X*sz.Y<bestArea then best,bestArea=frame,sz.X*sz.Y end
   end
  end
  if not best then return end
  local entry=scrollers[best];local limit=limitOf(best)
  local goal=(entry.target or entry.current)-Vector2.new(0,input.Position.Z*WHEEL_STEP)
  entry.target=Vector2.new(entry.current.X,clamp(goal.Y,0,limit.Y))
  wheelUntil=os.clock()+.35
 end))
 track(RunService.RenderStepped:Connect(function(dt)
  for frame,entry in pairs(scrollers) do
   if not frame.Parent then scrollers[frame]=nil
   elseif entry.target then
    local nextPosition=entry.current:Lerp(entry.target,1-math.exp(-dt*14))
    if (entry.target-nextPosition).Magnitude<.5 then nextPosition=entry.target;entry.target=nil end
    entry.current=nextPosition
    entry.setting=true;frame.CanvasPosition=nextPosition;entry.setting=false
    if entry.target then wheelUntil=max(wheelUntil,os.clock()+.05) end
   end
  end
 end))
end

-- Runner: one job renders at a time (they share the renderer state), paced by
-- the shared frame budget; the transition always has priority.
local runner=nil
local runnerArgs=nil
local runnerJob=nil
local nextJob=1
local wasActive={}
liquid.pauseField=function()
 runner=nil;runnerArgs=nil;runnerJob=nil
 for _,job in ipairs(jobs) do
  if job.reset then job.reset() end
  wasActive[job]=false
 end
end
liquid.service=function(dt)
 if stopped then return end
 clock=os.clock()-epoch
 for _,job in ipairs(jobs) do
  local on=job.active()
  if not on and wasActive[job] then
   if runnerJob==job then runner=nil;runnerArgs=nil;runnerJob=nil end
   if job.reset then job.reset() end
  end
  wasActive[job]=on
  job.elapsed+=dt
 end
 -- Jobs take turns (round robin); when one finishes inside this frame's slice
 -- the next due job starts in the same frame, so each redraws as often as the
 -- budget allows.
 for _=1,#jobs do
  if not runner then
   local count=#jobs
   for step=1,count do
    local index=(nextJob+step-2)%count+1
    local job=jobs[index]
    if wasActive[job] and job.run and job.elapsed>=job.interval then
     local delta=job.elapsed;job.elapsed=0;nextJob=index%count+1
     runner=coroutine.create(job.run);runnerArgs={delta};runnerJob=job
     break
    end
   end
  end
  if not runner then break end
  pacing.budget=pacing.limit;pacing.start=pacing.frameStart
  local args=runnerArgs;runnerArgs=nil
  local ok,err
  if args then ok,err=coroutine.resume(runner,args[1]) else ok,err=coroutine.resume(runner) end
  pacing.budget=nil
  if not ok then runner=nil;runnerJob=nil;error(err,0) end
  if coroutine.status(runner)=='dead' then runner=nil;runnerJob=nil else break end
  if os.clock()-pacing.frameStart>pacing.limit then break end
 end
end
track(function() stopped=true;liquid.service=nil end)
return {jobs=jobs,toast=toastMorph}
end)()
end) if not fieldOk then warn('[LiquidField] disabled',fieldError) end end
Resize.liquidToast=liquidField and liquidField.toast or nil

        function Resize.setMinimized(minimized: boolean, instant: boolean?)
            if state.closing then return end
            if Resize.animating then liquid.start(minimized,instant);return end
            if Resize.minimized == minimized then return end
            local ok,err=pcall(liquid.start,minimized,instant)
            if not ok then warn('[LiquidIntegration] transition unavailable',err);return end
            Resize.minimized=minimized
        end

        -- bubble: click to restore, drag to move (4px threshold tells them apart)
        local bubbleDrag = { pending = false, moved = false, start = Vector2.zero, origin = Vector2.zero }
        track(bubble.InputBegan:Connect(function(input: InputObject)
            if Resize.animating then return end
            if not isPointerInput(input) then
                return
            end
            bubbleDrag.pending = true
            bubbleDrag.moved = false
            bubbleDrag.start = Vector2.new(input.Position.X, input.Position.Y)
            bubbleDrag.origin = Vector2.new(bubble.Position.X.Offset, bubble.Position.Y.Offset)
        end))
        track(UserInputService.InputChanged:Connect(function(input: InputObject)
            if not bubbleDrag.pending or not isMoveInput(input) then
                return
            end
            local delta = Vector2.new(input.Position.X, input.Position.Y) - bubbleDrag.start
            if not bubbleDrag.moved and delta.Magnitude < 4 then
                return
            end
            bubbleDrag.moved = true
            placeBubble(bubbleDrag.origin + delta)
        end))
        track(UserInputService.InputEnded:Connect(function(input: InputObject)
            if not bubbleDrag.pending or not isPointerInput(input) then
                return
            end
            bubbleDrag.pending = false
            if not bubbleDrag.moved then Resize.setMinimized(false) end
        end))
        track(bubble.MouseEnter:Connect(function()
            tween(bubbleScale, 0.22, { Scale = Layout.uiScale * 1.06 })
        end))
        track(bubble.MouseLeave:Connect(function()
            tween(bubbleScale, 0.28, { Scale = Layout.uiScale })
        end))
    end)()
    track(minimizeButton.MouseButton1Click:Connect(function()
        Resize.setMinimized(not Resize.minimized)
    end))
    track(minimizeButton.MouseEnter:Connect(function()
        closeHovered = true -- also keeps the header drag from starting here
        tween(minimizeButton, 0.18, { BackgroundTransparency = 0.82 })
    end))
    track(minimizeButton.MouseLeave:Connect(function()
        closeHovered = false
        tween(minimizeButton, 0.25, { BackgroundTransparency = 0.93 })
    end))
    track(UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
        if not gameProcessed and input.KeyCode == Layout.minimizeKey then
            Resize.setMinimized(not Resize.minimized)
        end
    end))
end

-- Animation: liquid drift, light follows the cursor, skeleton shimmer
local clock = 0

local function onRenderStep(deltaTime: number)
    clock += deltaTime

    for _, vein in veins do
        vein.frame.Rotation = vein.base + math.sin(clock * vein.speed + vein.phase) * vein.swing
        vein.gradient.Offset = Vector2.new(math.sin(clock * vein.speed * 1.3 + vein.phase) * vein.drift, 0)
    end
    for _, blob in blobs do
        blob.frame.Position = UDim2.fromScale(
            blob.center.X + math.cos(clock * blob.speed + blob.phase) * blob.radius.X,
            blob.center.Y + math.sin(clock * blob.speed * 0.8 + blob.phase) * blob.radius.Y
        )
    end
    for _, lava in lavaLayers do
        -- slow, viscous creep with a gentle surge so it never moves linearly
        local travel = lava.velocity * (clock + 0.4 * math.sin(clock * 0.15 + lava.phase) / 0.15)
        lava.label.ImageRectOffset = Vector2.new(
            (lava.origin.X + travel.X) % Lava.tile,
            (lava.origin.Y + travel.Y) % Lava.tile
        )
    end
    if Liquid.stars then
        Liquid.stars.update(clock)
    end
    logoGradient.Rotation = (clock * 90) % 360
    if Resize.bubbleGradient then
        Resize.bubbleGradient.Rotation = (clock * 90) % 360
    end
    ScrollHints.update()
    for _, wave in waveLayers do
        -- integrate a gently breathing speed so the drift never looks mechanical
        local travel = wave.velocity * (clock + Liquid.sway * math.sin(clock * 0.23 + wave.phase) / 0.23)
        local x = (wave.origin.X + travel.X) % WAVE_TILE
        local y = (wave.origin.Y + travel.Y) % WAVE_TILE
        wave.label.ImageRectOffset = Vector2.new(x, y)
    end

    if skeletonGhost.Visible then
        skeletonGradient.Rotation = (clock * 140) % 360
        local shimmer = ((clock * 0.9) % 2) - 1
        for _, gradient in boneGradients do
            gradient.Offset = Vector2.new(shimmer, 0)
        end
    end
end


-- source: lifecycle.lua
local toastToken = 0
local function sweepToastGlint(token: number)
    ToastGlint.rest()
    task.delay(0.2, function()
        if token ~= toastToken or not toast.Parent then return end
        local width = toast.AbsoluteSize.X
        local from, to = -20, width + ToastGlint.SPAN * 0.6 + 20
        local started, duration = os.clock(), 1.1
        local connection
        connection = RunService.Heartbeat:Connect(function()
            local a = math.clamp((os.clock() - started) / duration, 0, 1)
            if token ~= toastToken or not toast.Parent then connection:Disconnect(); ToastGlint.rest(); return end
            local eased = if a < 0.5 then 2 * a * a else 1 - (-2 * a + 2) ^ 2 / 2
            ToastGlint.at(from + (to - from) * eased)
            if a >= 1 then connection:Disconnect(); ToastGlint.rest() end
        end)
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


-- source: api.lua
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

end
return Mercury
