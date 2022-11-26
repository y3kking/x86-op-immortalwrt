package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("stringutility")
include("structuredmission")
include("callable")
include("randomext")

local AI = include("story/ai")
local MissionUT = include("missionutility")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Experiment"%_T
mission.data.title = "The Experiment"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.location = {}

mission.data.description =
{
    "The Adventurer has heard about another Xsotan artifact."%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "Ask around for information on the location of the AI"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Go to sector"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Destroy the AI and collect its artifact"%_T, bulletPoint = true, fulfilled = false, visible = false},
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
                    if item.script == "data/scripts/systems/teleporterkey6.lua" then
                        accomplish()
                    end
                end
            end
        end
    }
}

-- initial phase, sends a mail and continues on read
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    local player = Player()
    local mail = Mail()
    mail.text = Format("Hello! \n\nI've heard about a failed experiment. A long time ago somebody attempted to build an automated spaceship that fights Xsotan. People call it the AI. Apparently Xsotan technology was used when constructing it. You should check it out.\n\nGreetings,\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "A Failed Experiment /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_AI_Mission"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_AI_Mission" then
            nextPhase()
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

--freighters tell player about the location of the AI
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true
    -- go find a hint on where
    determineAILocation()
end
mission.phases[2].onSectorEntered = function()
    if onServer() and mission.data.custom.location.x == nil then
        determineAILocation()
    end
end
mission.phases[2].onStartDialog = function(entityId)
    local entity = Entity(entityId)

    if entity and entity:hasScript("data/scripts/entity/dialogs/storyhints.lua") then
        ScriptUI(entityId):addDialogOption("Have you heard about the Xsotan fighting machine?"%_t, "onAIHintAsked")
    end
end
mission.phases[2].showUpdateOnEnd = true

-- when player reached location, AI is spawned
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    mission.data.description[4].fulfilled = false
    mission.data.description[4].visible = true
    -- now you know where to go - go there
    mission.data.description[4].text = "Go to sector (${x}:${y})"%_T
    mission.data.description[4].arguments = {x = mission.data.location.x, y = mission.data.location.y}
end
mission.phases[3].onTargetLocationEntered = function(x, y)
    if onServer() then
        AI.spawn(x, y)
        nextPhase()
    end
end
mission.phases[3].onTargetLocationLeft = function()
    mission.data.location = {}
    mission.data.description[3].fulfilled = false
    mission.data.description[4].visible = false
    setPhase(2)
end
mission.phases[3].showUpdateOnEnd = true

-- player kills AI and collects artifact
mission.phases[4] = {}
mission.phases[4].onBeginServer = function()
    mission.data.description[4].fulfilled = true
    mission.data.description[5].visible = true
end
mission.phases[4].onRestore = function()
    if onServer() then
        if MissionUT.playerInTargetSector(Player(), mission.data.location) then
            local ai = Sector():getEntitiesByScript("entity/story/aibehaviour.lua")
            if not ai then
                AI.spawn(Sector():getCoordinates())
            end
        else
            mission.data.location = {}
            mission.data.description[3].fulfilled = false
            mission.data.description[4].visible = false
            setPhase(2)
        end
    end
end
mission.phases[4].onTargetLocationLeft = function()
    mission.data.location = {}
    mission.data.description[3].fulfilled = false
    mission.data.description[4].visible = false
    setPhase(2)
end


--helper functions
-------------------------------------------------------

-- calculates the spawn location of AI
function determineAILocation()
    local location = {Sector():getCoordinates()}
    local distance2 = location[1]*location[1] + location[2]*location[2]
    -- don't calculate sector, if player isn't in correct region
    if distance2 < 240*240 or distance2 > 340*340 then return end

    local x, y = MissionUT.getSector(location[1], location[2], 1, 20, false, false, false, false)
    if not x and not y then setPhase(2) return end -- if we didn't find a sector retry
    mission.data.custom.location = {x = x, y = y}
    sync()
end

local hintAskedOnEnd = makeDialogServerCallback("hintAskedOnEnd", 2, function()
    -- player now knows location - so show it on map
    mission.data.location.x = mission.data.custom.location.x
    mission.data.location.y = mission.data.custom.location.y
    setPhase(3)
end)

function getExactLocationPossible()
    local location = {Sector():getCoordinates()}
    local distance2 = location[1]*location[1] + location[2]*location[2]
    -- don't give hint if player is outside the AI spawn region
    if distance2 < 240*240 or distance2 > 340*340 then return false end
    return true
end

function onAIHintAsked(entityId)
    if getExactLocationPossible() then
        if mission.data.custom.location.x == nil then
            local dialogNo = {}
            dialogNo.text = "No, I'm sorry, I can't help you there. You should ask someone else."%_t
            dialogNo.answers = {
                {answer = "Okay, thanks."%_t}
            }
            ScriptUI(entityId):showDialog(dialogNo)
        else
            local dialogYes = {}
            dialogYes.text = string.format("I've heard about it. I believe it was last seen in sector (${x}:${y}). But it's supposed to be really dangerous, are you sure you want to go there?"%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
            dialogYes.answers = {
                {answer = "I know what I'm doing."%_t}
            }
            dialogYes.onEnd = hintAskedOnEnd

            ScriptUI(entityId):showDialog(dialogYes, false)
        end
    else
        local dialogFurtherOut = {}
        dialogFurtherOut.text = "Sorry, I can't help you there. Maybe you should try asking somebody closer to the edge of the galaxy."%_t
        dialogFurtherOut.answers = {
            {answer = "Thanks for your help."%_t}
        }

        local dialogFurtherIn = {}
        dialogFurtherIn.text = "Sorry, I don't know anything about that. Try asking somebody closer to the center of the galaxy."%_t
        dialogFurtherIn.answers = {
            {answer = "Thanks for your help."%_t}
        }

        local location = {Sector():getCoordinates()}
        local distance2 = location[1]*location[1] + location[2]*location[2]

        if distance2 < 240*240 then
            ScriptUI(entityId):showDialog(dialogFurtherOut)
        elseif distance2 > 340*340 then
            ScriptUI(entityId):showDialog(dialogFurtherIn)
        end
    end
end

