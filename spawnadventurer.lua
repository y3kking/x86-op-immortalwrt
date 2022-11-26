
package.path = package.path .. ";data/scripts/lib/?.lua"

local AdventurerGuide = include("story/adventurerguide")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace SpawnAdventurer
SpawnAdventurer = {}
local waitingTimer = 5 * 60

if onServer() then

function SpawnAdventurer.initialize(time)
    if Player():getValue("met_adventurer") then
        terminate()
        return
    end

    if time and type(time) == "number" then
        waitingTimer = time
    end
end

function SpawnAdventurer.getUpdateInterval()
    return 10
end

local registerdCallback = false
function SpawnAdventurer.updateServer(timestep)
    local player = Player()
    if not player:getValue("met_adventurer") then
        waitingTimer = waitingTimer - timestep
    end
    if not registerdCallback and waitingTimer <= 0 then
        Player():registerCallback("onSectorEntered", "onSectorEntered")
        registerdCallback = true
    end
end

function SpawnAdventurer.onSectorEntered(player, x, y)
    if Player():getValue("met_adventurer") then return end

    -- check if there are friendly stations
    local friendlyStations = false
    local unfriendlyStations = false

    for _, station in pairs({Sector():getEntitiesByType(EntityType.Station)}) do

        if station.factionIndex then
            local relations = Player():getRelations(station.factionIndex)

            if relations > 30000 then
                friendlyStations = true
            end

            if relations < -10000 then
                unfriendlyStations = true
            end
        end
    end

    if friendlyStations and (not unfriendlyStations) then
        Player():setValue("met_adventurer", true)

        AdventurerGuide.spawn1(Player())
    end

end

function SpawnAdventurer.secure()
    return waitingTimer
end

function SpawnAdventurer.restore(data_in)
    waitingTimer = data_in
end

end
