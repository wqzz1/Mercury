from pathlib import Path
import hashlib
root=Path(__file__).resolve().parent
parts=root/'src'
out=(root.parent/'outputs' if root.name == 'work' else root)/'Mercury.lua'
out.parent.mkdir(parents=True,exist_ok=True)
icon_text=(parts/'icons.lua').read_text(encoding='utf-8')
chunks=[]
def add(path): chunks.append('-- source: '+path+'\n'+(parts/path).read_text(encoding='utf-8'))
for path in ['config.lua','primitives.lua'] : add(path)
prefix='''--!nocheck
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
'''
custom='''
    if typeof(options.Performance) == "string" then Layout.performance = options.Performance end
    if typeof(options.MinimizeKey) == "EnumItem" then Layout.minimizeKey = options.MinimizeKey end
    if options.MinimizedIcon ~= nil then Layout.minimizedIcon = options.MinimizedIcon end
'''
body=prefix+'\n'.join(chunks)+'\n'+custom+'\n'+icon_text
for path in ['shell.lua','tabs.lua','motion.lua','lifecycle.lua','api.lua']:
    body+='\n-- source: '+path+'\n'+(parts/path).read_text(encoding='utf-8')
body+='\nend\nreturn Mercury\n'
out.write_text(body,encoding='utf-8')
print(out, len(body), 'chars',hashlib.sha256(body.encode()).hexdigest())
