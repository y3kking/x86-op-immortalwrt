package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("structuredmission")
include("callable")

local MissionUT = include("missionutility")


--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Smuggler Boss"%_T
mission.data.title = "The Smuggler Boss"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.description =
{
    "A powerful smuggler boss is rumored to have a Xsotan artifact. Go to a smuggler hideout and try to find out where the smuggler boss is."%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "Find a Smuggler Hideout and talk to the smugglers"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Follow the smuggler's instructions"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Talk to Bottan"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Read the mysterious mail you've just received"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Work with Bottan's enemy"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Take revenge on Bottan and collect his artifact"%_T, bulletPoint = true, fulfilled = false, visible = false},
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
                    if item.script == "data/scripts/systems/teleporterkey8.lua" then
                        accomplish()
                    end
                end

                -- used in phase 4 to see if player does smugglerretaliation
                if item and item.itemType == InventoryItemType.SystemUpgrade then
                    if item.script == "data/scripts/systems/smugglerblocker.lua" and mission.internals.phaseIndex == 4 then
                        setPhase(5)
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
    mail.text = Format("Hello!\n\nI’ve heard about another strange artifact. It seems that a smuggler has somehow got his hands on it. You should find a smuggler’s market and see if you can get the smugglers to trust you. Maybe they’ll lead you to the smuggler boss. He should have the artifact.\n\nGreetings,\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "Find the Smuggler /*Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_Bottan_Mission"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_Bottan_Mission" then
            setPhase(2)
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

-- check if player got the smugglerdelivery script
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true

    local player = Player()
    local scripts = player:getScripts()
    for _, script in pairs(scripts) do
        if script == "data/scripts/player/story/smugglerdelivery.lua" then
            setPhase(3)
        end
        if script == "data/scripts/player/story/smugglerretaliation.lua" then
            setPhase(5)
        end
    end
end
mission.phases[2].playerCallbacks = {}
mission.phases[2].playerCallbacks[1] =
{
    -- player doesn't have it yet - wait until he gets it
    name = "onScriptAdded",
    func = function(playerIndex, scriptIndex, scriptPath)
        local player = Player()
        local script = scriptPath
        if script == "data/scripts/player/story/smugglerdelivery.lua" then
            setPhase(3)
        end

        if script == "data/scripts/player/story/smugglerretaliation.lua" then
            setPhase(5)
        end
    end
}
mission.phases[2].triggers = {
    {
        condition = function() return Sector():getEntitiesByScript("data/scripts/entity/story/smuggler.lua") end,
        callback = function() setPhase(4) end
    }
}
mission.phases[2].showUpdateOnEnd = true

-- tell player to do smugglerdelivery quest
-- check if player met Bottan
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
end
mission.phases[3].triggers = {
    {
        condition = function() return Sector():getEntitiesByScript("data/scripts/entity/story/smuggler.lua") end,
        callback = function() nextPhase() end
    }
}
mission.phases[3].showUpdateOnEnd = true

-- wait for the player to get hyperspace blocker by doing smuggler retaliation quest
mission.phases[4] = {}
mission.phases[4].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
    mission.data.description[4].fulfilled = true
    mission.data.description[5].visible = true

    local player = Player()
    local inventory = player:getInventory()
    local items = inventory:getItems()

    for _, v in pairs(items) do
        if v.item and v.item.itemType == InventoryItemType.SystemUpgrade then
            if v.item.script == "data/scripts/systems/smugglerblocker.lua" then
                nextPhase()
            end
        end
    end
end
mission.phases[4].playerCallbacks = {}
mission.phases[4].playerCallbacks[1] =
{
    name = "onScriptAdded",
    func = function(playerIndex, scriptIndex, scriptPath)
        local player = Player()
        local script = scriptPath
        if script == "data/scripts/player/story/smugglerretaliation.lua" then
            -- update description to tell player to do the new quest
            mission.data.description[5].fulfilled = true
            mission.data.description[6].visible = true
            sync()
        end
    end
}
mission.phases[4].playerCallbacks[2] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_Smuggler_Letter" then
            mission.data.description[6].fulfilled = true
            mission.data.description[7].visible = true -- tell player to do enemy of my enemy quest
            sync()
        end
    end
}

-- accomplish when player collected bottans teleporter key -- done in global phase
mission.phases[5] = {}
mission.phases[5].onBeginServer = function()
    mission.data.description[5].fulfilled = true
    mission.data.description[6].fulfilled = true
    mission.data.description[7].fulfilled = true
    mission.data.description[8].visible = true
end
