package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("galaxy")
include("stringutility")
include("structuredmission")
include("callable")
include("randomext")

local SectorSpecifics = include ("sectorspecifics")
local MissionUT = include("missionutility")
local Hermit = include("data/scripts/entity/story/hermit")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "Crossing the Barrier"%_T
mission.data.title = "Crossing the Barrier"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.hermitId = nil
mission.data.custom.teleporterLocation = nil
mission.data.description =
{
    "Be the first to cross the Barrier."%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "(optional) Ask the Hermit for more information"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Cross the Barrier"%_T, bulletPoint = true, fulfilled = false, visible = false},
}

mission.globalPhase.onSectorEnteredReportedByClient = function(x, y)
    checkAccomplished(x, y) -- this function accomplishes if sector is inside barrier
end
mission.globalPhase.onAccomplish = function()
    local player = Player()
    player:invokeFunction("storyquestutility.lua", "onCrossBarrierAccomplished")
end

mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    local player = Player()
    local mail = Mail()
    mail.text = Format("Hello!\n\nNicely done! You collected all artifacts. Now, according to my sources you have to find the sector with the eight key asteroids to open the gate. It should be close to the barrier. Good luck!\n\nGreetings,\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "Find and activate the gate /*Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_Cross_Barrier_Mission"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_Cross_Barrier_Mission" then
            setPhase(2)
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

mission.phases[2] = {}
mission.phases[2].noBossEncountersTargetSector = true
mission.phases[2].noPlayerEventsTargetSector = true
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true
    mission.data.description[4].visible = true

    local player = Player()
    local ok, oldHermitLocationX, oldHermitLocationY = player:invokeFunction("storyquestutility.lua", "getHermitLocation")

    if oldHermitLocationX ~= nil and oldHermitLocationY ~= nil then
        mission.data.location.x = oldHermitLocationX
        mission.data.location.y = oldHermitLocationY
    else
        -- find new meet-up location
        local xSpawn, ySpawn = Hermit.getLocation(Sector():getCoordinates())
        mission.data.location = {x = xSpawn, y = ySpawn}
    end
    mission.data.description[3] = {text = "(optional) Ask the Hermit for more information (${x}:${y})"%_T, arguments = {x = mission.data.location.x, y = mission.data.location.y}, bulletPoint = true, fulfilled = false, visible = true}
end
mission.phases[2].onTargetLocationEntered = function(x, y)
    if onServer() then
        local ship = Hermit.spawn()
        mission.data.custom.hermitId = ship.id.string
        getTeleporterSector()
        nextPhase()
    end
end

mission.phases[3] = {}
mission.phases[3].noBossEncountersTargetSector = true
mission.phases[3].noPlayerEventsTargetSector = true
mission.phases[3].onStartDialog = function(entityId)
    local entity = Entity(mission.data.custom.hermitId)
    if not entity then return end
    ScriptUI(entity.id):addDialogOption("Would you help me again?"%_t, "createHermitDialog")
end
mission.phases[3].onRestore = function(x, y)
    if onServer() then
        local x, y = Sector():getCoordinates()
        if x == mission.data.location.x and y == mission.data.location.y then
            local ship = Hermit.spawn()
            mission.data.custom.hermitId = ship.id.string
        end
    end
end

-- helper functions
-- find a teleporter sector
function getTeleporterSector(sx, sy)

    if not sx or not sy then
        sx, sy = Sector():getCoordinates()
    end

    local dir = normalize(vec2(sx, sy))
    local teleporter = dir * 155
    local tx, ty = math.floor(teleporter.x), math.floor(teleporter.y)

    -- performance optimization to not create internal variables all the time
    -- we also use a second instance to check for content to be sure to not mess up any internals of findSector() down below
    local tmpSpecs = SectorSpecifics(tx, ty, GameSeed())

    local test = function(x, y, regular, offgrid, blocked, home, dust, factionIndex, centralArea)
        if not offgrid then return end -- we know that the sector we're searching is off-grid
        if blocked then return end
        if Balancing_InsideRing(x, y) then return end
        if sx == x and sy == y then return end

        tmpSpecs:initialize(x, y, GameSeed())
        if tmpSpecs.generationTemplate and tmpSpecs.generationTemplate.path == "sectors/teleporter" then
            return true
        end
    end

    local radius = 15
    local specs = SectorSpecifics(tx, ty, GameSeed())

    for i = 0, 20 do
        local target = specs:findSector(random(), tx, ty, test, radius + i * 15, i * 15)
        if target then
            mission.data.custom.teleporterLocation = target
            return
        end
    end

    print("Cross barrier mission: Error: couldn't find a teleporter sector")
end

local locationAskedOnEnd = makeDialogServerCallback("locationAskedOnEnd", 3, function()
    -- player now knows location - so show it on map
    mission.data.location.x = mission.data.custom.teleporterLocation.x
    mission.data.location.y = mission.data.custom.teleporterLocation.y
end)

function createHermitDialog()
    sync()
    local d0_dialog = {}
    local d1_dialog = {}
    local d2_dialog = {}
    local d3_dialog = {}
    local d4_dialog = {}
    local d5_dialog = {}

    d0_dialog.text =  "Ah the young one again, what is it this time?"%_t
    d0_dialog.answers = {{answer = "I need more information."%_t, followUp = d1_dialog}}

    d1_dialog.text = "Always on the hunt, hu? Well, start talking!"%_t
    d1_dialog.answers = {{answer ="I have the eight artifacts. Now what?"%_t, followUp = d2_dialog}}

    d2_dialog.text = "Ah, you’re looking for the gate. Very interesting thing that was. Hum, mh, hum, where do I start.. \n\nRemember the ship from the center that I told you about?\n\nTheir arrival started a race of the best scientists and the most ruthless corporations to find a way to the inside."%_t
    d2_dialog.answers = {{answer = "How did that go?"%_t, followUp = d3_dialog}}

    d3_dialog.text = "About as well as you could expect. Supposedly they managed to build a teleporter system that would be able to open a gate across the barrier.\n\nBut they never managed to open it. There’s been tons of rumors that these artifacts you have could make it work, but nobody has ever tried."%_t
    d3_dialog.answers = {{answer = "That sounds promising. Where was that?"%_t, followUp = d4_dialog}}

    d4_dialog.text = string.format("I've never been there myself. But I've heard that lots of workers with machinery were seen entering sector (${x}:${y}). You should go there."%_t % {x = mission.data.custom.teleporterLocation.x, y = mission.data.custom.teleporterLocation.y})
    d4_dialog.answers = {{answer = "Thank you, I’ll start there."%_t, followUp = d5_dialog}}

    d5_dialog.text = "Good luck!"%_t
    d5_dialog.answers = {{answer = "Thank you!"%_t}}
    d5_dialog.onEnd = locationAskedOnEnd

    ScriptUI(mission.data.custom.hermitId):showDialog(d0_dialog, false)
end

-- needed for testing
function checkAccomplished(x, y)
    if onClient() then return end
    if MissionUT.checkSectorInsideBarrier(x, y) then
        accomplish()
    end
end
