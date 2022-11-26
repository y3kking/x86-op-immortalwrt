package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("structuredmission")
include("callable")

-- mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Trading Guild"%_T
mission.data.title = "The Trading Guild"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.location = {}

mission.data.description =
{
    "Buy an artifact from a Mobile Merchant"%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "Buy a Trade Guild Beacon from an Equipment Dock"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Activate the Trade Guild Beacon"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Buy the Artifact from the Mobile Merchant"%_T, bulletPoint = true, fulfilled = false, visible = false},
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

                if item and item.itemType == InventoryItemType.UsableItem then
                    if item:getValue("subtype") == "EquipmentMerchantCaller" and mission.internals.phaseIndex == 2 then
                        setPhase(3)
                    end
                end

                if item and item.itemType == InventoryItemType.SystemUpgrade then
                    if item.script == "data/scripts/systems/teleporterkey4.lua" then
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
    mail.text = Format("Hello!\n\nThere are merchants from the Trading Guilds that might sell one of the artifacts you are looking for. It seems that they have to be called in a special way. Look out for a way to call them and you should be able purchase an artifact.\n\nGreetings,\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "Trading Guild /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_Buy_Mission"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_Buy_Mission" then
            nextPhase()
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

-- checks if player has equipmentmerchant caller
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    -- if he already has it immediately go on
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true

    local player = Player()
    local inventory = player:getInventory()
    local items = inventory:getItems()

    for k, v in pairs(items) do
        if v.item and v.item.itemType == InventoryItemType.UsableItem then
            if v.item:getValue("subtype") == "EquipmentMerchantCaller" then
                nextPhase()
            end
        end
    end
end
mission.phases[2].showUpdateOnEnd = true

-- checks if equipmentmerchant is present
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
end
mission.phases[3].updateServer = function(timestep)
    -- poll needed because ship value is set after creation, so onEntityCreated callback doesn't work
    local ships = {Sector():getEntitiesByType(EntityType.Ship)}
    for _, ship in pairs(ships) do
        if ship:getValue("called_equipment_merchant") then
            nextPhase()
        end
    end
end

-- checks if player has the xsotan artifact 4 - done by global phase
mission.phases[4] = {}
mission.phases[4].onBeginServer = function()
    mission.data.description[4].fulfilled = true
    mission.data.description[5].visible = true
end
