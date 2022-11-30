package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"

include ("structuredmission")
include ("utility")
include ("callable")
include ("goods")
include ("randomext")
include ("relations")
include ("stringutility")
include ("galaxy")
include ("player")

local Dialog = include ("dialogutility")
local Balancing = include ("galaxy")
local AsyncPirateGenerator = include("asyncpirategenerator")
local ShipGenerator = include ("shipgenerator")
local SectorGenerator = include ("SectorGenerator")

--mission.tracing = true

-- custom mission data
mission.data.custom.missionGoodName = "Potato"
mission.data.custom.amountMissionGoods = 45
mission.data.custom.pirateLocation = {}

mission.data.custom.pirateFactionIndex = nil
mission.data.custom.stationId = nil

-- Flag for legacy purposes: used to terminate pre 2.0.7 missions
mission.data.custom.legacyResetUnnecessary = true

-- mission data
mission.data.title = "Investigate Missing Freighters"%_t
mission.data.brief = mission.data.title

mission.data.autoTrackMission = true

mission.data.description = {}
mission.data.description[1] = {text = "For some time now, freighters taking a certain trade route have been disappearing. Pretend to be a freighter yourself and investigate."%_T}
mission.data.description[2] = {text = "Report to ${stationTitle} ${stationName} once you have ${cargoSpace} free cargo space."%_T, bulletPoint = true, fulfilled = false, visible = false}
mission.data.description[3] = {text = "The freighters usually go to (${xCoord}:${yCoord}) first."%_T, bulletPoint = true, fulfilled = false, visible = false}
mission.data.description[4] = {text = "Afterwards, they travel to (${xCoord}:${yCoord})."%_T, bulletPoint = true, fulfilled = false, visible = false}
mission.data.description[5] = {text = "Then they jump to (${xCoord}:${yCoord})."%_T, bulletPoint = true, fulfilled = false, visible = false}
mission.data.description[6] = {text = "Their next stop usually is (${xCoord}:${yCoord})."%_T, bulletPoint = true, fulfilled = false, visible = false}
mission.data.description[7] = {text = "Find the pirate base."%_T, bulletPoint = true, fulfilled = false, visible = false}
mission.data.description[8] = {text = "Defeat the pirates."%_T, bulletPoint = true, fulfilled = false, visible = false}

-- Flag for legacy purposes: used to terminate pre-2.0.7 missions
mission.globalPhase.onRestore = function()
    if not mission.data.custom.legacyResetUnnecessary then
        terminate()
    end
end

-- Phase 1: Calculate all necessary values
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    local name = ""
    local giver = Entity(mission.data.giver.id)
    if giver then name = giver.name end

    mission.data.description[2].arguments = {stationTitle = mission.data.giver.baseTitle, stationName = name, cargoSpace = mission.data.custom.amountMissionGoods}
    mission.data.description[2].visible = true
end
mission.phases[1].updateServer = function()
    if checkCargoSpace() then
        mission.data.targets = {mission.data.giver.id.string}
        setPhase(2)
    end
end
mission.phases[1].onStartDialog = function(entityId)
    if tostring(mission.data.giver.id) == tostring(entityId) then
        local ui = ScriptUI(mission.data.giver.id)
        ui:addDialogOption("I'm ready to find those freighters."%_t, "tryToAddMissionCargo")
    end
end

-- Phase 2: Have player accept mission and add cargo
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    if MissionUT.playerInTargetSector(Player(), mission.data.location) then
        if not Entity(mission.data.giver.id) then
            abortMissionGiverIsGone()
        end
    end
end
mission.phases[2].onTargetLocationEntered = function()
    if not Entity(mission.data.giver.id) then
        abortMissionGiverIsGone()
    end
end
mission.phases[2].onStartDialog = function(entityId)
    if tostring(mission.data.giver.id) == tostring(entityId) then
        local ui = ScriptUI(mission.data.giver.id)
        ui:addDialogOption("I'm ready to find those freighters."%_t, "tryToAddMissionCargo")
    end
end
mission.phases[2].showUpdateOnEnd = true

-- Phase 3: Give player the points on the way
mission.phases[3] = {}
mission.phases[3].onTargetLocationEntered = function(x, y)
    if onClient() then return end

    local x, y = calculateNextLocation()
    mission.data.location = {x = x, y = y}

    mission.data.description[3].fulfilled = true
    mission.data.description[4].arguments = {xCoord = x, yCoord = y}
    mission.data.description[4].visible = true
    nextPhase()
end

mission.phases[4] = {}
mission.phases[4].onTargetLocationEntered = function(x, y)
    if onClient() then return end

    local x, y = calculateNextLocation()
    mission.data.location = {x = x, y = y}

    mission.data.description[4].fulfilled = true
    mission.data.description[5].arguments = {xCoord = x, yCoord = y}
    mission.data.description[5].visible = true
    nextPhase()
end

mission.phases[5] = {}
mission.phases[5].onTargetLocationEntered = function(x, y)
    if onClient() then return end

    local x, y = calculateNextLocation()
    mission.data.location = {x = x, y = y}

    mission.data.description[5].fulfilled = true
    mission.data.description[6].arguments = {xCoord = x, yCoord = y}
    mission.data.description[6].visible = true
    nextPhase()
end

mission.phases[6] = {}
mission.phases[6].onTargetLocationEntered = function(x, y)
    if onClient() then return end

    createFakePirates()

    -- already calculate next sector here, because it is used in the following dialog
    local x, y = calculateNextLocation()
    mission.data.custom.pirateLocation = {x = x, y = y}

    setPhase(7)
end
mission.phases[6].noPlayerEventsTargetSector = true
mission.phases[6].noBossEncountersTargetSector = true
mission.phases[6].noLocalPlayerEventsTargetSector = true

local dialogStarted = false
-- Phase 7: Meet the fake pirates
mission.phases[7] = {}
mission.phases[7].updateTargetLocationClient = function()
    if not dialogStarted and Sector():getEntitiesByScriptValue("pirate_defender", true) then
        deferredCallback(3, "startPirateDialog")
        dialogStarted = true
    end
end
mission.phases[7].updateTargetLocationServer = function()
    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        -- if the player (or his buddies) somehow manage to defeat the pirates before a choice is made in the dialog, set phase 11
        setPhase(11)
    end
end
mission.phases[7].onTargetLocationLeft = function()
    dialogStarted = false
end
mission.phases[7].onRestore = function()
    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        createFakePirates()
    end
end
mission.phases[7].noPlayerEventsTargetSector = true
mission.phases[7].noBossEncountersTargetSector = true
mission.phases[7].noLocalPlayerEventsTargetSector = true

-- if player wants to defeat fake pirates: mission goes to phase 11
-- if player wants to find the real pirates: mission goes to phase 8

-- Phase 8: Meet the real pirates
mission.phases[8] = {}
local piratesCreated = false
mission.phases[8].updateTargetLocationServer = function()
    if not piratesCreated and not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        createPirates()
        piratesCreated = true
    end
end
mission.phases[8].noPlayerEventsTargetSector = true
mission.phases[8].noBossEncountersTargetSector = true
mission.phases[8].noLocalPlayerEventsTargetSector = true

-- Phase 9: start dialog with pirates and fight them
mission.phases[9] = {}
mission.phases[9].triggers = {}
mission.phases[9].triggers[1] =
{
    condition = function() return checkStationCreated() end,
    callback = function() return onStartRealPirateDialog() end,
}
mission.phases[9].onRestore = function()
    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        setPhase(8)
    else
        setPhase(10)
    end
end
mission.phases[9].noPlayerEventsTargetSector = true
mission.phases[9].noBossEncountersTargetSector = true
mission.phases[9].noLocalPlayerEventsTargetSector = true

-- Phase 10: Check if the real pirates were defeated
mission.phases[10] = {}
mission.phases[10].updateTargetLocationServer = function()
    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        -- add warzonecheck to sector again
        Sector():addScriptOnce("data/scripts/sector/background/warzonecheck.lua")

        finishFreightersComeHome()
    end
end
mission.phases[10].onTargetLocationEntered = function()
    if onClient() then return end

    -- if the player returns to the target sector, restart encounter without the dialog
    mission.data.description[7].fulfilled = true
    local faction = Faction(mission.data.custom.pirateFactionIndex)
    local galaxy = Galaxy()
    for _, player in pairs({Sector():getPlayers()}) do
        galaxy:setFactionRelationStatus(faction, Faction(player.index), RelationStatus.War, false, false)
        galaxy:setFactionRelationStatus(faction, Faction(player.allianceIndex), RelationStatus.War, false, false)
    end

    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        createPirates()
    end
end
mission.phases[10].onTargetLocationLeft = function()
    -- if the player leaves the target sector tell him to go back to it
    mission.data.description[6].text = "Go to sector (${x}:${y})"%_T
    mission.data.description[6].arguments = {x = mission.data.custom.pirateLocation.x, y = mission.data.custom.pirateLocation.y}
    mission.data.description[6].fulfilled = false
end
mission.phases[10].onRestore = function()
    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        setPhase(8)
    end
end
mission.phases[10].noPlayerEventsTargetSector = true
mission.phases[10].noBossEncountersTargetSector = true
mission.phases[10].noLocalPlayerEventsTargetSector = true

-- check if all the fake pirates were destroyed
mission.phases[11] = {}
mission.data.custom.readyForTargetSectorUpdate = false -- only check if pirates are still there after we can be sure that they were spawned
mission.phases[11].updateTargetLocationServer = function()
    if mission.data.custom.readyForTargetSectorUpdate == true and not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        finishFreighterPiratesDefeated()
    end
end
mission.phases[11].onTargetLocationEntered = function()
    if onClient() then return end

    -- if the player returns to the target sector, restart encounter without the dialog
    mission.data.description[6].fulfilled = true
    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        createFakePirates()
    end
end
mission.phases[11].onTargetLocationLeft = function()
    mission.data.custom.readyForTargetSectorUpdate = false

    -- if the player leaves the target sector tell him to go back to it
    mission.data.description[7].text = "Go to sector (${x}:${y})"%_T
    mission.data.description[7].arguments = {x = mission.data.custom.pirateLocation.x, y = mission.data.custom.pirateLocation.y}
    mission.data.description[7].fulfilled = false
end
mission.phases[11].onRestore = function()
    mission.data.custom.readyForTargetSectorUpdate = false
    if not Sector():getEntitiesByScriptValue("pirate_defender", true) then
        createFakePirates()
    end
end
mission.phases[11].noPlayerEventsTargetSector = true
mission.phases[11].noBossEncountersTargetSector = true
mission.phases[11].noLocalPlayerEventsTargetSector = true

-- helper functions
function syncValues(values) -- additional sync just for custom data
    if onServer() then
        invokeClientFunction(Player(), "syncValues", mission.data.custom)
    else
        mission.data.custom = values
    end
end
callable(nil, "syncValues")

function checkCargoSpace()
    local player = Player()
    local ship = player.craft
    local cargoSpaceNeeded = goods[mission.data.custom.missionGoodName]:good().size * mission.data.custom.amountMissionGoods

    if not ship or ship.freeCargoSpace == nil or ship.freeCargoSpace < mission.data.custom.amountMissionGoods then
        return false
    else
        return true
    end
end

local addMissionCargo = makeDialogServerCallback("addMissionCargo", 2, function()
    local ship = Player().craft
    ship:addCargo(goods[mission.data.custom.missionGoodName]:good(), mission.data.custom.amountMissionGoods)

    local x, y = calculateNextLocation()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].fulfilled = true
    mission.data.description[3].arguments = {xCoord = x, yCoord = y}
    mission.data.description[3].visible = true
    mission.data.targets = {}

    setPhase(3)
end)

function showEnoughCargoSpaceDialog()
    local giveCargoDialog1 = {}
    local giveCargoDialog2 = {}
    local giveCargoDialog3 = {}

    giveCargoDialog1.text = "You want to help us investigate what happened to our freighters? Every cargo ship we send on that route simply disappears. But no military ship has found anything. Would you pretend to be a freighter and find out what happened to all the others?"%_t
    giveCargoDialog1.answers = {{answer = "I think I can do that."%_t, followUp = giveCargoDialog2}}
    giveCargoDialog2.text = "We will give you some cargo, so you can pretend to be a freighter. Expect dire consequences if you don't return it."%_t
    giveCargoDialog2.answers = {{answer = "I will do my best."%_t, followUp = giveCargoDialog3}}
    giveCargoDialog3.text = "Very well. We are going to send you the route our freighters usually take."%_t
    giveCargoDialog3.onEnd = addMissionCargo

    ScriptUI(mission.data.giver.id):interactShowDialog(giveCargoDialog1, false)
end

function showNotEnoughCargoSpaceDialog()
    local notEnoughCargoDialog1 = {}
    local notEnoughCargoDialog2 = {}

    notEnoughCargoDialog1.text = "You want to help us investigate what happened to our freighters? Every cargo ship we send on that route simply disappears. But no military ship has found anything. Would you pretend to be a freighter and find out what happened to all the others?"%_t
    notEnoughCargoDialog1.answers = {{answer = "I think I can do that."%_t, followUp = notEnoughCargoDialog2}}
    notEnoughCargoDialog2.text = "You don't have enough free cargo space to take our cargo. Please come back once you have enough free cargo space."%_t

    ScriptUI(mission.data.giver.id):interactShowDialog(notEnoughCargoDialog1, false)
end

function showNotDockedDialog()
    local notDockedDialog = {}
    notDockedDialog.text = "You must be docked to the station to pick up the goods."%_t

    ScriptUI(mission.data.giver.id):interactShowDialog(notDockedDialog, false)
end

function tryToAddMissionCargo()
    if onClient() then
        ScriptUI(mission.data.giver.id):interactShowDialog(Dialog.empty())
        invokeServerFunction("tryToAddMissionCargo")
        return
    end

    local player = Player()
    local craft = player.craft
    if not craft then return end

    if checkCargoSpace() then
        local station = Entity(mission.data.giver.id)
        local errors = {}
        errors[EntityType.Station] = "You must be docked to the station to pick up the goods."%_T

        -- If we have enough cargo space here, we should be in phase 2.
        -- If we aren't, have player repeat dialog in order to safely be in phase 2 to make sure dialog callback works as expected
        if CheckPlayerDocked(Player(), station, errors) and mission.internals.phaseIndex == 2 then
            invokeClientFunction(player, "showEnoughCargoSpaceDialog")
        else
            invokeClientFunction(player, "showNotDockedDialog")
        end
    else
        invokeClientFunction(player, "showNotEnoughCargoSpaceDialog")
    end
end
callable(nil, "tryToAddMissionCargo")

function calculateNextLocation()
    local x, y = Sector():getCoordinates()
    local playerInsideBarrier = MissionUT.checkSectorInsideBarrier(x, y)
    local offsetX = math.random(4, 5)
    local offsetY = math.random(4, 5)

    -- make sure we are moving towards the center
    local centerX, centerY
    if x <= 0 then
        centerX = x + offsetX
    elseif x > 0 then
        centerX = x - offsetX
    end

    if y <= 0 then
        centerY = y + offsetY
    elseif y > 0 then
        centerY = y - offsetY
    end

    local newX, newY = MissionUT.getEmptySector(centerX, centerY, 0, 4, playerInsideBarrier)

    if not newX or not newY then
        abortMissionNoLocationFound()
    end

    return newX, newY
end

function abortMissionGiverIsGone()
    if onClient() then
        displayMissionAccomplishedText("MISSION ABORTED"%_t, "The station that hired you no longer exists."%_t)
    end

    if onServer() then
        deferredCallback(1, "terminate")
    end
end

function abortMissionNoLocationFound()
    Player():addMail(createRiftMail())

    mission.data.reward.credits = mission.data.reward.credits * 0.5
    reward()

    terminate()
end

function createPirateFaction()
    local sector = Sector()
    local x, y = sector:getCoordinates()
    local seed = Seed(string.join({GameSeed(), x, y, "investigatemissingfreighters"}, "-"))
    math.randomseed(seed);
    local language = Language(Seed(makeFastHash(seed.value, x, y)))
    local factionNameBase = language:getName()
    local factionName = ("The " .. factionNameBase .. " Pirates")
    local galaxy = Galaxy()

    local faction = galaxy:findFaction(factionName)
    if not faction then
        faction = galaxy:createFaction(factionName, x, y)
        faction.baseName = factionNameBase
        faction.stateForm = "The %s Pirates"%_T
    end

    return faction.index
end


function createFakePirates()
    local sector = Sector()
    local galaxy = Galaxy()
    local x, y = sector:getCoordinates()
    local generator = SectorGenerator(x, y)

    if not mission.data.custom.pirateFactionIndex then
        mission.data.custom.pirateFactionIndex = createPirateFaction()
    end

    local faction = Faction(mission.data.custom.pirateFactionIndex)

    -- create ships
    local volume = Balancing_GetSectorShipVolume(x, y)
    for i = 1, 6 do
        local ship = ShipGenerator.createMilitaryShip(faction, generator:getPositionInSector(), volume)
        ShipAI(ship.id):setAggressive()
        ship:setValue("pirate_defender", true)
        ship:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")
    end

    -- if the player died during the fight and returns to the sector, the pirates are aggressive right away, otherwise they don't attack
    if mission.internals.phaseIndex == 11 then
        for _, player in pairs({sector:getPlayers()}) do
            galaxy:setFactionRelationStatus(faction, Faction(player.index), RelationStatus.War, false, false)
            galaxy:setFactionRelationStatus(faction, Faction(player.allianceIndex), RelationStatus.War, false, false)
        end
    else
        for _, player in pairs({sector:getPlayers()}) do
            galaxy:setFactionRelationStatus(faction, Faction(player.index), RelationStatus.Ceasefire, false, false)
            galaxy:setFactionRelationStatus(faction, Faction(player.allianceIndex), RelationStatus.Ceasefire, false, false)
        end
    end

    mission.data.custom.readyForTargetSectorUpdate = true
    syncValues()
end

function startPirateDialog()
    if onServer() then return end

    local leader = Sector():getEntitiesByScriptValue("pirate_defender", true)
    ScriptUI(leader):interactShowDialog(makePirateDialog(), false)
end

local fightTheFreighterPirates = makeDialogServerCallback("fightTheFreighterPirates", 7, function()
    mission.data.description[6].fulfilled = true
    mission.data.description[8].visible = true

    local faction = Faction(mission.data.custom.pirateFactionIndex)
    local galaxy = Galaxy()
    for _, player in pairs({Sector():getPlayers()}) do
        galaxy:setFactionRelationStatus(faction, Faction(player.index), RelationStatus.War, false, false)
        galaxy:setFactionRelationStatus(faction, Faction(player.allianceIndex), RelationStatus.War, false, false)
    end

    setPhase(11)
end)

local doNotFightFreighterPirates = makeDialogServerCallback("doNotFightFreighterPirates", 7, function()
    mission.data.description[6].fulfilled = true
    mission.data.description[7].visible = true

    for _, pirate in pairs({Sector():getEntitiesByScriptValue("pirate_defender", true)}) do
        pirate.factionIndex = mission.data.giver.factionIndex
    end

    mission.data.location = mission.data.custom.pirateLocation
    setPhase(8)
end)

function makePirateDialog()

    local dialog1 = {}
    local dialog2 = {}
    local dialog3 = {}
    local dialog4 = {}
    local dialog5 = {}
    local dialog6 = {}
    local dialog7 = {}

    dialog1.text = "If you want to live, you have only one option now!"%_t
    dialog1.answers =
    {
        {answer = "I'm listening."%_t, followUp = dialog2},
        {answer = "I know which one that is. I'll kill you!"%_t, followUp = dialog6},
        {answer = "You're the pirates that destroyed all those freighters!"%_t, followUp = dialog3}
    }

    dialog2.text = "You're going to have to become a pirate and fight for us."%_t
    dialog2.answers =
    {
        {answer = "Never!"%_t, followUp = dialog6},
        {answer = "Why would I do that?"%_t, followUp = dialog3}
    }

    dialog3.text = "We didn't want to become pirates. But they attacked us and told us if we didn't fight for them, they would go after our families."%_t
    dialog3.answers =
    {
        {answer = "Who did that?"%_t, followUp = dialog4},
        {answer = "That's a nice excuse!"%_t, followUp = dialog6}
    }

    dialog4.text = string.format("The pirates that have their base in sector (${xCoord}:${yCoord}). They now have a giant army, because they force everybody to fight for them instead of killing them."%_t % {xCoord = mission.data.custom.pirateLocation.x, yCoord = mission.data.custom.pirateLocation.y})
    dialog4.answers =
    {
        {answer = "Then why don't you turn on them?"%_t, followUp = dialog5},
        {answer = "You're no better than them now."%_t, followUp = dialog6}
    }

    dialog5.text = "They're too strong for us. If we fail, they are going to go after our families."%_t
    dialog5.answers =
    {
        {answer = "Fine, I will try to defeat them for you."%_t, followUp = dialog7}
    }

    dialog6.text = "You are outnumbered. Prepare to die!"%_t
    dialog6.onEnd = fightTheFreighterPirates

    dialog7.text = "Thank you so much, we will never attack anyone ever again!"%_t
    dialog7.onEnd = doNotFightFreighterPirates

    return dialog1
end

function getPositionInSector()
    local position = vec3(math.random(), math.random(), math.random());
    local dist = getFloat(-5000, 5000)
    position = position * dist

    -- create a random up, right and look vector
    local up = vec3(math.random(), math.random(), math.random())
    local look = vec3(math.random(), math.random(), math.random())
    local mat = MatrixLookUp(look, up)
    mat.pos = position

    return mat
end

function createPirates()
    -- create ships
    local generator = AsyncPirateGenerator(nil, onPiratesCreated)
    local sector = Sector()

    generator:startBatch()

    -- create 3 pirates
    for i = 1, 3 do
        generator:createScaledPirate(getPositionInSector())
    end

    -- create 3 bandits
    for i = 1, 3 do
        generator:createScaledBandit(getPositionInSector())
    end

    generator:endBatch()

    -- create station
    local sectorGenerator = SectorGenerator(sector:getCoordinates())
    local pirateFaction = Faction(mission.data.custom.pirateFactionIndex)

    local station = sectorGenerator:createStation(pirateFaction, "data/scripts/entity/merchants/shipyard.lua")
    station:addScriptOnce("entity/ai/patrolpeacefully.lua")
    mission.data.custom.stationId = station.id.string
    Boarding(station).boardable = false

    -- damage the station and remove its shield if it has one, otherwise it would be too boring to destroy
    if station.shieldDurability and station.shieldDurability > 0 then
        station.durability = station.maxDurability * 0.5
        station.shieldMaxDurability = 0
    else
        station.durability = station.maxDurability * 0.5
    end

    station:setValue("pirate_defender", true)
    station:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")
    station:removeScript("data/scripts/entity/backup.lua")

    -- remove warzonecheck from the sector
    sector:removeScript("data/scripts/sector/background/warzonecheck.lua")

    syncValues()
end

function onPiratesCreated(generated)
    for _, pirate in pairs(generated) do
        pirate.factionIndex = mission.data.custom.pirateFactionIndex
        pirate:addScriptOnce("entity/ai/patrolpeacefully.lua") -- don't attack yet, but fly around so that background looks more alive
        pirate:setValue("pirate_defender", true)
        pirate:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")
    end

    -- if in phase (8), set phase (9)
    if mission.internals.phaseIndex == 8 then
        setPhase(9)
    end
end

function checkStationCreated()
    if onServer() then return end

    -- check only on client
    for _, entity in pairs({Sector():getEntitiesByType(EntityType.Station)}) do
        if entity:getValue("pirate_defender", true) then
            return true
        end
    end

    return false
end

local setPiratesAggressive = makeDialogServerCallback("setPiratesAggressive", 9, function()
    local faction = Faction(mission.data.custom.pirateFactionIndex)
    local galaxy = Galaxy()
    for _, player in pairs({Sector():getPlayers()}) do
        galaxy:setFactionRelationStatus(faction, Faction(player.index), RelationStatus.War, false, false)
        galaxy:setFactionRelationStatus(faction, Faction(player.allianceIndex), RelationStatus.War, false, false)
    end

    for _, pirate in pairs({Sector():getEntitiesByScriptValue("pirate_defender", true)}) do
        pirate:removeScript("entity/ai/patrolpeacefully.lua")
        pirate:addScriptOnce("entity/ai/patrol.lua")
    end

    -- set station aggressive as well
    if mission.data.custom.stationId then
        local station = Entity(mission.data.custom.stationId)
        station:removeScript("entity/ai/patrolpeacefully.lua")
        station:addScriptOnce("entity/ai/patrol.lua")
    end

    mission.data.description[7].fulfilled = true
    mission.data.description[8].visible = true
    setPhase(10)
end)

function onStartRealPirateDialog()
    local station = Entity(mission.data.custom.stationId)
    if not station then return end

    ScriptUI(station):interactShowDialog(realPirateDialog(), false)
end

function realPirateDialog()
    local dialog1 = {}
    local dialog2 = {}

    dialog1.text = "What are you doing here?"%_t
    dialog1.answers = {
        {answer = "I heard you are forcing innocent freighters to fight for you. I will put a stop to that."%_t, followUp = dialog2},
        {answer = "(attack)"%_t, followUp = dialog2},
    }

    dialog2.text = "Let's see you try!"%_t
    dialog2.onEnd = setPiratesAggressive

    return dialog1
end

function finishFreightersComeHome()
    local mail = Mail()
    mail.text = "Thank you! \n\nOur people have returned home safely. \n\nWe are in your debt.\n\nYou may keep the cargo we gave you.\n\nGreetings,\n\nLieutenant Omask."%_T
    mail.header = "Thank you for returning our people /* Mail Subject */"%_T
    mail.sender = "Lieutenant Omask"%_T
    mail.id = "FreightersComeHomeMail"

    Player():addMail(mail)
    mission.data.reward.credits = mission.data.reward.credits * 1.5
    reward()
    accomplish()
end

function finishFreighterPiratesDefeated()
    local mail = Mail()
    mail.text = "Thank you! \n\nWe heard you defeated some pirates that were lurking on the trade route. \n\nYou may keep the cargo we gave you.\n\nGreetings,\n\nLieutenant Omask."%_T
    mail.header = "Thank you for defeating the pirates /* Mail Subject */"%_T
    mail.sender = "Lieutenant Omask"%_T
    mail.id = "FreighterPiratesDefeatedMail"

    Player():addMail(mail)
    reward()
    accomplish()
end

function createRiftMail()
    local faction = Faction(mission.data.giver.factionIndex)
    if not faction then return end

    local mail = Mail()
    mail.text = Format("Hello,\n\nit seems that our information was outdated and the trade route now leads through a rift. We apologize for the inconvenience and transferred a compensation for your time to your account.\n\nGreetings,\n%s"%_T, tostring(faction.name))
    mail.header = "New Information /* Mail Subject */"%_T
    mail.sender = Format("%s"%_T, tostring(faction.name))
    mail.id = "Investigate_Missing_Freighters"

    return mail
end


mission.makeBulletin = function(station)
    -- only offer mission at bulletin boards of AI factions
    local faction = Faction(station.factionIndex)
    if not faction then return end
    if not faction.isAIFaction then return end

    x, y = Sector():getCoordinates()
    --check if distance to barrier is bigger than distance traveled in mission  to avoid jumps over barrier
    local distanceToBarrier = math.abs((x * x + y * y) - (Balancing_GetBlockRingMax() * Balancing_GetBlockRingMax()))
    if not x or not y or distanceToBarrier < 25 then return end

    local balancing = Balancing.GetSectorRewardFactor(Sector():getCoordinates())
    reward = {credits = 45000 * balancing, relations = 7500, paymentMessage = "Earned %1% Credits for finding out what happened to the freighters"%_T}
    local materialAmount = round(random():getInt(7000, 8000) / 100) * 100
    MissionUT.addSectorRewardMaterial(x, y, reward, materialAmount)

    local bulletin =
    {
        -- data for the bulletin board
        brief = mission.data.brief,
        title = mission.data.title,
        description = "Looking for help! For some time now, freighters taking a certain trade route have been disappearing. We already contacted the authorities, but nothing ever came up, so we're taking matters into our own hands!\n\nWe need someone brave enough to pose as one of our freighters, and investigate where and how our deliveries have been disappearing."%_T,
        difficulty = "Normal /*difficulty*/"%_T,
        reward = "¢${reward}"%_T,
        script = "missions/investigatemissingfreighters.lua",
        formatArguments = {x = x, y = y, reward = createMonetaryString(reward.credits)},

        -- data that's important for our own mission
        arguments = {{
            giver = station.id,
            location = {x = x, y = y},
            reward = reward,
        }},
    }

    return bulletin
end

