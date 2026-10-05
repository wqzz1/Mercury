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
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                -- Status lines can be mid-tween when the snapshot is taken; their
                -- FadeTarget is where they're heading, so fade to that instead.
                local target = object:GetAttribute("FadeTarget")
                local base = if typeof(target) == "number" then target else object.TextTransparency
                table.insert(entries, { instance = object, property = "TextTransparency", base = base })
            end
            if object:IsA("ScrollingFrame") then
                table.insert(entries, { instance = object, property = "ScrollBarImageTransparency", base = object.ScrollBarImageTransparency })
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

