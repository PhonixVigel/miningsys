local pd = peripheral.find("player_detector")
local geo = peripheral.find("geo_scanner")
local glasses = peripheral.find("smart_glasses")

if not glasses then print("Error: Smart Glasses not found!") return end
local overlay = glasses.getModule("advancedperipherals:overlay")
if not overlay then print("Error: Overlay Module is not installed in the glasses!") return end
if overlay.setAutoUpdate then overlay.setAutoUpdate(true) end

local OFFSET_X = -1
local OFFSET_Y = 1
local OFFSET_Z = -1

local COLOR_PLAYER = 0xFF0000 

local function isOre(b)
    if b.name == "minecraft:ancient_debris" then return true end
    if type(b.name) == "string" and string.match(b.name, "_ore$") then return true end
    if type(b.tags) == "table" then
        for k, v in pairs(b.tags) do
            local tagStr = type(k) == "string" and k or v
            if type(tagStr) == "string" and string.find(tagStr, "ores") then return true end
        end
    end
    return false
end

-- ================= УЗНАВАНИЕ СЕБЯ =================
local myCachedName = ""

local function getMyName()
    if myCachedName ~= "" then return myCachedName end
    if not pd then return "" end
    
    -- 1. Ищем игрока в радиусе 2 блоков (в очках это всегда мы)
    if pd.getPlayersInRange then
        local near = pd.getPlayersInRange(2)
        if type(near) == "table" and #near > 0 then
            local first = near[1]
            if type(first) == "string" then myCachedName = first
            elseif type(first) == "table" and first.name then myCachedName = first.name end
            return myCachedName
        end
    end
    
    -- 2. Запасной вариант через getOwner
    if pd.getOwner then
        local o = pd.getOwner()
        if type(o) == "string" then myCachedName = o
        elseif type(o) == "table" and o.name then myCachedName = o.name end
        if myCachedName ~= "" then return myCachedName end
    end
    
    -- 3. Совсем на крайний случай
    local online = pd.getOnlinePlayers()
    if type(online) == "table" and #online > 0 then
        myCachedName = online[1]
    end
    
    return myCachedName
end

local function getMyInfo()
    local name = getMyName()
    if pd and name ~= "" then
        return pd.getPlayer(name)
    end
    return nil
end
-- ==================================================

overlay.clear()
print("Starting Ultimate AR Radar... (Hold Ctrl+T to exit)")

local drawnPlayers = {}
local PERSISTENT_ORES = {}

local function playerLoop()
    while true do
        if pd then
            local currentPlayers = {}
            local online = pd.getOnlinePlayers()
            local me = getMyName()
            
            if type(online) == "table" then
                for _, name in pairs(online) do
                    -- ЖЕСТКИЙ ФИЛЬТР: ЕСЛИ ИМЯ СОВПАДАЕТ С НАШИМ - ПРОПУСКАЕМ
                    if name ~= me then
                        local pInfo = pd.getPlayer(name)
                        if pInfo then currentPlayers[name] = pInfo end
                    end
                end
            end

            for name, pInfo in pairs(currentPlayers) do
                local bx = pInfo.x - 0.3
                local by = pInfo.y + 1
                local bz = pInfo.z - 0.3
                
                local obj = drawnPlayers[name]
                if obj and obj.setX then
                    obj.setX(bx)
                    obj.setY(by)
                    obj.setZ(bz)
                else
                    if obj then overlay.removeObject(obj.getId()) end
                    drawnPlayers[name] = overlay.createBox({
                        x = bx, y = by, z = bz,
                        sizeX = 0.6, sizeY = 1.8, sizeZ = 0.6,
                        color = COLOR_PLAYER, opacity = 0.5,
                        depthTest = false, relativePosition = false
                    })
                end
            end

            for name, obj in pairs(drawnPlayers) do
                if not currentPlayers[name] then
                    overlay.removeObject(obj.getId())
                    drawnPlayers[name] = nil
                end
            end
        end
        os.sleep(0.05)
    end
end

local function oreLoop()
    while true do
        if geo then
            local pInfoBefore = getMyInfo()
            local blocks, err = geo.scanBlocks(16)
            local pInfoAfter = getMyInfo()
            
            if blocks and pInfoBefore and pInfoAfter then
                local dx = math.abs(pInfoAfter.x - pInfoBefore.x)
                local dy = math.abs(pInfoAfter.y - pInfoBefore.y)
                local dz = math.abs(pInfoAfter.z - pInfoBefore.z)
                
                -- Если мы сдвинулись меньше чем на 0.4 блока - скан ИДЕАЛЕН
                if dx < 0.4 and dy < 0.4 and dz < 0.4 then
                    local now = os.epoch("utc")
                    local seenThisScan = {}
                    
                    for _, block in pairs(blocks) do
                        if isOre(block) then
                            local exactX = pInfoAfter.x + block.x + OFFSET_X
                            local exactY = pInfoAfter.y + block.y + OFFSET_Y
                            local exactZ = pInfoAfter.z + block.z + OFFSET_Z
                            
                            local estX = math.floor(exactX + 0.5)
                            local estY = math.floor(exactY + 0.5)
                            local estZ = math.floor(exactZ + 0.5)
                            
                            local exactKey = estX .. "," .. estY .. "," .. estZ
                            seenThisScan[exactKey] = true
                            
                            if PERSISTENT_ORES[exactKey] and PERSISTENT_ORES[exactKey].name == block.name then
                                PERSISTENT_ORES[exactKey].lastSeen = now
                            else
                                local obj = overlay.createBlock({
                                    x = estX + 0.5, y = estY + 0.5, z = estZ + 0.5,
                                    sizeX = 1.02, sizeY = 1.02, sizeZ = 1.02,
                                    block = block.name,
                                    opacity = 1.0,
                                    depthTest = false,
                                    relativePosition = false
                                })
                                PERSISTENT_ORES[exactKey] = {
                                    obj = obj,
                                    name = block.name,
                                    lastSeen = now
                                }
                            end
                        end
                    end
                    
                    for key, data in pairs(PERSISTENT_ORES) do
                        if not seenThisScan[key] then
                            overlay.removeObject(data.obj.getId())
                            PERSISTENT_ORES[key] = nil
                        end
                    end
                end
            end
        end
        os.sleep(0.1) 
    end
end

parallel.waitForAll(playerLoop, oreLoop)