package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"

include("utility")
include("stringutility")
include("structuredmission")
include("callable")

local OperationExodus = include("story/operationexodus")
local MissionUT = include("missionutility")
local SectorGenerator = include("SectorGenerator")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Haathi"%_T
mission.data.title = "The Haathi"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.location = {}

mission.data.description =
{
    "Find out more about the Haathi"%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "Find the first beacon"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Ask around to find another beacon. Once you have found matching beacons, go to the location indicated by them"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Find the beacon in sector"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Follow the beacons"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Talk to the final beacon"%_T, bulletPoint = true, fulfilled = false, visible = false},
}

-- on accomplish frame mission has to be moved on
mission.globalPhase.onAccomplish = function()
    local player = Player()
    player:invokeFunction("storyquestutility.lua", "onFollowUpQuestAccomplished")
end
mission.globalPhase.playerCallbacks =
{
    {
        name = "onItemAdded",
        func = function(index, amount, amountBefore)
            if onServer() then
                local player = Player()
                local inventory = player:getInventory()
                local item = inventory:find(index)

                if item and item.itemType == InventoryItemType.SystemUpgrade then
                    if item.script == "data/scripts/systems/teleporterkey1.lua" then
                        accomplish()
                    end
                end
            end
        end
    }
}

-- sends mission mail and continues on read mail
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    -- find first beacon location
    local x, y = Sector():getCoordinates()
    findNearbyBeacon(x, y)

    local player = Player()
    local mail = Mail()
    if mission.data.custom.location.x == nil then
        mail.text = "Hello!\n\nSomebody told me about strange beacons in this area. We should go take a look at them.\n\nGreetings,\nThe Hermit"%_T
    else
        mail.text = Format("Hello!\n\nSomebody told me about strange beacons in this area. We should go take a look at them. I already tracked one in sector (%1%:%2%). Go there and take a look at the beacon.\n\nGreetings,\nThe Hermit"%_T, mission.data.custom.location.x, mission.data.custom.location.y)
    end
    mail.header = "The Haathi /* Mail Subject */"%_T
    mail.sender = "The Hermit"%_T
    mail.id = "Exodus_Mission_Mail"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Exodus_Mission_Mail" then
            setPhase(2)
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

-- creates an exodusbeacon in target sector, if there isn't already one
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    -- if player already has exodus script he probably doesn't need the first beacon anymore, but it doesn't hurt
    checkForExodusScript()

    if mission.data.custom.location.x == nil then
        mission.data.description[2].fulfilled = true
        setPhase(3)
    else
        mission.data.location = {}
        mission.data.location.x = mission.data.custom.location.x
        mission.data.location.y = mission.data.custom.location.y
        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Investigate the beacon in sector (${xCoord}:${yCoord})"%_T, arguments = {xCoord = mission.data.custom.location.x, yCoord = mission.data.custom.location.y}, bulletPoint = true, visible = true}
    end
end
mission.phases[2].onTargetLocationEntered = function(x, y)
    if onServer() then
        local beacon = Sector():getEntitiesByScript("data/scripts/entity/story/exodusbeacon.lua")
        if not beacon then
            createBeacon()
        end
    end
end
mission.phases[2].playerCallbacks = {}
mission.phases[2].playerCallbacks[1] =
{
    name = "onScriptAdded",
    func = function(playerIndex, scriptIndex, scriptPath)
        local player = Player()
        local script = scriptPath
        if script == "data/scripts/player/story/exodus.lua" then
            setPhase(3)
        end
    end
}
mission.phases[2].noBossEncountersTargetSector = true
mission.phases[2].noPlayerEventsTargetSector = true
mission.phases[2].showUpdateOnEnd = true

-- checks if second beacon was found
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    mission.data.location = nil
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
end
mission.phases[3].onStartDialog = function(entityId)
    local entity = Entity(entityId)
    if not entity then return end

    if entity:hasScript("data/scripts/entity/dialogs/storyhints.lua") then
        local x, y = Sector():getCoordinates()
        findNearbyBeacon(x, y)
        ScriptUI(entityId):addDialogOption("Do you know where to find beacons that talk to you?"%_t, "onBeaconLocationHintAsked")
        return
    end

    if entity:hasScript("data/scripts/entity/story/exodusbeacon.lua") then
        invokeServerFunction("setBeaconInteracted")
    end
end
mission.phases[3].onTargetLocationEntered = function(x, y)
    -- location entered that was given in hint
    if onServer() then
        local beacon = Sector():getEntitiesByScript("data/scripts/entity/story/exodusbeacon.lua")
        if not beacon then
            createBeacon()
        end
    end
end
mission.phases[3].onSectorEntered = function (x, y)
    if onClient() then return end
    -- if the player already knows point and goes there, mission should advance
    local rendezVousPoints = OperationExodus.getRendezVousPoints()
    for _, coords in pairs(rendezVousPoints) do
        if coords.x == x and coords.y == y then
            nextPhase()
        end
    end
end
mission.phases[3].showUpdateOnEnd = true

-- checks if corner point was found
mission.phases[4] = {}
mission.phases[4].onBeginServer = function()
    mission.data.description[4].fulfilled = true
    mission.data.description[5].fulfilled = true
    mission.data.description[6].visible = true
end
mission.phases[4].onSectorEntered = function (x, y)
    if onClient() then return end
    local corners = OperationExodus.getCornerPoints()

    for _, coords in pairs(corners) do
        if coords.x == x and coords.y == y then
            mission.data.description[6].fulfilled = true
            mission.data.description[7].visible = true
            setPhase(5)
        end
    end
end

-- update description and wait for player to collect artifact
mission.phases[5] = {}
mission.phases[5].onBeginServer = function()
    -- set entire description besides last one to fulfilled and visible
    mission.data.description[4].fulfilled = true
    mission.data.description[5].fulfilled = true
    mission.data.description[6].fulfilled = true
    mission.data.description[6].visible = true
    mission.data.description[7].visible = true
end

function setBeaconInteracted()
    mission.data.location = nil -- no next target sector yet
    mission.data.description[3].fulfilled = true
    mission.data.description[5].fulfilled = true
    sync()
end
callable(nil, "setBeaconInteracted")

function findNearbyBeacon(x_in, y_in)
    if onClient() then invokeServerFunction("findNearbyBeacon", x_in, y_in) return end

    local x, y
    for i = 0, 5 do
        x, y = MissionUT.getSector(x_in, y_in, 8, 25 + i * 10, false, false, false, false)
        if x and y then
            break
        end
    end

    if not x or not y then
        x, y = MissionUT.getSector(0, 0, 350, 500, false, false, false, false)
    end

    mission.data.custom.location = {x = x, y = y}
    sync()

    return x, y
end
callable(nil, "findNearbyBeacon")

function createBeacon()
    local x, y = Sector():getCoordinates()
    local generator = SectorGenerator(x, y)
    OperationExodus.generateBeacon(generator)
end

function checkForExodusScript()
    if onClient() then invokeServerFunction("checkForExodusScript") return end
    local player = Player()
    local scripts = player:getScripts()
    for _, script in pairs(scripts) do
        if script == "data/scripts/player/story/exodus.lua" then
            setPhase(3)
        end
    end
end
callable(nil, "checkForExodusScript")

local hintAskedOnEnd = makeDialogServerCallback("hintAskedOnEnd", 3, function()
    -- player now knows location - so show it on map
    mission.data.location = {}
    mission.data.location.x = mission.data.custom.location.x
    mission.data.location.y = mission.data.custom.location.y
    mission.data.description[5] = {text = "Go to the beacon in sector (${xCoord}:${yCoord})"%_T, arguments = {xCoord = mission.data.custom.location.x, yCoord = mission.data.custom.location.y}, bulletPoint = true, visible = true, fulfilled = false}
    sync()
end)

local onNoLocationReceived = makeDialogServerCallback("onNoLocationReceived", 3, function()
    -- just calculate the location again, you only get to here if the location was missing for some reason
    findNearbyBeacon(Sector():getCoordinates())
    sync()
end)

function onBeaconLocationHintAsked(entityId)
    if mission.data.custom.location.x == nil then
        local dialogNo = {}
        dialogNo.text = "I've never seen anything of the sort. Ask someone else."%_t
        dialogNo.answers = {{answer = "Okay, thanks."%_t}}
        dialogNo.onEnd = onNoLocationReceived

        ScriptUI(entityId):showDialog(dialogNo)
    else
        local dialogYes = {}
        dialogYes.text = string.format("There was a strange beacon in sector (${x}:${y}). It didn't do anything special except repeating a message over and over that I couldn't do anything with."%_t% {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialogYes.answers = {
            {answer = "Thanks for your help."%_t}
        }
        dialogYes.onEnd = hintAskedOnEnd

        ScriptUI(entityId):showDialog(dialogYes)
    end
end
