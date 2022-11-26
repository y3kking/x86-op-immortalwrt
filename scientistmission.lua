package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("structuredmission")
include("callable")
include("randomext")
local MissionUT = include("missionutility")
local SectorSpecifics = include ("sectorspecifics")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Scientist"%_T
mission.data.title = "The Scientist"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.visitedSatelliteSectors = {}
mission.data.custom.location = {}

mission.data.description =
{
    "The Adventurer heard rumors of strange satellites that seem to be harmful. He asked you to destroy them."%_T,
    {text = "Move towards the Barrier and wait for more information"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Find and destroy the research satellite"%_T, bulletPoint = true, fulfilled = false, visible = false}, -- this is updated later with a location
    {text = "Find and destroy more research satellites. Ask around for more information"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Destroy the Mobile Energy Lab and collect its artifact"%_t, bulletPoint = true, fulfilled = false, visible = false}
}

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
                    if item.script == "data/scripts/systems/teleporterkey7.lua" then
                        accomplish()
                    end
                end
            end
        end
    }
}

-- Helper phase that simply makes sure we're in the correct region (Between 150 and 240)
-- It wouldn't make sense to send the player after satellites, if he won't find any bc he is in the wrong part of the galaxy
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    mission.data.description[2].visible = true
    determineTargetCoords()
end
mission.phases[1].onSectorEntered = function()
    if onClient() then return end
    determineTargetCoords()
end

-- Send player mail with location of a satellite
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true

    local player = Player()
    local mail = Mail()
    mail.text = Format("Hello!\n\nHave you seen this mail that’s going round lately?\nWe have to help. I know, I know, it looks like total spam, but I think he’s onto something. Will you help, too?\n\nGreetings,\n%1%\n\nQuote:\n\"Hello fellow galaxy dwellers,\nI have extremely concerning news to share with you. I just can’t not say something. We have to save the people! I’m a former member of the M.A.D. Association and they’re trying to reach galaxy domination. We have to stop them immediately!\n\nI’ve seen them do terrible experiments on all life-forms. Trying to create a super-being capable of destroying every living thing in the galaxy. They’re actively using Xsotan technology in order to find a weapon for mass destruction!!\n\nIf you’re a good person, you have to act now! Help us protect the galaxy! Destroy all of the M.A.D. Association’s research satellites!\n\nA concerned citizen\"\n"%_T, MissionUT.getAdventurerName())
    mail.header = "Fwd: Re: Fwd: M.A.D. Science Association /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_MAD_Mission"
    player:addMail(mail)
end
mission.phases[2].playerCallbacks =
{
    {
        name = "onMailRead",
        func = function(playerIndex, mailIndex, mailId)
            if mailId == "Story_MAD_Mission" then
                setPhase(3)
            end
        end
    }
}
mission.phases[2].showUpdateOnEnd = true

-- have player destroy the designated satellite
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    if mission.data.custom.location.x == nil then
        mission.data.description[4] = {text = "Ask around for the location of a satellite."%_T, bulletPoint = true, visible = true}
        return
    end
    mission.data.location = mission.data.custom.location -- now show location on map
    mission.data.description[4] = {text = "Destroy the satellite in sector (${xCoord}:${yCoord})"%_T, arguments = {xCoord = mission.data.custom.location.x, yCoord = mission.data.custom.location.y}, bulletPoint = true}
    -- we redo the mission in parts, so we update description to not be fulfilled
    mission.data.description[5].fulfilled = false
    mission.data.description[6].fulfilled = false
end
mission.phases[3].onTargetLocationEntered = function(entityId)
    if onServer() then
        local sector = Sector()
        local satelliteCoords = {sector:getCoordinates()}
        table.insert(mission.data.custom.visitedSatelliteSectors, satelliteCoords)
        if satelliteCoords[1] == mission.data.location.x and satelliteCoords[2] == mission.data.location.y then
            -- check if satellite hasn't been destroyed by someone else
            local satellite = sector:getEntitiesByScript("data/scripts/entity/story/researchsatellite.lua")
            if not satellite then
                mission.data.location = {}
                determineTargetCoords()
                mission.data.description[4].fulfilled = true
                mission.data.description[5] = {text = "The satellite seems to be gone. Ask around for the location of another satellite"%_T, bulletPoint = true, visible = true}
                sync()
            end
        end
    end
end
mission.phases[3].onStartDialog = function(entityId)
    local entity = Entity(entityId)
    if entity and entity:hasScript("data/scripts/entity/dialogs/storyhints.lua") then
        ScriptUI(entityId):addDialogOption("Do you know the location of a research satellite?"%_t, "onSatelliteHintAsked")
    end
end
mission.phases[3].onEntityDestroyed = function(index, lastDamageInflictor)
    if onServer() then
        local destroyed = Entity(index)
        if destroyed:hasScript("data/scripts/entity/story/researchsatellite.lua") then
            local satelliteCoords = {Sector():getCoordinates()}
            table.insert(mission.data.custom.visitedSatelliteSectors, satelliteCoords)
            if satelliteCoords[1] == mission.data.location.x and satelliteCoords[2] == mission.data.location.y then
                -- remove map marker of destroyed satellite if it was the one we pointed out
                mission.data.location = {}
                mission.data.description[4].fulfilled = true
                mission.data.description[5] = {text = "Find and destroy more research satellites. Ask around for more information"%_T, bulletPoint = true, visible = true}
                determineTargetCoords() -- and get some new coordinates that the player can ask for
                sync()
            end
        end
    end
end
mission.phases[3].sectorCallbacks =
{
    {
        name = "onScientistSpawned",
        func = function()
            if onServer() then
                nextPhase()
            end
        end
    }
}
mission.phases[3].showUpdateOnEnd = true


-- player found scientist - kill it, kill it with fire
mission.phases[4] = {}
mission.phases[4].onBeginServer = function()
    mission.data.description[5].fulfilled = true
    mission.data.description[6].visible = true
end
mission.phases[4].onSectorLeft = function()
    -- player lost or ran without collecting the upgrade - he should have another chance
    if onServer() then
        setPhase(3)
    end
end

function determineTargetCoords()
    local x, y = Sector():getCoordinates()
    local distance2 = x * x + y * y

    if distance2 > 150 * 150 and distance2 < 240 * 240 then
        -- we're in correct region => find sector with research satellite

        -- performance optimization to not create internal variables all the time
        -- we also use a second instance to check for content to be sure to not mess up any internals of findSector() down below
        local tmpSpecs = SectorSpecifics(x, y, GameSeed())

        local test = function(x, y, regular, offgrid, blocked, home, dust, factionIndex, centralArea)
            if not offgrid then return false end -- we know that the sector we're looking for is an offgrid sector
            if blocked then return false end

            for _, oldCoords in pairs(mission.data.custom.visitedSatelliteSectors) do
                if oldCoords[1] == x and oldCoords[2] == y then
                    return false
                end
            end

            tmpSpecs:initialize(x, y, GameSeed())
            if tmpSpecs.generationTemplate and tmpSpecs.generationTemplate.path == "sectors/researchsatellite" then
                return true
            end
        end

        local specs = SectorSpecifics()
        local target = specs:findSector(random(), x, y, test, 30, 1)

        -- if we didn't find a sector => abort; we'll retry next time on sector entered
        if not target then return end

        mission.data.custom.location = {x = target.x, y = target.y}
        if mission.internals.phaseIndex == 1 then
            setPhase(2)
        end
    end
end
callable(nil, "determineTargetCoords")

local onSatelliteHintEnd = makeDialogServerCallback("onSatelliteHintEnd", 3, function()
    -- player now knows location - so show it on map
    mission.data.location = {}
    mission.data.location.x = mission.data.custom.location.x
    mission.data.location.y = mission.data.custom.location.y
    -- also show location in missionlog
    mission.data.description[4].fulfilled = true
    mission.data.description[5] = {text = "Destroy the satellite in sector (${xCoord}:${yCoord})"%_T, arguments = {xCoord = mission.data.custom.location.x, yCoord = mission.data.custom.location.y}, bulletPoint = true, visible = true}
    sync()
end)

local onNoLocationReceived = makeDialogServerCallback("onNoLocationReceived", 3, function()
    -- just calculate the location again, you only get to here if the location was missing for some reason
    determineTargetCoords()
    sync()
end)

function onSatelliteHintAsked(entityId)
    if mission.data.custom.location.x == nil then
        local dialog0 = {}
        dialog0.text = "I'm sorry, but I have no idea what you are talking about. You should ask someone else."%_t
        dialog0.answers = {{answer = "Okay, thanks."%_t}}
        dialog0.onEnd = onNoLocationReceived

        ScriptUI(entityId):showDialog(dialog0)
    else
        local dialogOptions = {}

        local dialog1 = {}
        local dialog1_followUp = {}
        dialog1.text = "You mean those things that spout radio messages on some kind of energy experiment?"%_t
        dialog1.answers = {
            {answer = "Yes exactly."%_t, followUp = dialog1_followUp}
        }
        dialog1_followUp.text = string.format("Yeah, I've seen one. Wait, let me look where that was..\n\nAh here it is. It was in sector (${x}:${y})."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialog1_followUp.answers = {{answer = "Thank you for your help!"%_t}}
        dialog1.onEnd = onSatelliteHintEnd
        table.insert(dialogOptions, dialog1)

        local dialog2 = {}
        local dialog2_followUp = {}
        dialog2.text = "Why do you care?"%_t
        dialog2.answers = {
            {answer = "I want to destroy them."%_t, followUp = dialog2_followUp}
        }
        dialog2_followUp.text = string.format("Well, in that case... I saw one in sector (${x}:${y})."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialog2_followUp.answers = {{answer = "Thank you for your help!"%_t}}
        dialog2.onEnd = onSatelliteHintEnd
        table.insert(dialogOptions, dialog2)

        local dialog3 = {}
        local dialog3_followUp = {}
        dialog3.text = "Why would I tell you?"%_t
        dialog3.answers = {
            {answer = "Pretty please?"%_t, followUp = dialog3_followUp}
        }
        dialog3_followUp.text = string.format("All right. I heard of one in sector (${x}:${y})."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialog3_followUp.answers = {{answer = "Thank you for your help!"%_t}}
        dialog3.onEnd = onSatelliteHintEnd
        table.insert(dialogOptions, dialog3)

        local dialog4 = {}
        dialog4.text = string.format("I'm not sure. Somebody told me about a strange satellite in sector (${x}:${y}), but I don't know if that is what you're looking for."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialog4.answers = {{answer = "Thank you for your help!"%_t}}
        dialog4.onEnd = onSatelliteHintEnd
        table.insert(dialogOptions, dialog4)

        local dialog5 = {}
        dialog5.text = string.format("If I were you I would check out sector (${x}:${y})."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialog5.answers = {{answer = "Thank you for your help!"%_t}}
        dialog5.onEnd = onSatelliteHintEnd
        table.insert(dialogOptions, dialog5)

        local dialog6 = {}
        dialog6.text = string.format("Will you leave me alone if I tell you to look in sector (${x}:${y})?"%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialog6.answers = {{answer = "Thank you for your help!"%_t}}
        dialog6.onEnd = onSatelliteHintEnd
        table.insert(dialogOptions, dialog6)

        local dialog7 = {}
        dialog7.text = string.format("One of them is in sector (${x}:${y})."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
        dialog7.answers = {{answer = "Thank you for your help!"%_t}}
        dialog7.onEnd = onSatelliteHintEnd
        table.insert(dialogOptions, dialog7)

        local idString = (Entity(entityId).id.string)
        local number = string.match(idString, "%d+")
        local numberOfTexts = #dialogOptions
        local textNumber = number % numberOfTexts
        if textNumber == 0 then textNumber = 1 end

        ScriptUI(entityId):showDialog(dialogOptions[textNumber], false)
    end
end


