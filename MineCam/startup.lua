-- ============================================================================
-- SWARM NETBOOT & ZERO-TOUCH AUTO-BOOTSTRAP (v2.2 Precise Hand Detection)
-- ============================================================================
local BOOT_CHANNEL = 101

term.clear()
term.setCursorPos(1, 1)
print("=== SWARM ZERO-TOUCH BOOTLOADER v2.2 ===")

local function findItemSlot(pattern)
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and item.name:lower():find(pattern) then return slot end
    end
    return nil
end

-- ТОЧНАЯ ПРОВЕРКА ТОГО, ЧТО НАДЕТО В РУКАХ ЧЕРЕПАХИ
local function inspectHands()
    local rightHandItem = nil
    local leftHandItem = nil

    local emptySlot = nil
    for s = 1, 16 do
        if turtle.getItemCount(s) == 0 then emptySlot = s; break end
    end

    if emptySlot then
        -- Щуп правой руки
        turtle.select(emptySlot)
        if turtle.equipRight() then
            local d = turtle.getItemDetail(emptySlot)
            if d then rightHandItem = d.name:lower() end
            turtle.equipRight() -- Возвращаем в правую руку
        end

        -- Щуп левой руки
        if turtle.equipLeft() then
            local d = turtle.getItemDetail(emptySlot)
            if d then leftHandItem = d.name:lower() end
            turtle.equipLeft() -- Возвращаем в левую руку
        end
    end

    return rightHandItem, leftHandItem
end

-- Поиск соседней бочки/сундука
local function findAdjacentStorage()
    for dir = 0, 3 do
        local ok, data = turtle.inspect()
        if ok and data.name then
            local n = data.name:lower()
            if n:find("barrel") or n:find("chest") or n:find("storage") or n:find("vault") or n:find("backpack") or n:find("crate") then
                return "front"
            end
        end
        turtle.turnRight()
    end

    local okD, dataD = turtle.inspectDown()
    if okD and dataD.name then
        local n = dataD.name:lower()
        if n:find("barrel") or n:find("chest") or n:find("storage") or n:find("vault") or n:find("backpack") or n:find("crate") then
            return "down"
        end
    end

    local okU, dataU = turtle.inspectUp()
    if okU and dataU.name then
        local n = dataU.name:lower()
        if n:find("barrel") or n:find("chest") or n:find("storage") or n:find("vault") or n:find("backpack") or n:find("crate") then
            return "up"
        end
    end
    return nil
end

local function rawSuck(side, count)
    if side == "down" then return turtle.suckDown(count)
    elseif side == "up" then return turtle.suckUp(count)
    else return turtle.suck(count) end
end

local function rawDrop(side)
    if side == "down" then return turtle.dropDown()
    elseif side == "up" then return turtle.dropUp()
    else return turtle.drop() end
end

local function extractFromStorage(storageSide, targetSlot, countNeeded)
    local pSide = (storageSide == "down" and "bottom") or (storageSide == "up" and "top") or "front"
    local chest = peripheral.wrap(pSide)
    if not chest or not chest.list then return false end

    local items = chest.list()
    local tempSlots = {}

    for s = 1, targetSlot - 1 do
        if items[s] then
            for turtleSlot = 1, 16 do
                if turtle.getItemCount(turtleSlot) == 0 then
                    turtle.select(turtleSlot)
                    if rawSuck(storageSide, items[s].count) then
                        table.insert(tempSlots, turtleSlot)
                    end
                    break
                end
            end
        end
    end

    local pulled = false
    for turtleSlot = 1, 16 do
        if turtle.getItemCount(turtleSlot) == 0 then
            turtle.select(turtleSlot)
            pulled = rawSuck(storageSide, countNeeded)
            break
        end
    end

    for _, tSlot in ipairs(tempSlots) do
        turtle.select(tSlot)
        rawDrop(storageSide)
    end
    turtle.select(1)
    return pulled
end

-- САМОСНАРЯЖЕНИЕ С АБСОЛЮТНЫМ КОНТРОЛЕМ РУК И ИНВЕНТАРЯ
local function bootstrapEquipment()
    -- 1. Сначала сканируем свои руки и карманы
    local rightHand, leftHand = inspectHands()

    local gotPick = (rightHand and rightHand:find("pickaxe") ~= nil) or (leftHand and leftHand:find("pickaxe") ~= nil) or (findItemSlot("pickaxe") ~= nil)
    local gotScanner = (rightHand and rightHand:find("geo") ~= nil) or (leftHand and leftHand:find("geo") ~= nil) or (findItemSlot("geo") ~= nil) or (findItemSlot("scan") ~= nil)
    local gotModem = (rightHand and rightHand:find("modem") ~= nil) or (leftHand and leftHand:find("modem") ~= nil) or (findItemSlot("modem") ~= nil) or (peripheral.find("modem") ~= nil)

    print(string.format("[Status] Pickaxe: %s | Scanner: %s | Modem: %s", 
        gotPick and "YES" or "NO", gotScanner and "YES" or "NO", gotModem and "YES" or "NO"))

    -- Если всё уже есть — в сундук не лезем!
    if gotPick and gotScanner and gotModem and turtle.getFuelLevel() >= 1000 then
        print("[Bootstrap] Kit is already complete!")
        return
    end

    local storageSide = findAdjacentStorage()
    if not storageSide then return end

    local pSide = (storageSide == "down" and "bottom") or (storageSide == "up" and "top") or "front"
    local chest = peripheral.wrap(pSide)
    if not chest or not chest.list then return end

    local items = chest.list()

    for slot, item in pairs(items) do
        local n = item.name:lower()
        local isScanner = n:find("geo_scanner") or n:find("geoscanner")
        local isPick = n:find("pickaxe")
        local isModem = n:find("wireless_modem") or n:find("modem")
        local isCoal = n:find("coal") or n:find("charcoal") or n:find("fuel")

        -- Берем кирку, ТОЛЬКО ЕСЛИ ЕЁ НЕТ В РУКАХ И КАРМАНАХ
        if isPick and not gotPick then
            print(string.format("[Bootstrap] Taking 1x Pickaxe from slot %d...", slot))
            extractFromStorage(storageSide, slot, 1)
            local pSlot = findItemSlot("pickaxe")
            if pSlot then turtle.select(pSlot); turtle.equipRight(); sleep(0.2) end
            gotPick = true
            items = chest.list()

        -- Берем модем, ТОЛЬКО ЕСЛИ ЕГО НЕТ В РУКАХ И КАРМАНАХ
        elseif isModem and not gotModem then
            print(string.format("[Bootstrap] Taking 1x Wireless Modem from slot %d...", slot))
            extractFromStorage(storageSide, slot, 1)
            local mSlot = findItemSlot("modem")
            if mSlot then turtle.select(mSlot); turtle.equipLeft(); sleep(0.2) end
            gotModem = true
            items = chest.list()

        -- Берем сканер, ТОЛЬКО ЕСЛИ ЕГО НЕТ
        elseif isScanner and not gotScanner then
            print(string.format("[Bootstrap] Taking 1x Geo Scanner from slot %d...", slot))
            extractFromStorage(storageSide, slot, 1)
            gotScanner = true
            items = chest.list()

        -- Заправка (только если топлива < 1000)
        elseif isCoal and turtle.getFuelLevel() < 1000 then
            print(string.format("[Bootstrap] Refueling from slot %d...", slot))
            extractFromStorage(storageSide, slot, 16)
            for s = 1, 16 do
                turtle.select(s)
                if turtle.refuel(0) then turtle.refuel() end
            end
            items = chest.list()
        end
    end
end

bootstrapEquipment()

-- Загрузка скрипта по воздуху
local modem = peripheral.find("modem")
if not modem then
    local mSlot = findItemSlot("modem")
    if mSlot then turtle.select(mSlot); turtle.equipLeft(); sleep(0.2); modem = peripheral.find("modem") end
end

if not modem then
    if fs.exists("miner.lua") then shell.run("miner.lua") else error("Modem missing and no miner.lua!") end
    return
end

modem.open(BOOT_CHANNEL)
print("[NetBoot] Downloading firmware from Base #211...")

local myId = os.getComputerID()
modem.transmit(BOOT_CHANNEL, BOOT_CHANNEL, { type = "REQ_FIRMWARE", origin = myId })

local timer = os.startTimer(4)
local downloaded = false

while true do
    local event, p1, ch, replyCh, msg = os.pullEvent()
    if event == "modem_message" and ch == BOOT_CHANNEL and type(msg) == "table" then
        if msg.type == "FIRMWARE_PAYLOAD" and msg.code and (msg.target == myId or msg.target == "ALL") then
            local file = fs.open("miner.lua", "w")
            file.write(msg.code)
            file.close()
            downloaded = true
            break
        end
    elseif event == "timer" and p1 == timer then
        break
    end
end

modem.close(BOOT_CHANNEL)

if downloaded or fs.exists("miner.lua") then
    print("[NetBoot] Starting miner.lua...")
    sleep(0.5)
    shell.run("miner.lua")
else
    error("[Fatal] NetBoot failed!")
end