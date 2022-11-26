package.path = package.path .. ";data/scripts/lib/?.lua"

include ("randomext")
include ("utility")
include ("mission")
include ("stringutility")

local Dialog = include ("dialogutility")

function initialize(dummy)

    if onClient() then
        sync()
    else
        Player():registerCallback("onItemAdded", "onItemAdded")

        if not dummy then return end

        missionData.justStarted = true
        missionData.title = "Getting Technical"%_t
        missionData.brief = "Getting Technical"%_t
        missionData.icon = "data/textures/icons/story-mission.png"
        missionData.priority = 10
        missionData.description = "Collect and research Xsotan technology to use against the Wormhole Guardian."%_t

    end
end

function onItemAdded(index, amount, before)
    if amount >= 1 then

        local item = Player():getInventory():find(index)
        if item and item.itemType == InventoryItemType.SystemUpgrade then
            if item.script:match("systems/wormholeopener.lua") then
                if item.rarity == Rarity(RarityType.Legendary) then
                    showMissionAccomplished()
                    terminate()
                end
            end
        end

    end
end

function updateDescription()

end
