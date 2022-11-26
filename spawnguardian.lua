
package.path = package.path .. ";data/scripts/lib/?.lua"
include("stringutility")
local Xsotan = include("story/xsotan")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace SpawnGuardian
SpawnGuardian = {}

if onServer() then

function SpawnGuardian.initialize()
    Player():registerCallback("onSectorEntered", "onSectorEntered")
end

function SpawnGuardian.canSpawn()
    local server = Server()
    local respawnTime = server:getValue("guardian_respawn_time")
    if respawnTime then return false end

    return true
end

function SpawnGuardian.onSectorEntered(player, x, y, changeType)
    if not (x == 0 and y == 0) then return end
    if not (changeType == SectorChangeType.Jump) and not (changeType == SectorChangeType.Switch) then return end

    if not SpawnGuardian.canSpawn() then
        local player = Player()
        player:sendChatMessage("", ChatMessageType.Information, "Your sensors are picking up energy signatures of a major battle that happened here. But for now, there doesn't seem to be anything here."%_T)
        return
    end

    -- only spawn him once
    local sector = Sector()
    if sector:getEntitiesByScript("data/scripts/entity/story/wormholeguardian.lua") then return end

    -- clear everything that's not player owned
    local entities = {sector:getEntities()}
    for _, entity in pairs(entities) do
        if not entity.allianceOwned and not entity.playerOwned then
            sector:deleteEntity(entity)
        end
    end

    Xsotan.createGuardian()
end

end
