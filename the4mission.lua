package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("structuredmission")
local MissionUT = include("missionutility")
local The4 = include("story/the4")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Brotherhood"%_T
mission.data.title = "The Brotherhood"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.location = {}
mission.data.custom.acceptedUpgrades = 0

mission.data.description =
{
    "Find the Brotherhood"%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "Find a bulletin about the Brotherhood"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Find the Brotherhood"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Defeat the leaders of the Brotherhood and get their artifact"%_T, bulletPoint = true, fulfilled = false, visible = false},
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
                    if item.script == "data/scripts/systems/teleporterkey5.lua" then
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
    local player = Player()
    local mail = Mail()
    mail.text = Format("Hey you,\n\nI heard about a group of people who also want to cross the Barrier. They are looking for Xsotan artifacts as well. They have posted on Bulletin Boards of stations. Maybe you could find them and we can all work together to overcome the Barrier.\n\nGreetings,\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "The Brotherhood /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Brotherhood_Mission_Mail"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Brotherhood_Mission_Mail" then
            nextPhase()
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

-- checks if player has the artifactdelivery script
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true

    local player = Player()
    if player:hasScript("data/scripts/player/story/artifactdelivery.lua") then
        nextPhase()
    end
end
mission.phases[2].playerCallbacks = {}
mission.phases[2].playerCallbacks[1] =
{
    name = "onScriptAdded",
    func = function(playerIndex, scriptIndex, scriptPath)
        local player = Player()
        local script = scriptPath
        if script == "data/scripts/player/story/artifactdelivery.lua" then
            nextPhase()
        end
    end
}
mission.phases[2].showUpdateOnEnd = true

-- checks if player goes to sector where the 4 will be
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true

    local ok, x, y = Player():invokeFunction("artifactdelivery", "getMissionLocation")
    mission.data.location = {x = x, y = y}
end
mission.phases[3].onTargetLocationEntered = function(x, y)
    nextPhase()
end

-- checks if the player called the 4
mission.phases[4] = {}
-- if player leaves sector, phase is set back to remind player to go to target sector
mission.phases[4].onSectorLeft = function(x, y)
    setPhase(3)
end
mission.phases[4].sectorCallbacks =
{
    {
        name = "onThe4Spawned",
        func = function()
            if onServer() then
                nextPhase()
            end
        end
    }
}

-- checks if player has the xsotan artifact 5
mission.phases[5] = {}
mission.phases[5].onBeginServer = function()
    mission.data.description[4].fulfilled = true
    mission.data.description[5].visible = true
end
