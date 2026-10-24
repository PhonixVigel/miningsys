-- ============================================================
-- CONFIGURATION
-- ============================================================
 
-- IDs mapped exactly to what we found inside the table row dump
local CLASS_SPAWNS = {
    ["madmax:mad"] = "5980.00 65.00 -286.00",
    ["madmax:scientists"] = "-3262.00 60.00 -5015.00", -- Perfect match!
    ["madmax:fanatics"] = "-2626.00 63.00 5447.00",
    ["madmax:punished"] = "0 302 0"
}
 
-- Fallback spawn coordinate
local DEFAULT_SPAWN = "0 302 0"
 
-- Player Blacklist
local BLACKLIST = {
    ["VozduHAN"] = true,
    ["VozduHAN2"] = true,
    ["PhonixVogel"] = false,
}
 
local DETECTION_RADIUS = 10
 
-- ============================================================
 
term.clear()
term.setCursorPos(1, 1)
print("=== INITIALIZING TP-ONLY SYSTEM ===")
 
local detector = peripheral.find("player_detector") or peripheral.find("playerDetector")
if not detector then 
    print("[CRITICAL ERROR] Player Detector NOT found!")
    error() 
end
 
print("[SUCCESS] Player Detector linked.")
 
local function getPlayerFaction(playerName)
    print("[INFO] Querying internal table for: " .. playerName)
    
    local cmd = string.format("origin get %s neoorigins:origin", playerName)
    
    local success, result, textTable = pcall(function()
        return commands.exec(cmd)
    end)
    
    local rawText = ""
    
    if success and type(textTable) == "table" then
        local textParts = {}
        for _, line in pairs(textTable) do
            table.insert(textParts, tostring(line))
        end
        rawText = table.concat(textParts, " "):lower()
        print("[DEBUG] Intercepted row text: " .. rawText)
    else
        print("[WARNING] Extraction error from the hidden buffer.")
    end
    
    for factionID, _ in pairs(CLASS_SPAWNS) do
        if rawText:find(factionID:lower(), 1, true) then
            print("[SUCCESS] Found matching layout key: " .. factionID)
            return factionID
        end
    end
    
    return nil
end
 
-- Teleport function
local function teleportPlayer(playerName, coords)
    local cmd = string.format("tp %s %s", playerName, coords)
    local success, result = pcall(function()
        return commands.exec(cmd)
    end)
    
    if success then
        print("[TP SUCCESS] " .. playerName .. " -> " .. coords)
        return true
    else
        print("[TP ERROR] Failed: " .. tostring(result))
        return false
    end
end
 
-- ============================================================
-- MAIN LOOP
-- ============================================================
print("=== MAD MAX SPAWN SYSTEM ACTIVE ===")
print("Listening to players within " .. DETECTION_RADIUS .. " blocks...")
 
while true do
    local success, players = pcall(detector.getPlayersInCubic, 
                                  DETECTION_RADIUS, DETECTION_RADIUS, DETECTION_RADIUS)
    
    if success and players and #players > 0 then
        for _, player in ipairs(players) do
            local playerName = type(player) == "table" and (player.name or player) or tostring(player)
            
            if not BLACKLIST[playerName] and playerName ~= "" and not playerName:find("table:") then
                print("\n" .. string.rep("-", 40))
                print("[DETECTED] Player: " .. playerName)
                
                local faction = getPlayerFaction(playerName)
                local spawnCoords = DEFAULT_SPAWN
                
                if faction and CLASS_SPAWNS[faction] then
                    print("[FACTION] Verified: " .. faction)
                    spawnCoords = CLASS_SPAWNS[faction]
                else
                    print("[WARNING] Text unmatched. Routing to fallback.")
                end
                
                -- ТПаем игрока на каждом тике цикла
                teleportPlayer(playerName, spawnCoords)
            end
        end
    end
 
    -- Задержка ровно в 1 секунду. Скрипт проверяет зону и ТПает каждую секунду.
    sleep(1) 
end
