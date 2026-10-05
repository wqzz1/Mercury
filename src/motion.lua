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
        if Resize.syncBones then Resize.syncBones() end
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
            lava.label.ImageRectSize = rect * (Lava.texScale or 1)
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
 -- EditableImage's BlendSourceOver floors: floor(d+(s-d)*A/255), so each layer
 -- blended over the marble loses ~0.55 of a level. The marble stacks 4-6 such
 -- layers and came out ~2.5 levels darker than the GPU-drawn panel (measured on
 -- screen: -2.7/-2.5/-2.3 RGB), which showed as a darker liquid during the
 -- minimize morph. Layer pixels are stored pre-compensated instead:
 --  * colour raised by 0.5*255/A: the floored blend then lands on the rounded
 --    value for any destination (exact);
 --  * where that would pass 255 (the white lava, the warm gloss) the alpha is
 --    raised by one step on an ordered-dither share of pixels, worth half a
 --    level on average over the dark marble (DITHER_REF: typical level below).
 local BAYER={[0]=0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5}
 local DITHER_REF=40
 local function overPixel(r,g,b,A,x,y)
  if A<=0 or A>=255 then return r+g*256+b*65536+A*16777216 end
  local lift=127.5/A
  local r2,g2,b2=floor(r+lift+.5),floor(g+lift+.5),floor(b+lift+.5)
  if r2<=255 and g2<=255 and b2<=255 then return r2+g2*256+b2*65536+A*16777216 end
  local gain=(r+g+b)/3-DITHER_REF
  if gain>0 and BAYER[(y%4)*4+x%4]<8*255/gain then A+=1 end
  return r+g*256+b*65536+A*16777216
 end
 -- the same, applied in place to an already drawn layer image
 local function compensateImage(image,w,h,yield)
  local readu32=buffer.readu32
  local buf=image:ReadPixelsBuffer(Vector2.zero,Vector2.new(w,h))
  local memo={};local slice=os.clock()
  for y=0,h-1 do
   local row=y*w*4;local by=(y%4)*4
   for x=0,w-1 do
    local off=row+x*4;local v=readu32(buf,off)
    if v>=16777216 and v<4278190080 then
     local key=v*16+by+x%4;local out=memo[key]
     if not out then local A=v//16777216;local rgb=v%16777216;out=overPixel(rgb%256,(rgb//256)%256,rgb//65536,A,x,y);memo[key]=out end
     writeu32(buf,off,out)
    end
   end
   if yield and os.clock()-slice>.002 then task.wait();slice=os.clock() end
  end
  image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),buf)
 end
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
 local function orbPixels(orb,size,D,yield,comp)
  local c=size/2;local n=orb.rings;local keep=1-orb.alpha
  local R,G,B=byte(orb.color.R),byte(orb.color.G),byte(orb.color.B)
  local rgb=R+G*256+B*65536
  local buf=buffer.create(size*size*4);local slice=os.clock()
  for y=0,size-1 do for x=0,size-1 do
   -- rings at scale 1-(j-1)/n*.92 cover this pixel: a count linear in radius
   local d=sqrt((x+.5-c)^2+(y+.5-c)^2);local count=clamp((1-2*d/D)*n/.92+.5,0,n)
   if count>0 then
    local A=round((1-keep^(count/n))*255)
    writeu32(buf,(y*size+x)*4,if comp then overPixel(R,G,B,A,x,y) else rgb+A*16777216)
   end
  end
   if yield and os.clock()-slice>.002 then task.wait();slice=os.clock() end
  end
  return buf
 end
 do
  local k=Layout.uiScale
  for i,orb in ipairs(orbData) do
   local D=orb.frame.Size.X.Offset*k;local size=ceil(D)+2
   local image=newImage(size,size);image:WritePixelsBuffer(Vector2.zero,Vector2.new(size,size),orbPixels(orb,size,D,false,true))
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
   local TR,TG,TB=byte(tr),byte(tg),byte(tb)
   local rowT=.5+(v-.5)*sb
   for i=0,BW-1 do
    local px=i-MARGIN+.5;local dx=max(0,-px,px-Wp)
    local idx=round(clamp(rowT+(clamp(px/Wp,0,1)-.5)*cb,0,1)*1023)
    local r,g,b=lr[idx],lg[idx],lb[idx];local fade=0
    if dx>0 or dy>0 then local d=min(1,sqrt(dx*dx+dy*dy)/MARGIN);fade=d*d*(3-2*d);r=round(r+(ir-r)*fade);g=round(g+(ig-g)*fade);b=round(b+(ib-b)*fade) end
    local off=(j*BW+i)*4
    writeu32(baseBuf,off,r+g*256+b*65536+4278190080)
    if ta>0 then writeu32(topBuf,off,overPixel(TR,TG,TB,round(ta*(1-fade)*255),i,j)) end
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
     compensateImage(sub.image,sub.w,sub.h,yield)
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
     local buf=orbPixels(orb,sprite.size,sprite.D,true,true)
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
 -- (these skip the blend compensation above; the full recolor() every few
 -- seconds restores it)
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
   local vr,vg,vb=rgb%256,(rgb//256)%256,rgb//65536
   buffer.fill(buf,0,0)
   for j=0,used-1 do
    local a=lut[round(((start+(j+.5)*dir)/L+.5-offset)*LUT)]
    if a and a>0 then
     local A=round(a*255)
     if rowsMode then for r=0,BLOCK-1 do writeu32(buf,(r*n+j)*4,overPixel(vr,vg,vb,A,j,r)) end else for r=0,BLOCK-1 do writeu32(buf,(j*BLOCK+r)*4,overPixel(vr,vg,vb,A,r,j)) end end
    end
   end
   if rowsMode then strip.rows:WritePixelsBuffer(Vector2.zero,Vector2.new(n,BLOCK),buf) else strip.cols:WritePixelsBuffer(Vector2.zero,Vector2.new(BLOCK,n),buf) end
   strip.rowsMode,strip.c,strip.s,strip.start,strip.used=rowsMode,c,s,start,used
   -- origin-free: compose adds its own (ox,oy), so two composes for different
   -- targets (one may be suspended mid-way) never misplace each other's veins
   strip.ccx,strip.ccy=frame.Position.X.Scale*A.w,frame.Position.Y.Scale*A.h
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
       local xs=round(ox+strip.ccx+(strip.start-(yb+BLOCK/2-oy-strip.ccy)*strip.s)/strip.c)
       if xs<rx1 and xs+strip.used>rx0 then image:DrawImage(Vector2.new(xs-tx,yb-ty),strip.rows,OVER) end
      end
     else
      for xb=rx0,rx1-1,BLOCK do
       local ys=round(oy+strip.ccy+(strip.start-(xb+BLOCK/2-ox-strip.ccx)*strip.c)/strip.s)
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
 -- A small region composed fresh on demand (sub-pixel smooth lava), for liquid
 -- that must flow at full frame rate: the notification card while it is up and
 -- disclosures while they move. The sheet only refreshes SHEET_RATE times a
 -- second, which read as a ~10 fps marble on anything that sits still. Each
 -- caller keeps its own target; it grows in 32 px steps and is never shrunk.
 -- (px,py): the panel's top-left in the caller's image; (x0,y0,w,h): the area
 -- needed, in the same space. Returns pixels, origin and size like sheetAt.
 local regions={}
 function m.regionAt(key,px,py,x0,y0,w,h)
  if not assets then return nil end
  x0,y0=floor(x0),floor(y0)
  w,h=max(1,ceil(w)),max(1,ceil(h))
  local r=regions[key]
  if not r or r.w<w or r.h<h then
   if r then destroyTiles(r.tiles) end
   local cw,ch=ceil(w/32)*32,ceil(h/32)*32
   r={w=cw,h=ch,tiles=tiled(cw,ch,128),pixels=buffer.create(cw*ch*4)}
   regions[key]=r
  end
  -- whole-pixel lava like the sheet: the smooth (resampled) path rounds down
  -- once more per blend and read ~3 levels darker than the panel
  compose(r.tiles,px-x0,py-y0,0,0,r.w,h,r.pixels,r.w,true,false,false)
  return r.pixels,x0,y0,r.w,h
 end
 function m.releaseRegion(key)
  local r=regions[key]
  if r then destroyTiles(r.tiles);regions[key]=nil end
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
  -- The lava texture is magnified ~5x on screen, so its texels showed as grain
  -- and steps. Build a smooth 3x copy once (cubic B-spline, separable, wrapping
  -- the seamless tile), in the background, then switch the panel and the liquid
  -- to it. B-spline rather than Catmull-Rom: Catmull-Rom passes through every
  -- source texel and overshoots, so the tile's speckle survived as dotted halos
  -- along the strands; the B-spline is C2-smooth with no ringing.
  if not texture then return end
  local ok2,err2=pcall(function()
   local F=3
   local src=texture.Size.X;local tile=src//2           -- stored 2x2
   local px=texture:ReadPixelsBuffer(Vector2.zero,texture.Size)
   local function ch(x,y,c) return buffer.readu8(px,((y%tile)*src+(x%tile))*4+c) end
   local function weights(t)
    local u=1-t
    local t2,t3=t*t,t*t*t
    return u*u*u/6, (3*t3-6*t2+4)/6, (-3*t3+3*t2+3*t+1)/6, t3/6
   end
   local H=tile*F
   -- horizontal pass: tile x tile -> H x tile (float channels)
   local mid=table.create(H*tile*4,0)
   local slice=os.clock()
   for y=0,tile-1 do
    for X=0,H-1 do
     local sx=(X+.5)/F-.5;local x0=math.floor(sx);local w0,w1,w2,w3=weights(sx-x0)
     for c=0,3 do
      mid[(y*H+X)*4+c+1]=ch(x0-1,y,c)*w0+ch(x0,y,c)*w1+ch(x0+1,y,c)*w2+ch(x0+2,y,c)*w3
     end
    end
    if os.clock()-slice>.003 then task.wait();slice=os.clock() end
   end
   -- vertical pass into the 2x2 stored hi-res texture
   local out=buffer.create(2*H*2*H*4)
   local function m4(X,y,c) return mid[((y%tile)*H+X)*4+c+1] end
   for Y=0,H-1 do
    local sy=(Y+.5)/F-.5;local y0=math.floor(sy);local w0,w1,w2,w3=weights(sy-y0)
    for X=0,H-1 do
     local v={}
     for c=0,3 do
      local s=m4(X,y0-1,c)*w0+m4(X,y0,c)*w1+m4(X,y0+1,c)*w2+m4(X,y0+2,c)*w3
      v[c]=s<0 and 0 or (s>255 and 255 or math.floor(s+.5))
     end
     local p=v[0]+v[1]*256+v[2]*65536+v[3]*16777216
     for oy=0,1 do for ox=0,1 do buffer.writeu32(out,(((Y+oy*H)*2*H)+X+ox*H)*4,p) end end
    end
    if os.clock()-slice>.003 then task.wait();slice=os.clock() end
   end
   if stopped then return end
   local hi=AS:CreateEditableImage({Size=Vector2.new(2*H,2*H)})
   hi:WritePixelsBuffer(Vector2.zero,Vector2.new(2*H,2*H),out)
   -- switch: texture units scale by F everywhere the lava is addressed
   local old=texture;texture=hi
   Lava.texScale=F
   for _,layer in ipairs(lavaLayers) do
    local l=layer.label
    l.ImageContent=Content.fromObject(hi)
    l.ImageRectSize=l.ImageRectSize*F
   end
   local stale=assets;assets=nil
   if stale then task.delay(1,release,stale) end
   m.invalidateSheet()
   task.delay(1,function() old:Destroy() end)
  end)
  if not ok2 then warn('[LiquidMaterial] smooth lava unavailable',err2) end
 end)
 function m.destroy()
  for key in pairs(regions) do m.releaseRegion(key) end
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
-- rim tables from the window's own (rimBase, extra=0) to the bubble's 1 px wider
-- one (extra=1): the minimize morph walks them with its progress, so the panel turns
-- into liquid with exactly the window's border and widens only as it becomes the bubble
local rimByProgress={}
for step=0,8 do local extra=step/8;local t={};for i=0,2048 do t[i]=math.exp(-math.max(0,i/32-extra)*.8) end;rimByProgress[step]=t end
rimByProgress[0]=rimBase;rimByProgress[8]=rimWide
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
  Resize.contourOut=contourOut
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
  flow.rim=rimByProgress[math.clamp(math.round(T*8),0,8)]
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
   pacing.task=coroutine.create(render);pacing.args={pts,drops};pacing.work=0;pacing.rim=flow.rim
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
  pacing.task=coroutine.create(render);pacing.args={pts,drops};pacing.work=0;pacing.rim=flow.rim
 else
  local started=os.clock();local savedRim=rimLookup;rimLookup=flow.rim or rimWide;render(pts,drops);rimLookup=savedRim;local ms=(os.clock()-started)*1000
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
 local savedRim=rimLookup;rimLookup=pacing.rim or rimWide
 if pacing.args then local args=pacing.args;pacing.args=nil;ok,err=coroutine.resume(task,args[1],args[2]) else ok,err=coroutine.resume(task) end
 rimLookup=savedRim
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
         -- 'tint' bakes the rim colour into the pixels (label stays white), so a
         -- surface can switch between liquid and rim pictures without a colour flash
         write(pixels,off,(rimMode=='tint' and RIM_R+RIM_G*256+RIM_B*65536 or 16777215)+floor(alpha*shine*255+.5)*16777216)
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

-- Disclosures (dropdown lists, picker bodies, sections) share the panel-piece
-- renderer and its paced job queue. While moving, a neck grows into a hanging
-- drop that spreads into the rounded card; once a persistent card is open its
-- rim is baked once and nothing renders again until it resizes or retints.
function Resize.createDisclosure(host,inset,zIndex,persistent)
 local label=create('ImageLabel',{Name='LiquidDisclosure',BackgroundTransparency=1,Visible=false,ZIndex=zIndex,Parent=host})
 passThrough(label)
 local data={p=0,top=0,height=0,surface=nil,ready=-1,dead=false,rimKey=nil,drawn=nil,
  vel=0,lastP=0,lastT=os.clock(),cost=1/60,shownLen=nil,pending=nil,w=0,h=0,scale=1}
 local PAD=24
 local function ease(t) t=clamp(t,0,1);return t*t*(3-2*t) end
 local job={name='disclosure',interval=0,elapsed=1}
 local function hostShown()
  if data.dead or not host.Parent or Resize.animating or Resize.minimized then return false end
  local ancestor=host
  while ancestor and ancestor~=screenGui do
   if ancestor:IsA('GuiObject') and not ancestor.Visible then return false end
   ancestor=ancestor.Parent
  end
  return true
 end
 local function geometry()
  local scale=root.AbsoluteSize.X/math.max(1,root.Size.X.Offset)
  local width=max(8,host.AbsoluteSize.X-inset*2*scale)
  local height=min(900,data.height*scale)
  return scale,width,height
 end
 local function lengthAt(p,height) local o=Resize.contourOut or 0;return max(2,max(2,height-2*o)*ease(p/.65)) end
 local function rimKeyNow()
  local scale,width,height=geometry()
  return string.format('%d|%d|%.3f|%d|%d|%d',floor(width+.5),floor(height+.5),scale,RIM_R,RIM_G,RIM_B)
 end
 local function mode()
  if data.dead or data.p<=0 or data.height<=0 then return nil end
  if data.p<1 then return 'liquid' end
  return persistent and 'rim' or nil
 end
 -- Place the label. Between liquid pictures the last one is stretched along
 -- the drop's length on the GPU (anchored at the top, where it hangs from), so
 -- the growth moves at the game's frame rate while the shape detail updates as
 -- fast as the CPU allows.
 local function place()
  local scale=data.scale;local w,h=data.w,data.h
  local f=1
  if data.drawn=='liquid' and data.shownLen then
   local _,_,height=geometry()
   f=clamp(lengthAt(data.p,height)/data.shownLen,.8,1.25)
  end
  label.Position=UDim2.fromOffset(inset-PAD/scale,data.top-PAD*f/scale)
  label.Size=UDim2.fromOffset(w/scale,h*f/scale)
 end
 job.active=function()
  local m=mode()
  if not m then
   if label.Visible then label.Visible=false end
   data.ready=-1;data.drawn=nil;data.rimKey=nil;data.pending=nil;data.shownLen=nil
   return false
  end
  if data.ready>0 then data.ready-=1 end
  -- a finished picture's pixels reach the screen one frame after they are
  -- written: switch the stretch reference in that same frame
  if data.pending then
   local pend=data.pending;data.pending=nil
   data.shownLen=pend.len;data.drawn=pend.mode;data.w,data.h,data.scale=pend.w,pend.h,pend.scale
  end
  label.Visible=data.surface~=nil and data.ready==0 and data.drawn~=nil
  if data.drawn then place() end
  if not persistent then label.ImageTransparency=ease((data.p-.78)/.22) end
  if not hostShown() then return false end
  if m=='liquid' then return true end
  return data.rimKey~=rimKeyNow()
 end
 job.run=function()
  local m=mode();if not m then return end
  local started=os.clock()
  local scale,width,height=geometry()
  local w,h=ceil((width+PAD*2)/2)*2,ceil((height+PAD*2)/2)*2
  if not data.surface or data.surface.OW~=w or data.surface.OH~=h then
   if data.surface then data.surface.image:Destroy() end
   data.surface=newSurface(w,h);data.ready=-1;data.drawn=nil;data.shownLen=nil
   label.ImageContent=Content.fromObject(data.surface.image)
   data.w,data.h,data.scale=w,h,scale
  end
  -- draw for the moment the picture will be on screen: one render plus the
  -- one-frame upload lag ahead along the current motion
  local p=1
  if m=='liquid' then
   local lead=data.cost+1/60
   p=clamp(data.p+data.vel*lead,0,1)
   if data.vel>0 then p=min(p,.999) end
  end
  local o=Resize.contourOut or 0
  local cw=max(4,width-2*o)
  local length=lengthAt(p,height)
  local spread=ease((p-.23)/.55)
  -- while it is still a drip the neck reaches up across the gap and hangs from
  -- the button; it lets go as the drop spreads into the card
  local lift=(data.gap or 0)*scale*(1-spread)
  local radius=min(max(1,12*scale-o),length/2,cw/2)
  local bulb=min(cw*.15,max(3,length*.28))
  local neck=min(cw*.045,max(1,length*.1))
  -- sample heights: a few along the neck in the gap, dense around the rounded
  -- corners (so the flat top and bottom stay flat), even in between
  local ys={}
  if lift>.5 then for i=0,3 do ys[#ys+1]=-lift+lift*i/4 end end
  local CORNER,MIDDLE=8,24
  for i=0,CORNER-1 do ys[#ys+1]=radius*(1-math.cos(i/CORNER*pi/2)) end
  for i=0,MIDDLE do ys[#ys+1]=radius+(length-2*radius)*i/MIDDLE end
  for i=1,CORNER do ys[#ys+1]=length-radius+radius*math.sin(i/CORNER*pi/2) end
  local points={};local left,right={},{}
  for index,y in ipairs(ys) do
   local i=40*clamp(y/max(1,length),0,1)
   local edge=max(0,radius-y,y-(length-radius))
   if y<0 then edge=0 end
   local rect=cw/2-radius+sqrt(max(0,radius*radius-edge*edge))
   local dy=y-(length-bulb)
   local drop=sqrt(max(0,bulb*bulb-dy*dy))
   if y<length-bulb then drop=max(neck,drop) end
   local half=if y<0 then neck else drop+(rect-drop)*spread
   local sway=sin(p*pi)*sin(i/40*pi)*cw*.025*(1-spread)
   left[#left+1]={PAD+width/2+sway-half,PAD+o+y}
   right[#right+1]={PAD+width/2+sway+half,PAD+o+y}
  end
  for _,point in ipairs(left) do points[#points+1]=point end
  for i=#right,1,-1 do points[#points+1]=right[i] end
  -- Rim-only pictures, moving or not: the liquid's inside is transparent, so
  -- the panel's own marble shows through it live (a CPU copy of the marble
  -- never matched the GPU panel exactly and only refreshed a few times a
  -- second). Rim-only shading also skips all interior work, so pictures are
  -- far cheaper and come several times more often.
  use(data.surface);clearRow=nil;postProcess=nil
  rimMode='tint';material.compose=nil
  local ok=pcall(render,points,{})
  rimMode=false
  if not ok then return end
  data.rimKey=if m=='rim' then rimKeyNow() else nil
  data.cost=data.cost*.6+(os.clock()-started)*.4
  data.pending={mode=m,len=length,w=w,h=h,scale=scale}
  if data.ready<0 then data.ready=2 end
 end
 -- called when the job goes idle (or its render was cut short): a baked rim
 -- stays on screen; anything else is dropped. A cut-short rim render must not
 -- leave the shared renderer in rim mode.
 job.reset=function()
  rimMode=false
  if mode()=='rim' and data.drawn=='rim' and data.rimKey then return end
  label.Visible=false;data.ready=-1;data.drawn=nil;data.rimKey=nil;data.pending=nil;data.shownLen=nil
 end
 jobs[#jobs+1]=job
 track(host.Destroying:Connect(function()
  data.dead=true;label.Visible=false
  if data.surface then data.surface.image:Destroy();data.surface=nil end
 end))
 return function(p,top,height,gap)
  data.gap=gap
  local now=os.clock()
  if math.abs(top-data.top)>.01 then data.rimKey=nil end
  local dt=now-data.lastT
  if dt>.001 then
   local v=(p-data.lastP)/dt
   if p<=0 or p>=1 then v=0 end
   data.vel=data.vel*.5+v*.5;data.lastP=p;data.lastT=now
  end
  data.p=p;data.top=top;data.height=height
  if data.drawn then place() end
 end
end

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
 -- A droplet picture is reused from the pool. Its new pixels reach the screen a
 -- frame after they're written, so showing it at once flashed the previous
 -- droplet (another spot, even another side) for one frame. It becomes visible
 -- on its next update instead, when the new picture is already up.
 local function showItem(item,ox,oy)
  item.label.Position=UDim2.fromOffset(ox/k,oy/k)
  if item.label.Visible then return end
  if item.armed then item.armed=nil;item.label.Visible=true else item.armed=true end
 end
 local function hideItem(item) item.label.Visible=false;item.armed=nil end
 local function clearAll()
  for _,d in ipairs(drops) do hideItem(d.slot);pool[#pool+1]=d.slot end
  table.clear(drops)
   if drip then hideItem(drip.slot);pool[#pool+1]=drip.slot;drip=nil end
   for _,f in ipairs(falling) do hideItem(f.slot);pool[#pool+1]=f.slot end;table.clear(falling)
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
    showItem(item,ox,oy)
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
  showItem(item,ox,oy)
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
    if t>=d.bud+d.float+d.back then hideItem(d.slot);pool[#pool+1]=d.slot;table.remove(drops,i) else
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
     -- The window is anchored to the edge point, pushed out along the edge normal by a
     -- fixed amount: it slides along the edge but never moves toward or away from it.
     -- (Following the droplet, the snapped origin stepped 2 px across the edge, and for
     -- the one frame where the label had moved but its new picture wasn't up yet, the
     -- window's slice of the panel edge showed 2 px off: a slab or a bite in the border.)
     local reach=WINDOW/2-50
     local ox,oy=floor((ex+nx*reach-WINDOW/2)/S)*S,floor((ey+ny*reach-WINDOW/2)/S)*S
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
     showItem(item,ox,oy)
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
       local qx,qy=ox+x+.5,oy+y+.5
       local sdp=sdRR(qx,qy,0,0,w,h,r)
       local ps
       if sdp<=0 then
        -- inside the window: the window's own rim, from its own outline (distance and
        -- normal), so these pixels match the real window exactly; the drops add nothing
        local nx=sdRR(qx+.5,qy,0,0,w,h,r)-sdRR(qx-.5,qy,0,0,w,h,r)
        local ny=sdRR(qx,qy+.5,0,0,w,h,r)-sdRR(qx,qy-.5,0,0,w,h,r)
        local nl=sqrt(nx*nx+ny*ny)+1e-6
        local light=(-nx*.6-ny*.8)/nl;if light<0 then light=0 elseif light>1 then light=1 end
        local key=floor(-sdp*16);if key>1024 then key=1024 end
        ps=RIM_NEAR[key]*(.18+.82*light)+RIM_BROAD[key]*light
       else
        -- just outside: the merged outline, so the window's edge bends into the stream
        local light=(gx*.6+gy*.8)/gl;if light<0 then light=0 elseif light>1 then light=1 end
        local dd=dist>0 and dist or 0
        local key=floor(dd*16);if key>1024 then key=1024 end
        ps=RIM_NEAR[key]*(.18+.82*light)+RIM_BROAD[key]*light
       end
       if ps>shine then shine=ps>1 and 1 or ps end
      end
     end
     -- on the card side the card's own outline bounds the liquid: blobs never bulge past it
     local px=ox+x+.5
     if dir*(px-ex)>g.gap+.5 then
      local mid=ex+dir*(g.gap+g.cw/2)
      local sc
      if dir*(px-ex)<g.gap+g.rad then
       -- the corners on the window side: where the stream joins, only the card's
       -- top/bottom lines bound it (its rounded corners would carve a notch into it)
       sc=math.abs(oy+y+.5-g.cy)-g.ch/2
      else
       sc=sdRR(px,oy+y+.5,mid-g.cw/2,g.cy-g.ch/2,mid+g.cw/2,g.cy+g.ch/2,g.rad)
      end
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
  local mat,mx,my,mw,mh=shared.material.regionAt('toast',-ox,-oy,live.x0,live.y0,live.w,live.h)
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
  local cb=m and m.onDone;m=nil
  if label then label.Visible=false end
  if image then image:WritePixelsBuffer(Vector2.zero,Vector2.new(W_,H_),buffer.create(W_*H_*4)) end
  liveShow(false);if cb then cb() end
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
    if original:IsA('ImageLabel') then
     -- the lava switches to its smooth hi-res copy once built: follow it
     if (Lava.texScale or 1)>1 and not copy:GetAttribute('HiRes') then copy:SetAttribute('HiRes',true);copy.ImageContent=original.ImageContent end
     copy.ImageRectOffset=original.ImageRectOffset;copy.ImageRectSize=original.ImageRectSize;copy.ImageTransparency=original.ImageTransparency
    end
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
        ) * (Lava.texScale or 1)
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

