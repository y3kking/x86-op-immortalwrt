package.path = package.path .. ";data/scripts/lib/?.lua"

include("structuredmission")
include("stringutility")
local ShipGenerator = include("shipgenerator")
local Placer = include("placer")
local Smuggler = include("story/smuggler")
local SpawnUtility = include ("spawnutility")
include("randomext")

-- mission.tracing = true

-- data
mission.data.location = {}
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.title = "Easy Delivery"%_t
mission.data.brief = "Easy Delivery"%_t

mission.data.autoTrackMission = true

mission.data.description = {}
mission.data.description[1] = "A stranger gave you some suspicious goods to deliver in exchange for a lot of money. According to him the delivery will be easy.\nYou have 60 minutes to deliver the goods."%_t
mission.data.timeLimit = 60 * 60 -- 1 hour
mission.data.timeLimitInDescription = true

mission.data.custom.spawnedControllers = false

mission.globalPhase = {}
mission.globalPhase.getUpdateInterval = function()
    return 5
end
mission.globalPhase.onRestore = function(data)
    if data.data then return end -- already new version

    -- conversion of old versions to new ones
    if not data.data then
        mission.data = data

        -- try to write internals
        mission.data.internals = {}
        mission.data.internals.timePassed = 0
        mission.data.internals.fulfilled = data.fulfilled
        mission.data.internals.phaseIndex = data.stage
        mission.data.internals.justStarted = data.justStarted
    end

    -- stage and description
    mission.data.custom = {}
    if data.stage == 0 then
        mission.data.custom.spawnedControllers = false
    elseif data.stage == 1 then
        mission.data.custom.spawnedControllers = true
    end
end

mission.phases[1] = {}
mission.phases[1].onBeginClient = function()
    local currentlyTracked = getTrackedMissionScriptIndex()
    if not currentlyTracked then
        setTrackThisMission()
        return
    end

    -- check if our parent script or one of the other parts of bottan story is currently tracked
    -- we can overwrite those
    for index, path in pairs(Player():getScripts()) do
        if index ~= currentlyTracked then goto continue end

        if path == "data/scripts/player/story/bottanmission.lua" then
            setTrackThisMission()
            break
        elseif path == "data/scripts/player/story/smugglerretaliation.lua" then
            setTrackThisMission()
            break
        elseif path == "data/scripts/player/story/smugglerletter.lua" then
            setTrackThisMission()
            break
        end

        ::continue::
    end
end
mission.phases[1].onTargetLocationEntered = function(x, y)
    if onServer() then
        Smuggler.spawn(x, y)
    end
end
mission.phases[1].onSectorEntered = function(x, y)
    if onServer() then
        -- don't spawn controllers in target sector
        if x == mission.data.location.x and y == mission.data.location.y then return end

        -- spawn controllers
        if not mission.data.custom.spawnedControllers then
            local d = distance(vec2(x, y), vec2(mission.data.location.x, mission.data.location.y))
            if d < 30 then
                spawnControllers(x, y)
                mission.data.custom.spawnedControllers = true
            end
        end
    end
end
mission.phases[1].noBossEncountersTargetSector = true
mission.phases[1].noPlayerEventsTargetSector = true
mission.phases[1].noLocalPlayerEventsTargetSector = true



-- helper functions
function setLocation(x, y)
    mission.data.location = {x = x, y = y}
end

function spawnControllers(x, y)
    local faction = Galaxy():getNearestFaction(x, y)

    local player = Player()
    local ship = player.craft

    local defenders = {}

    for i = 1, 4 do
        local pos = random():getDirection() * 150
        local look = random():getDirection()
        local up = random():getDirection()

        table.insert(defenders, ShipGenerator.createDefender(faction, MatrixLookUpPosition(look, up, pos)))
    end

    -- add enemy buffs
    SpawnUtility.addEnemyBuffs(defenders)

    Placer.resolveIntersections()
end
