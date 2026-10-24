-- ============================================================================
-- SWARM UNIT CORE - FAST GEO-MINER (v6.0 Zero-Extraction on Startup)
-- Supported: CC:Tweaked + Advanced Peripherals + Create + Sophisticated
-- ============================================================================

local STATE_FILE = "state.json"
local SWARM_CHANNEL = 101

local CONFIG = {
    MAX_HORIZONTAL_RADIUS = 32,
    SAFE_OFFSET_Y = -5,
    MIN_FREE_SLOTS = 4,
    STUCK_TIMEOUT_SEC = 25,
    SCAN_RADIUS = 8,
    TARGET_FUEL = 2500,
    MIN_FUEL = 400,
    DROP_TRASH = true,
}

local BASE_TERRAIN_TRASH = {
    ["minecraft:air"] = true, ["minecraft:cave_air"] = true, ["minecraft:void_air"] = true,
    ["minecraft:water"] = true, ["minecraft:flowing_water"] = true,
    ["minecraft:lava"] = true, ["minecraft:flowing_lava"] = true,
    ["minecraft:bedrock"] = true, ["minecraft:stone"] = true,
    ["minecraft:cobblestone"] = true, ["minecraft:smooth_stone"] = true,
    ["minecraft:deepslate"] = true, ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:reinforced_deepslate"] = true, ["minecraft:dirt"] = true,
    ["minecraft:grass_block"] = true, ["minecraft:gravel"] = true,
    ["minecraft:sand"] = true, ["minecraft:red_sand"] = true,
    ["minecraft:andesite"] = true, ["minecraft:diorite"] = true,
    ["minecraft:granite"] = true, ["minecraft:tuff"] = true,
    ["minecraft:calcite"] = true, ["minecraft:netherrack"] = true,
    ["minecraft:basalt"] = true, ["minecraft:blackstone"] = true,
}

local DX = { [0] = 0,  [1] = 1,  [2] = 0,  [3] = -1 }
local DZ = { [0] = -1, [1] = 0,  [2] = 1,  [3] = 0 }

local Pos = { x = 0, y = 0, z = 0, facing = 0, chestPos = nil, mineFacing = 0 }

local State = {}
local Equip = {}
local Mesh = {}
local Nav = {}
local Base = {}
local Miner = { minedHistory = {} }
local scanner = nil

function State.save()
    local file = fs.open(STATE_FILE, "w")
    if file then
        local data = {
            x = Pos.x, y = Pos.y, z = Pos.z,
            facing = Pos.facing, mineFacing = Pos.mineFacing or 0,
            chestPos = Pos.chestPos
        }
        file.write(textutils.serializeJSON(data))
        file.close()
    end
end

function State.load()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        if file then
            local raw = file.readAll()
            file.close()
            local data = textutils.unserializeJSON(raw)
            if data and type(data) == "table" and data.x and data.y and data.z and data.facing then
                Pos.x = data.x; Pos.y = data.y; Pos.z = data.z; Pos.facing = data.facing
                Pos.mineFacing = data.mineFacing or 0; Pos.chestPos = data.chestPos
                return true
            end
        end
    end
    return false
end

local function findItemSlot(pattern)
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and item.name:lower():find(pattern) then return slot end
    end
    return nil
end

local function getFreeSlotCount()
    local free = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then free = free + 1 end
    end
    return free
end

-- ============================================================================
-- 1. ЭКИПИРОВКА (ТОЛЬКО НАДЕТЬ ТО, ЧТО УЖЕ ЕСТЬ В РУКАХ/КАРМАНАХ)
-- ============================================================================
function Equip.findScanner()
    for _, side in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(side)
        if pType and (pType:lower():find("geo") or pType:lower():find("scan")) then
            scanner = peripheral.wrap(side)
            return true
        end
    end
    return false
end

function Equip.enforceTools()
    local pickSlot = findItemSlot("pickaxe")
    if pickSlot then turtle.select(pickSlot); turtle.equipRight() end

    if not Equip.findScanner() then
        local scanSlot = findItemSlot("geo") or findItemSlot("scan")
        if scanSlot then
            turtle.select(scanSlot); turtle.equipLeft(); sleep(0.1); Equip.findScanner()
        end
    end
end

-- ============================================================================
-- 2. РОЕВАЯ MESH-СВЯЗЬ
-- ============================================================================
Mesh = {
    lastSyncTime = 0,
    recalledByBase = false,
    homingOrder = false,
}

function Mesh.equipModem()
    local slot = findItemSlot("modem")
    if slot then
        turtle.select(slot); turtle.equipLeft(); sleep(0.2); return true
    end
    return false
end

function Mesh.equipScanner()
    local slot = findItemSlot("geo") or findItemSlot("scan")
    if slot then
        turtle.select(slot); turtle.equipLeft(); sleep(0.2); Equip.findScanner(); return true
    end
    return false
end

function Mesh.sync(currentState)
    if not findItemSlot("modem") and not peripheral.find("modem") then return end

    local now = os.epoch("utc")
    if (now - Mesh.lastSyncTime) < 10000 then return end
    Mesh.lastSyncTime = now

    if not Mesh.equipModem() then return end

    local modem = peripheral.wrap("left")
    if modem and modem.open then
        modem.open(SWARM_CHANNEL)
        local myId = os.getComputerID()
        local dist = math.floor(math.sqrt(Pos.x^2 + Pos.y^2 + Pos.z^2))

        local telemetryPacket = {
            type = "TELEMETRY", origin = myId,
            x = Pos.x, y = Pos.y, z = Pos.z, dist = dist,
            fuel = turtle.getFuelLevel(), freeSlots = getFreeSlotCount(),
            state = currentState or "MINING"
        }
        modem.transmit(SWARM_CHANNEL, SWARM_CHANNEL, telemetryPacket)

        local timer = os.startTimer(0.4)
        while true do
            local event, p1, p2, p3, msg = os.pullEvent()
            if event == "modem_message" and type(msg) == "table" then
                if msg.type == "ORDER" and (msg.target == myId or msg.target == "ALL") then
                    if msg.cmd == "RECALL" then
                        Mesh.recalledByBase = true; Mesh.homingOrder = false
                    elseif msg.cmd == "HOMING" then
                        Mesh.homingOrder = true; Mesh.recalledByBase = false
                    elseif msg.cmd == "RESUME" then
                        Mesh.recalledByBase = false; Mesh.homingOrder = false
                    end

                    if msg.config and type(msg.config) == "table" then
                        for k, v in pairs(msg.config) do CONFIG[k] = v end
                    end
                end
            elseif event == "timer" and p1 == timer then
                break
            end
        end
        modem.close(SWARM_CHANNEL)
    end

    Mesh.equipScanner()
    Equip.enforceTools()
end

-- ============================================================================
-- 3. НАВИГАЦИЯ
-- ============================================================================
function Nav.turnRight()
    turtle.turnRight(); Pos.facing = (Pos.facing + 1) % 4; State.save()
end

function Nav.turnLeft()
    turtle.turnLeft(); Pos.facing = (Pos.facing + 3) % 4; State.save()
end

function Nav.setFacing(targetFacing)
    local diff = (targetFacing - Pos.facing) % 4
    if diff == 1 then Nav.turnRight()
    elseif diff == 2 then Nav.turnRight(); Nav.turnRight()
    elseif diff == 3 then Nav.turnLeft() end
end

local function isInsideHorizontalLimit(x, z)
    return math.abs(x) <= CONFIG.MAX_HORIZONTAL_RADIUS and math.abs(z) <= CONFIG.MAX_HORIZONTAL_RADIUS
end

local function isAnyStorageBlock(inspectFn)
    local ok, data = inspectFn()
    if ok and data.name then
        local n = data.name:lower()
        if n:find("vault") or n:find("barrel") or n:find("chest") or n:find("storage") or 
           n:find("shulker") or n:find("drawer") or n:find("backpack") or n:find("crate") or 
           n:find("toolbox") or n:find("bin") or n:find("cache") then
            return true, data.name
        end
    end
    return false, nil
end

local function isFriendTurtle(inspectFn)
    local ok, data = inspectFn()
    if ok and data.name and (data.name:find("turtle") or data.name:find("computercraft")) then
        return true, data.name
    end
    return false, nil
end

function Nav.bypassObstacle()
    if Pos.y > (CONFIG.SAFE_OFFSET_Y - 50) and not isAnyStorageBlock(turtle.inspectDown) then
        local ok, bd = turtle.inspectDown()
        if not ok or bd.name ~= "minecraft:bedrock" then
            if Nav.down() then
                local s1 = Nav.forward(); local s2 = Nav.forward(); Nav.up()
                if s1 or s2 then return true end
            end
        end
    end

    Nav.turnRight(); local side = Nav.forward(); Nav.turnLeft()
    if side then
        Nav.forward(); Nav.forward(); Nav.turnLeft(); Nav.forward(); Nav.turnRight()
        return true
    end
    return false
end

function Nav.forward()
    local tx, tz = Pos.x + DX[Pos.facing], Pos.z + DZ[Pos.facing]
    if not isInsideHorizontalLimit(tx, tz) then return false end
    if isAnyStorageBlock(turtle.inspect) then return false end

    local startTime = os.epoch("utc")
    while not turtle.forward() do
        if (os.epoch("utc") - startTime) > (CONFIG.STUCK_TIMEOUT_SEC * 1000) then return false end
        if turtle.getFuelLevel() == 0 then error("[Fatal] OUT OF FUEL!") end
        if isAnyStorageBlock(turtle.inspect) then return false end

        if isFriendTurtle(turtle.inspect) then
            sleep(0.5)
            if isFriendTurtle(turtle.inspect) then
                if Nav.bypassObstacle() then return true end
            end
        elseif turtle.detect() then
            turtle.dig(); sleep(0.1)
        elseif turtle.attack() then sleep(0.2)
        else sleep(0.1) end
    end
    Pos.x, Pos.z = tx, tz; State.save()
    return true
end

function Nav.back()
    local tx, tz = Pos.x - DX[Pos.facing], Pos.z - DZ[Pos.facing]
    if not isInsideHorizontalLimit(tx, tz) then return false end

    if turtle.back() then
        Pos.x, Pos.z = tx, tz; State.save(); return true
    else
        Nav.turnRight(); Nav.turnRight()
        local m = Nav.forward()
        Nav.turnRight(); Nav.turnRight()
        return m
    end
end

function Nav.up()
    if isAnyStorageBlock(turtle.inspectUp) then return false end

    local startTime = os.epoch("utc")
    while not turtle.up() do
        if (os.epoch("utc") - startTime) > (CONFIG.STUCK_TIMEOUT_SEC * 1000) then return false end
        if turtle.getFuelLevel() == 0 then error("[Fatal] OUT OF FUEL!") end
        if isAnyStorageBlock(turtle.inspectUp) then return false end

        if isFriendTurtle(turtle.inspectUp) then sleep(math.random(5, 15) / 10)
        elseif turtle.detectUp() then turtle.digUp(); sleep(0.1)
        elseif turtle.attackUp() then sleep(0.2)
        else sleep(0.1) end
    end
    Pos.y = Pos.y + 1; State.save()
    return true
end

function Nav.down()
    local ok, b = turtle.inspectDown()
    if ok and b.name == "minecraft:bedrock" then return false end
    if isAnyStorageBlock(turtle.inspectDown) then return false end

    local startTime = os.epoch("utc")
    while not turtle.down() do
        if (os.epoch("utc") - startTime) > (CONFIG.STUCK_TIMEOUT_SEC * 1000) then return false end
        if turtle.getFuelLevel() == 0 then error("[Fatal] OUT OF FUEL!") end
        if isAnyStorageBlock(turtle.inspectDown) then return false end

        if isFriendTurtle(turtle.inspectDown) then sleep(math.random(5, 15) / 10)
        elseif turtle.detectDown() then
            local s, bd = turtle.inspectDown()
            if s and bd.name == "minecraft:bedrock" then return false end
            turtle.digDown(); sleep(0.1)
        elseif turtle.attackDown() then sleep(0.2)
        else sleep(0.1) end
    end
    Pos.y = Pos.y - 1; State.save()
    return true
end

function Nav.goTo(tx, ty, tz)
    while Pos.y < ty do if not Nav.up() then return false end end
    while Pos.y > ty do if not Nav.down() then return false end end

    if Pos.x < tx then
        Nav.setFacing(1)
        while Pos.x < tx do if not Nav.forward() then return false end end
    elseif Pos.x > tx then
        Nav.setFacing(3)
        while Pos.x > tx do if not Nav.forward() then return false end end
    end

    if Pos.z < tz then
        Nav.setFacing(2)
        while Pos.z < tz do if not Nav.forward() then return false end end
    elseif Pos.z > tz then
        Nav.setFacing(0)
        while Pos.z > tz do if not Nav.forward() then return false end end
    end
    return true
end

-- ============================================================================
-- 4. БАЗА, CREATE VAULT И ВЫГРУЗКА
-- ============================================================================
local FUEL_ITEMS = {
    ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80,
    ["minecraft:coal_block"] = 800, ["minecraft:lava_bucket"] = 1000,
    ["minecraft:blaze_rod"] = 120,
}

function Base.isRealInventory(side)
    local pSide = (side == "down" and "bottom") or (side == "up" and "top") or "front"
    local p = peripheral.wrap(pSide)
    if p and (p.list or p.size or p.getItemDetail) then return true end

    local inspectFn = (side == "down" and turtle.inspectDown) or (side == "up" and turtle.inspectUp) or turtle.inspect
    local ok, data = inspectFn()
    if ok and data.name then
        local n = data.name:lower()
        if n:find("vault") or n:find("barrel") or n:find("chest") or n:find("storage") or 
           n:find("shulker") or n:find("drawer") or n:find("backpack") or n:find("crate") or 
           n:find("toolbox") or n:find("interface") or n:find("bin") or n:find("cache") then
            return true
        end
    end
    return false
end

function Base.findChest()
    for dir = 0, 3 do
        Nav.setFacing(dir)
        if Base.isRealInventory("front") then
            Pos.chestPos = { x = Pos.x + DX[dir], y = Pos.y, z = Pos.z + DZ[dir], side = "front", pSide = "front", facing = dir }
            Pos.mineFacing = (dir + 2) % 4; State.save(); return true
        end
    end

    if Base.isRealInventory("down") then
        Pos.chestPos = { x = Pos.x, y = Pos.y - 1, z = Pos.z, side = "down", pSide = "bottom" }
        Pos.mineFacing = Pos.facing; State.save(); return true
    end

    if Base.isRealInventory("up") then
        Pos.chestPos = { x = Pos.x, y = Pos.y + 1, z = Pos.z, side = "up", pSide = "top" }
        Pos.mineFacing = Pos.facing; State.save(); return true
    end
    return false
end

local function rawDrop()
    if Pos.chestPos and Pos.chestPos.side == "down" then return turtle.dropDown()
    elseif Pos.chestPos and Pos.chestPos.side == "up" then return turtle.dropUp()
    else return turtle.drop() end
end

function Base.refuelFromInventory()
    local modemSlot = findItemSlot("modem")
    for slot = 1, 16 do
        if slot ~= modemSlot then
            turtle.select(slot)
            if turtle.refuel(0) then
                while turtle.getFuelLevel() < CONFIG.TARGET_FUEL and turtle.getItemCount(slot) > 0 do
                    turtle.refuel(1)
                end
            end
        end
    end
    turtle.select(1)
end

function Base.dropTrash()
    if not CONFIG.DROP_TRASH then return end
    local modemSlot = findItemSlot("modem")
    for slot = 1, 16 do
        if slot ~= modemSlot then
            local item = turtle.getItemDetail(slot)
            if item and BASE_TERRAIN_TRASH[item.name] then
                turtle.select(slot); turtle.dropDown()
            end
        end
    end
    turtle.select(1)
end

function Base.unloadAndRefuel(reason)
    if reason then print(string.format("[Return] Returning to Create Vault: %s", reason))
    else print("[Base] Returning to base storage...") end

    while Pos.y < -1 do Nav.up() end
    while Pos.y > -1 do Nav.down() end

    Nav.goTo(0, -1, 0)
    Nav.up()

    local found = Base.findChest()
    if not found then
        print("[Storage ERROR] Create Vault not detected! Holding inventory.")
        sleep(2); return
    end

    if Pos.chestPos and Pos.chestPos.facing then Nav.setFacing(Pos.chestPos.facing) end

    print("[Base] Depositing resources into Create Vault...")
    local modemSlot = findItemSlot("modem")
    for slot = 1, 16 do
        if slot ~= modemSlot then
            local item = turtle.getItemDetail(slot)
            if item then
                local isScanner = item.name:find("geo_scanner") or item.name:find("geoscanner")
                local isTool = item.name:find("pickaxe")
                local isModem = item.name:find("modem")
                if not isScanner and not isTool and not isModem then
                    turtle.select(slot); rawDrop()
                end
            end
        end
    end

    Base.refuelFromInventory()
    Equip.enforceTools()
    print("[Base] Turn-around complete. Fuel: " .. turtle.getFuelLevel())
end

-- ============================================================================
-- 5. МГНОВЕННАЯ КАЛИБРОВКА
-- ============================================================================
function Miner.calibrateFacing()
    print("[Compass] Instant Base Calibration...")
    Base.findChest()
    if Pos.chestPos and Pos.chestPos.facing then
        Pos.facing = Pos.chestPos.facing
        Pos.mineFacing = (Pos.chestPos.facing + 2) % 4
    else
        Pos.facing = 0
        Pos.mineFacing = 2
    end
    Pos.x, Pos.y, Pos.z = 0, 0, 0
    State.save()
    print(string.format("[Compass] Calibrated! Facing: %d, Mine Heading: %d", Pos.facing, Pos.mineFacing))
end

-- ============================================================================
-- 6. ДЕТЕКТОР РУД И ГИБРИДНЫЙ ВАКУУМ
-- ============================================================================
local function isAllowedMiningLocation(x, y, z)
    local baseLevel = (Pos.chestPos and Pos.chestPos.y) or 0
    if y > (baseLevel + CONFIG.SAFE_OFFSET_Y) then return false end
    if not isInsideHorizontalLimit(x, z) then return false end
    return true
end

function Miner.isOre(block)
    if not block or not block.name then return false end
    local name = block.name:lower()
    if name:find("turtle") or name:find("computercraft") then return false end
    if BASE_TERRAIN_TRASH[name] then return false end
    if name:find("ore") or name:find("debris") or name:find("raw") or name:find("cluster") or name:find("crystal") then return true end
    local modId = name:match("^(.-):")
    if modId and modId ~= "minecraft" and modId ~= "advancedperipherals" then return true end

    if block.tags and type(block.tags) == "table" then
        for k, v in pairs(block.tags) do
            local tag = (type(v) == "string" and v) or (type(k) == "string" and k) or ""
            tag = tag:lower()
            if tag:find("ores") or tag:find("raw_materials") or tag:find("gems") then return true end
        end
    end
    return false
end

function Miner.scanOres(radius)
    Equip.enforceTools()
    local cooldown = scanner.getScanCooldown and scanner.getScanCooldown() or 0
    if cooldown > 0 then sleep(cooldown / 1000) end

    local data = scanner.scan(radius)
    if not data then return {} end

    local list = {}
    for _, block in ipairs(data) do
        local wx, wy, wz = Pos.x + block.x, Pos.y + block.y, Pos.z + block.z
        local key = wx .. "," .. wy .. "," .. wz

        if isAllowedMiningLocation(wx, wy, wz) and not Miner.minedHistory[key] and Miner.isOre(block) then
            local dist = math.abs(block.x) + math.abs(block.y) + math.abs(block.z)
            table.insert(list, { x = wx, y = wy, z = wz, name = block.name, dist = dist })
        end
    end

    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

function Miner.inspectAndMineAdjacent()
    local dugAny = false

    if isAllowedMiningLocation(Pos.x, Pos.y + 1, Pos.z) then
        local okU, bU = turtle.inspectUp()
        if okU and Miner.isOre(bU) then
            turtle.digUp(); Miner.minedHistory[Pos.x .. "," .. (Pos.y + 1) .. "," .. Pos.z] = true; dugAny = true
        end
    end

    local okD, bD = turtle.inspectDown()
    if okD and Miner.isOre(bD) then
        turtle.digDown(); Miner.minedHistory[Pos.x .. "," .. (Pos.y - 1) .. "," .. Pos.z] = true; dugAny = true
    end

    for i = 0, 3 do
        local fx, fz = Pos.x + DX[Pos.facing], Pos.z + DZ[Pos.facing]
        if isAllowedMiningLocation(fx, Pos.y, fz) then
            local okF, bF = turtle.inspect()
            if okF and Miner.isOre(bF) then
                turtle.dig(); Miner.minedHistory[fx .. "," .. Pos.y .. "," .. fz] = true; dugAny = true
            end
        end
        Nav.turnRight()
    end

    if dugAny then Base.refuelFromInventory(); Base.dropTrash() end
    return dugAny
end

function Miner.harvestVeinCluster()
    print("[Vein Engine] Vacuuming cluster with Inspect + Radar...")

    while getFreeSlotCount() > CONFIG.MIN_FREE_SLOTS do
        Mesh.sync("MINING_VEIN")
        if Mesh.recalledByBase or Mesh.homingOrder then break end

        local inspectedDug = true
        while inspectedDug do inspectedDug = Miner.inspectAndMineAdjacent() end

        local clusterOres = Miner.scanOres(CONFIG.SCAN_RADIUS)
        if #clusterOres == 0 then break end

        local nextOre = clusterOres[1]
        if not Nav.goTo(nextOre.x, nextOre.y, nextOre.z) then
            Miner.minedHistory[nextOre.x .. "," .. nextOre.y .. "," .. nextOre.z] = true
        else
            Miner.minedHistory[nextOre.x .. "," .. nextOre.y .. "," .. nextOre.z] = true
        end
    end
end

-- ============================================================================
-- 7. ГЛАВНЫЙ ЦИКЛ
-- ============================================================================
local function main()
    term.clear(); term.setCursorPos(1, 1)
    print("=== SWARM UNIT: HYBRID MESH v6.0 ===")

    local hasSavedState = State.load()
    Equip.enforceTools()
    Base.findChest()
    Base.refuelFromInventory()

    if turtle.getFuelLevel() < CONFIG.MIN_FUEL then error("[Fatal] Fuel too low!") end

    if hasSavedState and Pos.chestPos and Pos.y < 0 then
        print(string.format("[Resume] Restored Pos: (%d,%d,%d)", Pos.x, Pos.y, Pos.z))
    else
        Miner.calibrateFacing()
        print("[Docking] Undocking via sub-floor...")
        Nav.down()
        print("[Safety] Plunging into mining depth (Y <= " .. CONFIG.SAFE_OFFSET_Y .. ")...")
        while Pos.y > CONFIG.SAFE_OFFSET_Y do if not Nav.down() then break end end
    end

    local resumePos = nil

    while true do
        Equip.enforceTools()
        Mesh.sync("SEARCHING")

        -- 1. Топливо
        local distHome = math.abs(Pos.x) + math.abs(Pos.y) + math.abs(Pos.z)
        local minSafeFuel = distHome + 150

        if turtle.getFuelLevel() < minSafeFuel then
            print("[Fuel Warning] Low fuel! Emergency return.")
            resumePos = { x = Pos.x, y = Pos.y, z = Pos.z }
            Base.unloadAndRefuel("LOW_FUEL")
        end

        -- 2. Возврат в Create Vault
        local freeSlots = getFreeSlotCount()
        if Mesh.recalledByBase or freeSlots <= CONFIG.MIN_FREE_SLOTS then
            resumePos = { x = Pos.x, y = Pos.y, z = Pos.z }
            Base.unloadAndRefuel(Mesh.recalledByBase and "ORDER_RECALL" or "INVENTORY_FULL")

            while Mesh.recalledByBase and not Mesh.homingOrder do
                print("[Recall] Waiting at Create Vault for RESUME...")
                Mesh.sync("STANDBY_BASE")
                sleep(2)
            end

            Nav.down()

            if resumePos and not Mesh.homingOrder then
                print(string.format("[Resume] Returning to depth (%d,%d,%d)...", resumePos.x, resumePos.y, resumePos.z))
                if not Nav.goTo(resumePos.x, resumePos.y, resumePos.z) then
                    print("[Resume] Resuming from current depth.")
                end
                resumePos = nil
            end
        end

        -- 3. Добыча руды
        local list = Miner.scanOres(CONFIG.SCAN_RADIUS)
        if #list > 0 then
            Miner.harvestVeinCluster()
        else
            print("[Miner] Boring down...")
            local moved = 0
            for i = 1, 6 do
                if Nav.down() then moved = moved + 1 else break end
            end

            if moved == 0 then
                print("[Miner] Bedrock reached! Relocating shaft...")
                while Pos.y < CONFIG.SAFE_OFFSET_Y do Nav.up() end
                Nav.setFacing(Pos.mineFacing)
                local shifted = false
                for step = 1, 16 do
                    if Nav.forward() then shifted = true else break end
                end

                if not shifted then
                    Nav.turnRight()
                    for step = 1, 16 do if not Nav.forward() then break end end
                end
            end
        end
    end
end

local status, err = pcall(main)
if not status then
    print("[CRITICAL FAILURE] Error: " .. tostring(err))
    pcall(function()
        Base.unloadAndRefuel("CRITICAL_CRASH: " .. tostring(err):sub(1, 20))
    end)
end