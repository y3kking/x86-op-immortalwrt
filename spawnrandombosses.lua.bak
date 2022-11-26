
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include ("randomext")
include ("utility")
local SectorSpecifics = include ("sectorspecifics")
local PirateGenerator = include ("pirategenerator")
local SectorTurretGenerator = include ("sectorturretgenerator")
local AI = include("story/ai")
local Swoks = include("story/swoks")


-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace SpawnRandomBosses
SpawnRandomBosses = {}
local self = SpawnRandomBosses

self.spawnInterdictions = {}
self.consecutiveJumps = 0

local noSpawnTimer = 0
local aiPresent = false


if onServer() then

function SpawnRandomBosses.getUpdateInterval()
    if aiPresent then
        return 0.5
    else
        return 10
    end
end

function SpawnRandomBosses.initialize()
    Player():registerCallback("onSectorEntered", "onSectorEntered")
end

function SpawnRandomBosses.onSectorEntered(player, x, y, changeType)

    if not (changeType == SectorChangeType.Jump) and not (changeType == SectorChangeType.Switch) then return end
    if noSpawnTimer > 0 then return end
    if self.getSpawningDisabled(x, y) then return end

    self.trySpawningSwoks(player, x, y)
    self.trySpawningAI(player, x, y)
end

function SpawnRandomBosses.trySpawningSwoks(player, x, y)

    local dist = length(vec2(x, y))
    local spawn

    if dist > 350 and dist < 430 then
        local specs = SectorSpecifics()
        local regular, offgrid, blocked, home = specs:determineContent(x, y, Server().seed)

        if not regular and not offgrid and not blocked and not home then
            self.consecutiveJumps = self.consecutiveJumps + 1

            if random():test(0.04) or self.consecutiveJumps >= 10 then
                spawn = true
                -- on spawn reset the jump counter
                self.consecutiveJumps = 0
            end
        elseif regular then
            -- when jumping into the "wrong" sector, reset the jump counter
            self.consecutiveJumps = 0
        end

    end

    if not spawn then return end
    if Sector():getEntitiesByScript("data/scripts/entity/story/missionadventurer.lua") then return end

    self.spawnSwoks(Player(player), x, y)
end

function SpawnRandomBosses.trySpawningAI(player, x, y)

    local dist = length(vec2(x, y))
    local spawn

    if dist > 240 and dist < 340 then
        local specs = SectorSpecifics()
        local regular, offgrid, blocked, home = specs:determineContent(x, y, Server().seed)

        if not regular and not offgrid and not blocked and not home then
            self.consecutiveJumps = self.consecutiveJumps + 1

            if random():test(0.04) or self.consecutiveJumps >= 10 then
                spawn = true
                -- on spawn reset the jump counter
                self.consecutiveJumps = 0
            end
        elseif regular then
            -- when jumping into the "wrong" sector, reset the jump counter
            self.consecutiveJumps = 0
        end
    end

    if not spawn then return end
    if Sector():getEntitiesByScript("data/scripts/entity/story/missionadventurer.lua") then return end

    self.spawnAI(x, y)
    aiPresent = true

end

-- this is in a separate function so it can be called from outside for testing
function SpawnRandomBosses.spawnAI(x, y)
    AI.spawn(x, y)
end

function SpawnRandomBosses.spawnSwoks(player, x, y)
    Swoks.spawn(player, x, y)
end

function SpawnRandomBosses.onSwoksDestroyed()

    local beaten = Server():getValue("swoks_beaten") or 2
    beaten = beaten + 1

    Server():setValue("swoks_beaten", beaten)

    print ("Swoks was beaten for the %s. time!", beaten)

    noSpawnTimer = 30 * 60
end

function SpawnRandomBosses.updateServer(timeStep)
    -- decrease common no-spawn-timer
    noSpawnTimer = noSpawnTimer - timeStep

    -- check if the AI upgrade was dropped
    local dropped, present = AI.checkForDrop()
    aiPresent = present

    if dropped then
        noSpawnTimer = 30 * 60

        print ("The AI was beaten!")
    end

    -- update spawn interdictions of sectors where no bosses may be spawned
    for i, interdiction in pairs(self.spawnInterdictions) do
        interdiction.time = interdiction.time - timeStep

        if interdiction.time <= 0.0 then
            self.spawnInterdictions[i] = nil
        end
    end
end

function SpawnRandomBosses.disableSpawn(x, y, time)
    time = time or 15

    -- if there is already an interdiction present for the sector, just update it
    for _, interdiction in pairs(self.spawnInterdictions) do
        if interdiction.coordinates.x == x and interdiction.coordinates.y == y then
            interdiction.time = math.max(time, interdiction.time)
            return
        end
    end

    -- no interdiction found -> continue
    local i = 0
    while true do
        i = i + 1

        if not self.spawnInterdictions[i] then
            break
        end
    end

    self.spawnInterdictions[i] = {coordinates = {x=x, y=y}, time = time}
end

function SpawnRandomBosses.getSpawningDisabled(x, y)
    for _, interdiction in pairs(self.spawnInterdictions) do
        if interdiction.coordinates.x == x and interdiction.coordinates.y == y then
            return true
        end
    end

    return false
end


end
