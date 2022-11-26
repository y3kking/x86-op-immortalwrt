package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("structuredmission")

local MissionUT = include("missionutility")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Groundbreaking Research"%_T
mission.data.title = "The Groundbreaking Research"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.location = {}
mission.data.custom.acceptedUpgrades = 0

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
                    if item.script == "data/scripts/systems/teleporterkey2.lua" then
                        accomplish()
                    end
                end

                if mission.internals.phaseIndex == 2 and checkEnoughLegendaryUpgrades() then
                    setPhase(3)
                end
            end
        end
    }
}

mission.data.description =
{
    "Research an artifact"%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "Collect three legendary subsystems that are not a Xsotan Artifact"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Use three legendary subsystems as input in a Research Station"%_T, bulletPoint = true, fulfilled = false, visible = false},
}

-- sends mission mail and continues on read mail
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    local player = Player()
    local mail = Mail()
    mail.text = Format("Hello!\n\nHave you ever used a research station? Their AIs are trained with everything that floats around. We should try to see if we can get a Xsotan artifact out of it, everybody for himself. It should be very very rare so we should use only legendary subsystems to research it.\n\nGreetings,\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "Research /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Research_Mission_Mail"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Research_Mission_Mail" then
            nextPhase()
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

-- checks if player has enough legendary upgrades to research xsotan artifact (done in global)
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true
    if checkEnoughLegendaryUpgrades() then
        nextPhase()
    end
end
mission.phases[2].showUpdateOnEnd = true

-- checks if player has the Xsotan artifact 4 - done by global phase
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
end


function checkEnoughLegendaryUpgrades()
    local player = Player()
    local inventory = player:getInventory()
    local upgrades = inventory:getItemsByType(InventoryItemType.SystemUpgrade)

    local acceptedUpgrades = 0
    for _, p in pairs(upgrades) do
        local upgrade = p.item
        local amount = p.amount
        if upgrade.rarity.type == RarityType.Legendary then
            if not string.match(upgrade.script, "systems/teleporterkey") then
                acceptedUpgrades = acceptedUpgrades + amount
            end
        end
    end

    mission.data.custom.acceptedUpgrades = acceptedUpgrades

    if mission.data.custom.acceptedUpgrades >= 3 then
        return true
    else
        return false
    end
end
