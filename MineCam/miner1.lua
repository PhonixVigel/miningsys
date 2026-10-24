-- ============================================================================
-- SWARM UNIT CORE - FAST GEO-MINER (v2.5 Horizontal Radius Edition)
-- Supported: CC:Tweaked + Advanced Peripherals + Create + Sophisticated
-- ============================================================================

local CONFIG = {
    -- === ГЛАВНЫЕ НАСТРОЙКИ ЗОНЫ И РАБОТЫ ===
    MAX_HORIZONTAL_RADIUS = 32, -- МАКСИМАЛЬНЫЙ РАДИУС ОТХОДА ПО ГОРИЗОНТАЛИ (X/Z) ОТ СУНДУКА (в блоках)
    SAFE_OFFSET_Y = -5,         -- Копать СТРОГО на 5+ блоков ниже уровня базы/хранилища!
    ORE_LIMIT = 25,             -- Лимит руды за одну ходку
    
    -- === ПАРАМЕТРЫ СКАНИРОВАНИЯ И ТОПЛИВА ===
    SCAN_RADIUS = 8,            -- Радиус сканирования радара
    VEIN_RADIUS = 3,            -- Радиус зачистки жилы
    TARGET_FUEL = 2500,         -- Запас топлива при заправке
    MIN_FUEL = 400,             -- Минимальный уровень топлива
    DROP_TRASH = true,          -- Сбрасывать булыжник, землю и пустую породу
}

-- Черный список мусора (дефолтная пустая порода Minecraft)
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

-- 0: North (-Z), 1: East (+X), 2: South (+Z), 3: West (-X)
local DX = { [0] = 0,  [1] = 1,  [2] = 0,  [3] = -1 }
local DZ = { [0] = -1, [1] = 0,  [2] = 1,  [3] = 0 }

local Pos = { x = 0, y = 0, z = 0, facing = 0, chestPos = nil, mineFacing = 0 }
local Nav = {}

-- ============================================================================
-- 1. НАВИГАЦИЯ И ПРОВЕРКА ГРАНИЦ ЗОНЫ (HORIZONTAL BOUNDARY CHECK)
-- ============================================================================
function Nav.turnRight()
    turtle.turnRight()
    Pos.facing = (Pos.facing + 1) % 4
end

function Nav.turnLeft()
    turtle.turnLeft()
    Pos.facing = (Pos.facing + 3) % 4
end

function Nav.setFacing(targetFacing)
    local diff = (targetFacing - Pos.facing) % 4
    if diff == 1 then Nav.turnRight()
    elseif diff == 2 then Nav.turnRight(); Nav.turnRight()
    elseif diff == 3 then Nav.turnLeft() end
end

local function isChestBlock(tx, ty, tz)
    if not Pos.chestPos then return false end
    return Pos.chestPos.x == tx and Pos.chestPos.y == ty and Pos.chestPos.z == tz
end

-- Проверка: находится ли координата внутри разрешенного радиуса X/Z
local function isInsideHorizontalLimit(x, z)
    return math.abs(x) <= CONFIG.MAX_HORIZONTAL_RADIUS and math.abs(z) <= CONFIG.MAX_HORIZONTAL_RADIUS
end

local function isFriendTurtle(inspectFn)
    local ok, data = inspectFn()
    if ok and data.name and (data.name:find("turtle") or data.name:find("computercraft")) then
        return true, data.name
    end
    return false, nil
end

function Nav.forward()
    local tx, tz = Pos.x + DX[Pos.facing], Pos.z + DZ[Pos.facing]
    if isChestBlock(tx, Pos.y, tz) then return false end

    -- Блокировка выхода за пределы горизонтального радиуса
    if not isInsideHorizontalLimit(tx, tz) then
        return false
    end

    local retries = 0
    while not turtle.forward() do
        if turtle.getFuelLevel() == 0 then error("[Fatal] OUT OF FUEL!") end

        local isFriend = isFriendTurtle(turtle.inspect)
        if isFriend then
            print("[Traffic] Turtle ahead! Yielding...")
            sleep(math.random(5, 15) / 10)
            retries = retries + 1
            if retries > 3 then return false end
        elseif turtle.detect() then
            local ok, data = turtle.inspect()
            if ok and (data.name:find("chest") or data.name:find("storage") or data.name:find("vault") or data.name:find("backpack")) then
                return false
            end
            turtle.dig()
            sleep(0.1)
        elseif turtle.attack() then
            sleep(0.2)
        else
            sleep(0.1)
        end
    end
    Pos.x, Pos.z = tx, tz
    return true
end

function Nav.back()
    local tx, tz = Pos.x - DX[Pos.facing], Pos.z - DZ[Pos.facing]
    if isChestBlock(tx, Pos.y, tz) then return false end
    if not isInsideHorizontalLimit(tx, tz) then return false end

    if turtle.back() then
        Pos.x, Pos.z = tx, tz
        return true
    else
        Nav.turnRight(); Nav.turnRight()
        local m = Nav.forward()
        Nav.turnRight(); Nav.turnRight()
        return m
    end
end

function Nav.up()
    if isChestBlock(Pos.x, Pos.y + 1, Pos.z) then return false end

    local retries = 0
    while not turtle.up() do
        if turtle.getFuelLevel() == 0 then error("[Fatal] OUT OF FUEL!") end

        local isFriend = isFriendTurtle(turtle.inspectUp)
        if isFriend then
            print("[Traffic] Turtle above! Waiting...")
            sleep(math.random(5, 15) / 10)
            retries = retries + 1
            if retries > 3 then return false end
        elseif turtle.detectUp() then
            turtle.digUp()
            sleep(0.1)
        elseif turtle.attackUp() then
            sleep(0.2)
        else
            sleep(0.1)
        end
    end
    Pos.y = Pos.y + 1
    return true
end

function Nav.down()
    if isChestBlock(Pos.x, Pos.y - 1, Pos.z) then return false end
    local ok, b = turtle.inspectDown()
    if ok and b.name == "minecraft:bedrock" then return false end

    local retries = 0
    while not turtle.down() do
        if turtle.getFuelLevel() == 0 then error("[Fatal] OUT OF FUEL!") end

        local isFriend = isFriendTurtle(turtle.inspectDown)
        if isFriend then
            print("[Traffic] Turtle below! Waiting...")
            sleep(math.random(5, 15) / 10)
            retries = retries + 1
            if retries > 3 then return false end
        elseif turtle.detectDown() then
            local s, bd = turtle.inspectDown()
            if s and bd.name == "minecraft:bedrock" then return false end
            turtle.digDown()
            sleep(0.1)
        elseif turtle.attackDown() then
            sleep(0.2)
        else
            sleep(0.1)
        end
    end
    Pos.y = Pos.y - 1
    return true
end

function Nav.goTo(tx, ty, tz)
    while Pos.y < ty do Nav.up() end
    while Pos.y > ty do if not Nav.down() then break end end

    if Pos.x < tx then
        Nav.setFacing(1)
        while Pos.x < tx do if not Nav.forward() then break end end
    elseif Pos.x > tx then
        Nav.setFacing(3)
        while Pos.x > tx do if not Nav.forward() then break end end
    end

    if Pos.z < tz then
        Nav.setFacing(2)
        while Pos.z < tz do if not Nav.forward() then break end end
    elseif Pos.z > tz then
        Nav.setFacing(0)
        while Pos.z > tz do if not Nav.forward() then break end end
    end
end

-- ============================================================================
-- 2. ЭКИПИРОВКА
-- ============================================================================
local Equip = {}
local scanner = nil

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

function Equip.autoEquip()
    print("[Setup] Checking equipment...")
    if not Equip.findScanner() then
        for slot = 1, 16 do
            local item = turtle.getItemDetail(slot)
            if item and (item.name:find("geo_scanner") or item.name:find("geoscanner")) then
                turtle.select(slot); turtle.equipLeft(); sleep(0.5); break
            end
        end
    end

    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and item.name:find("pickaxe") then
            turtle.select(slot); turtle.equipRight(); sleep(0.5); break
        end
    end

    sleep(0.5)
    if not Equip.findScanner() then error("[Error] Geo Scanner not found in hand/inventory!") end
    print("[Setup] Scanner & Pickaxe ready.")
end

-- ============================================================================
-- 3. БАЗА И УНИВЕРСАЛЬНЫЕ ХРАНИЛИЩА (CREATE, SOPHISTICATED, VANILLA, ETC.)
-- ============================================================================
local Base = {}

local FUEL_ITEMS = {
    ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80,
    ["minecraft:coal_block"] = 800, ["minecraft:lava_bucket"] = 1000,
    ["minecraft:blaze_rod"] = 120,
}

function Base.isFuel(itemName)
    if not itemName then return false, 0 end
    local name = itemName:lower()
    if FUEL_ITEMS[name] then return true, FUEL_ITEMS[name] end
    if name:find("coal") or name:find("charcoal") or name:find("fuel") then return true, 80 end
    if name:find("lava") then return true, 1000 end
    return false, 0
end

function Base.isRealInventory(side)
    local pSide = (side == "down" and "bottom") or (side == "up" and "top") or "front"
    local p = peripheral.wrap(pSide)
    if p and (p.list or p.size or p.getItemDetail) then
        return true
    end

    local inspectFn = (side == "down" and turtle.inspectDown) or (side == "up" and turtle.inspectUp) or turtle.inspect
    local ok, data = inspectFn()
    if ok and data.name then
        local n = data.name:lower()
        if n:find("chest") or n:find("barrel") or n:find("storage") or n:find("shulker") or 
           n:find("drawer") or n:find("vault") or n:find("backpack") or n:find("crate") or 
           n:find("toolbox") or n:find("interface") or n:find("bin") or n:find("cache") then
            return true
        end
    end
    return false
end

function Base.findChest()
    print("[Base] Scanning perimeter for storage...")
    for dir = 0, 3 do
        Nav.setFacing(dir)
        if Base.isRealInventory("front") then
            Pos.chestPos = { x = Pos.x + DX[dir], y = Pos.y, z = Pos.z + DZ[dir], side = "front", pSide = "front", facing = dir }
            Pos.mineFacing = (dir + 2) % 4
            print(string.format("[Base] Storage locked in front (facing %d).", dir))
            return true
        end
    end

    if Base.isRealInventory("down") then
        Pos.chestPos = { x = Pos.x, y = Pos.y - 1, z = Pos.z, side = "down", pSide = "bottom" }
        Pos.mineFacing = Pos.facing
        print("[Base] Storage locked below.")
        return true
    end

    if Base.isRealInventory("up") then
        Pos.chestPos = { x = Pos.x, y = Pos.y + 1, z = Pos.z, side = "up", pSide = "top" }
        Pos.mineFacing = Pos.facing
        print("[Base] Storage locked above.")
        return true
    end

    print("[Base] Warning: No storage found nearby!")
    return false
end

function Base.refuelFromInventory()
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.refuel(0) then
            while turtle.getFuelLevel() < CONFIG.TARGET_FUEL and turtle.getItemCount(slot) > 0 do
                turtle.refuel(1)
            end
        end
    end
    turtle.select(1)
end

function Base.refuelFromChest()
    if not Pos.chestPos then return end
    if Pos.chestPos.facing then Nav.setFacing(Pos.chestPos.facing) end

    local currentFuel = turtle.getFuelLevel()
    local fuelNeeded = CONFIG.TARGET_FUEL - currentFuel
    if fuelNeeded <= 0 then return end

    local chest = peripheral.wrap(Pos.chestPos.pSide or "front")
    if not chest or not chest.list then return end

    local items = chest.list()
    local fuelName, fuelVal = nil, 80
    for slot, item in pairs(items) do
        local ok, val = Base.isFuel(item.name)
        if ok then fuelName = item.name; fuelVal = val; break end
    end
    if not fuelName then return end

    local countNeeded = math.ceil(fuelNeeded / math.max(fuelVal, 1))
    for s = 1, 16 do if turtle.getItemCount(s) == 0 then turtle.select(s) break end end

    local sucked = false
    if Pos.chestPos.side == "down" then sucked = turtle.suckDown(countNeeded)
    elseif Pos.chestPos.side == "up" then sucked = turtle.suckUp(countNeeded)
    else sucked = turtle.suck(countNeeded) end

    if sucked then
        if turtle.refuel(0) then turtle.refuel()
        else
            if Pos.chestPos.side == "down" then turtle.dropDown()
            elseif Pos.chestPos.side == "up" then turtle.dropUp()
            else turtle.drop() end
        end
    end
    turtle.select(1)
end

function Base.dropTrash()
    if not CONFIG.DROP_TRASH then return end
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and BASE_TERRAIN_TRASH[item.name] then
            turtle.select(slot)
            turtle.dropDown()
        end
    end
    turtle.select(1)
end

function Base.unloadAndRefuel()
    print("[Base] Returning home to base (0,0,0)...")
    while Pos.y < 0 do Nav.up() end
    Nav.goTo(0, 0, 0)

    local found = Base.findChest()
    if not found then
        print("[Storage ERROR] Storage NOT detected! Keeping items safe.")
        sleep(2)
        return
    end

    if Pos.chestPos and Pos.chestPos.facing then
        Nav.setFacing(Pos.chestPos.facing)
    end

    if not Base.isRealInventory(Pos.chestPos.side) then
        print("[Storage ERROR] Target is not an inventory! Drop aborted.")
        return
    end

    print("[Base] Depositing resources into storage...")
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item then
            local isScanner = item.name:find("geo_scanner") or item.name:find("geoscanner")
            local isTool = item.name:find("pickaxe")
            if not isScanner and not isTool then
                turtle.select(slot)
                local ok = false
                if Pos.chestPos.side == "down" then ok = turtle.dropDown()
                elseif Pos.chestPos.side == "up" then ok = turtle.dropUp()
                else ok = turtle.drop() end

                if not ok then
                    print(string.format("[Storage Warning] Slot %d full.", slot))
                end
            end
        end
    end

    if turtle.getFuelLevel() < CONFIG.TARGET_FUEL then
        Base.refuelFromChest()
    end

    Nav.setFacing(Pos.mineFacing)
    print("[Base] Done. Fuel: " .. turtle.getFuelLevel())
end

-- ============================================================================
-- 4. ДЕТЕКТОР РУД И ФИЛЬТР ЗОН (Y-DEPTH + HORIZONTAL RADIUS)
-- ============================================================================
local Miner = {
    oresMined = 0,
    minedHistory = {},
}

local function isAllowedMiningLocation(x, y, z)
    local baseLevel = (Pos.chestPos and Pos.chestPos.y) or 0
    -- 1. Высота должна быть ниже SAFE_OFFSET_Y
    if y > (baseLevel + CONFIG.SAFE_OFFSET_Y) then return false end
    -- 2. Горизонтальные координаты должны быть внутри MAX_HORIZONTAL_RADIUS
    if not isInsideHorizontalLimit(x, z) then return false end
    return true
end

function Miner.isOre(block)
    if not block or not block.name then return false end
    local name = block.name:lower()

    if name:find("turtle") or name:find("computercraft") then return false end
    if BASE_TERRAIN_TRASH[name] then return false end

    if name:find("ore") or name:find("debris") or name:find("raw") or name:find("cluster") or name:find("crystal") then
        return true
    end

    local modId = name:match("^(.-):")
    if modId and modId ~= "minecraft" and modId ~= "advancedperipherals" then
        return true
    end

    if block.tags and type(block.tags) == "table" then
        for k, v in pairs(block.tags) do
            local tag = (type(v) == "string" and v) or (type(k) == "string" and k) or ""
            tag = tag:lower()
            if tag:find("ores") or tag:find("raw_materials") or tag:find("gems") then return true end
        end
    end
    return false
end

function Miner.calibrateFacing()
    print("[Compass] Precise calibration using base storage...")
    if Pos.chestPos and Pos.chestPos.facing then
        Nav.setFacing((Pos.chestPos.facing + 2) % 4)
    end

    local scan1 = scanner.scan(4)
    if not scan1 then return end
    
    local chest1 = nil
    for _, b in ipairs(scan1) do
        local n = b.name:lower()
        if n:find("chest") or n:find("barrel") or n:find("storage") or n:find("vault") or n:find("backpack") or n:find("drawer") then
            chest1 = b
            break
        end
    end

    if not chest1 then return end

    Nav.forward()
    local scan2 = scanner.scan(4)
    Nav.back()
    if not scan2 then return end

    local chest2 = nil
    for _, b in ipairs(scan2) do
        local n = b.name:lower()
        if n:find("chest") or n:find("barrel") or n:find("storage") or n:find("vault") or n:find("backpack") or n:find("drawer") then
            chest2 = b
            break
        end
    end

    if not chest2 then return end

    local dxMove = chest1.x - chest2.x
    local dzMove = chest1.z - chest2.z

    if dxMove == 1 then Pos.facing = 1
    elseif dxMove == -1 then Pos.facing = 3
    elseif dzMove == 1 then Pos.facing = 2
    elseif dzMove == -1 then Pos.facing = 0 end

    Pos.x, Pos.y, Pos.z = 0, 0, 0
    if Pos.chestPos and Pos.chestPos.facing then
        Pos.mineFacing = (Pos.chestPos.facing + 2) % 4
    end
    print(string.format("[Compass] Calibrated! Facing: %d", Pos.facing))
end

-- Сканирование руд (СТРОГО ВНУТРИ РАДИУСА И ГЛУБИНЫ)
function Miner.scanOres(radius)
    local cooldown = scanner.getScanCooldown and scanner.getScanCooldown() or 0
    if cooldown > 0 then sleep(cooldown / 1000) end

    local data = scanner.scan(radius)
    if not data then return {} end

    local list = {}
    for _, block in ipairs(data) do
        local wx = Pos.x + block.x
        local wy = Pos.y + block.y
        local wz = Pos.z + block.z
        local key = wx .. "," .. wy .. "," .. wz

        -- Проверка: попадает ли блок в разрешенную 3D-зону
        if isAllowedMiningLocation(wx, wy, wz) and not Miner.minedHistory[key] and Miner.isOre(block) then
            local dist = math.abs(block.x) + math.abs(block.y) + math.abs(block.z)
            table.insert(list, { x = wx, y = wy, z = wz, name = block.name, dist = dist })
        end
    end

    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

-- ============================================================================
-- 5. ДОБЫЧА ЖИЛЫ
-- ============================================================================
function Miner.mineVein()
    if isAllowedMiningLocation(Pos.x, Pos.y + 1, Pos.z) then
        local okU, bU = turtle.inspectUp()
        if okU and Miner.isOre(bU) then turtle.digUp(); Miner.oresMined = Miner.oresMined + 1 end
    end

    local okD, bD = turtle.inspectDown()
    if okD and Miner.isOre(bD) then turtle.digDown(); Miner.oresMined = Miner.oresMined + 1 end

    local frontX = Pos.x + DX[Pos.facing]
    local frontZ = Pos.z + DZ[Pos.facing]
    if isAllowedMiningLocation(frontX, Pos.y, frontZ) then
        local okF, bF = turtle.inspect()
        if okF and Miner.isOre(bF) then turtle.dig(); Miner.oresMined = Miner.oresMined + 1 end
    end

    while Miner.oresMined < CONFIG.ORE_LIMIT do
        local nearby = Miner.scanOres(CONFIG.VEIN_RADIUS)
        if #nearby == 0 or nearby[1].dist > 3 then break end

        local ore = nearby[1]
        print(string.format("[Vein] Ore: %s at (%d,%d,%d)", ore.name, ore.x, ore.y, ore.z))
        Nav.goTo(ore.x, ore.y, ore.z)
        Miner.minedHistory[ore.x .. "," .. ore.y .. "," .. ore.z] = true
        Miner.oresMined = Miner.oresMined + 1
        Base.dropTrash()
    end

    Base.dropTrash()
end

function Miner.mineTarget(target)
    print(string.format("[Target] %s at (%d,%d,%d)", target.name, target.x, target.y, target.z))
    Nav.goTo(target.x, target.y, target.z)
    Miner.minedHistory[target.x .. "," .. target.y .. "," .. target.z] = true
    Miner.oresMined = Miner.oresMined + 1
    Miner.mineVein()
    print(string.format("[Miner] Progress: %d / %d ores", Miner.oresMined, CONFIG.ORE_LIMIT))
end

-- ============================================================================
-- 6. ГЛАВНЫЙ ИСПОЛНИТЕЛЬНЫЙ ЦИКЛ
-- ============================================================================
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== SWARM UNIT: MONO GEO-MINER v2.5 ===")
    print(string.format("[Zone] Max Horizontal Radius: +/- %d blocks", CONFIG.MAX_HORIZONTAL_RADIUS))
    print(string.format("[Safety] Base Level: Y > %d is SAFE", CONFIG.SAFE_OFFSET_Y))

    Equip.autoEquip()
    Base.findChest()
    Base.refuelFromInventory()
    if turtle.getFuelLevel() < CONFIG.TARGET_FUEL then Base.refuelFromChest() end
    if turtle.getFuelLevel() < CONFIG.MIN_FUEL then error("[Fatal] Fuel too low!") end

    Miner.calibrateFacing()

    -- Стартовое погружение в шахту под базу
    print("[Safety] Plunging into mining depth (Y <= " .. CONFIG.SAFE_OFFSET_Y .. ")...")
    while Pos.y > CONFIG.SAFE_OFFSET_Y do
        if not Nav.down() then break end
    end

    local resumePos = nil

    while true do
        if Miner.oresMined >= CONFIG.ORE_LIMIT then
            print("[Limit] 25 ores mined! Returning home...")
            resumePos = { x = Pos.x, y = Pos.y, z = Pos.z }
            Base.unloadAndRefuel()
            Miner.oresMined = 0

            if resumePos then
                print(string.format("[Resume] Returning to mine depth (%d,%d,%d)...", resumePos.x, resumePos.y, resumePos.z))
                Nav.goTo(resumePos.x, resumePos.y, resumePos.z)
                resumePos = nil
            end
        end

        local list = Miner.scanOres(CONFIG.SCAN_RADIUS)

        if #list > 0 then
            Miner.mineTarget(list[1])
            
            if turtle.getFuelLevel() < 300 then
                print("[Fuel] Low fuel! Emergency return.")
                Base.unloadAndRefuel()
            end
        else
            -- Бурим глубже в безопасной зоне
            print("[Miner] Boring down...")
            local moved = 0
            for i = 1, 6 do
                if Nav.down() then moved = moved + 1 else break end
            end

            -- Если упёрлись в бедрок
            if moved == 0 then
                print("[Miner] Bedrock reached! Relocating shaft...")
                while Pos.y < CONFIG.SAFE_OFFSET_Y do Nav.up() end
                
                -- Пробуем сместиться на 16 блоков вперед
                Nav.setFacing(Pos.mineFacing)
                local shifted = false
                for step = 1, 16 do
                    if Nav.forward() then shifted = true else break end
                end

                -- Если вышли на край разрешенного горизонтального радиуса — разворачиваемся
                if not shifted then
                    print("[Zone] Hit radius limit. Turning into alternate corridor...")
                    Nav.turnRight()
                    for step = 1, 16 do
                        if not Nav.forward() then break end
                    end
                end
            end
        end
    end
end

main()