package.path = package.path .. ";data/scripts/lib/?.lua"

include("goods")
include("structuredmission")
include("stringutility")
include("callable")
local Smuggler = include("story/smuggler")
local MissionUT = include("missionutility")

-- mission.tracing = true

-- data
mission.data.title = "Enemy of my Enemy"%_T
mission.data.brief = "Enemy of my Enemy"%_T

mission.data.autoTrackMission = true

mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10

mission.data.description = {}
mission.data.description[1] = "Someone unknown has contacted you. Read his mail to find out what he wants."%_t
mission.data.location = {}

-- custom
mission.data.custom.ingredients = {}
mission.data.custom.descriptionUpdate = "The mysterious figure turned out to be Bottan's ex chief engineer. He wants to take revenge and asked you to collect parts so he can build a ray that destroys Bottan's hyperspace drive."%_t

-- phases
mission.globalPhase = {}
mission.globalPhase.onTargetLocationEntered = function(x, y)
    if onServer() then
        local engineer = Smuggler.spawnEngineer(x, y)
        if not engineer then return end
        MissionUT.bindToMission(engineer)
    end
end
mission.globalPhase.onRestore = function(data)
    if data.data then return end -- already new version

    -- conversion of old versions to new ones
    if not data.data then
        mission.data = data

        -- try to write internals
        mission.data.internals = {}
        mission.data.internals.timePassed = 0
        mission.data.internals.fulfilled = data.fulfilled
        mission.data.internals.phaseIndex = data.stage
        mission.data.internals.justStarted = data.justStarted
    end

    mission.data.custom = {}
    mission.data.custom.ingredients = mission.data.goods
    mission.data.custom.interaction = mission.data.interactions or {}


    -- stage and description
    mission.data.description = {}
    if data.stage == 0 then
        mission.data.description[1] = "Someone unknown has contacted you. Read his mail to find out what he wants."%_t
        mission.data.internals.phaseIndex = 1
        setPhase(1)
    elseif data.stage == 1 then
        if not playerHasOverloader() then
            -- phase 2
            mission.data.description[1] = "The mysterious figure turned out to be Bottan's ex chief engineer. He wants to take revenge and asked you to collect parts so he can build a ray that destroys Bottan's hyperspace drive."%_t
            mission.data.internals.phaseIndex = 2
            setPhase(2)
        else
            -- phase 3
            mission.data.description[1] = "The mysterious figure turned out to be Bottan's ex chief engineer. He wants to take revenge and asked you to collect parts so he can build a ray that destroys Bottan's hyperspace drive."%_t
            mission.data.description[2] = "The engineer gave you a hyperspace overloader, use it to jam Bottan's hyperspace engine and defeat him."%_T
            mission.data.description[3] = {text = "The engineer will stick around for a bit. Go back to sector (${x}:${y}) if you need help."%_T, arguments = {x = mission.data.location.x, y = mission.data.location.y}}
            mission.data.internals.phaseIndex = 3
            setPhase(3)
        end
    end
end

-- first phase is placeholder and simply waits for player to go to target sector and talk to engineer
mission.phases[1] = {}
mission.phases[1].noBossEncountersTargetSector = true
mission.phases[1].noPlayerEvenetsTargetSector = true
mission.phases[1].onBeginClient = function()
    local currentlyTracked = getTrackedMissionScriptIndex()
    if not currentlyTracked then
        setTrackThisMission()
        return
    end

    -- check if our parent script or one of the other parts of bottan story is currently tracked
    -- we can overwrite those
    for index, path in pairs(Player():getScripts()) do
        if index ~= currentlyTracked then goto continue end

        if path == "data/scripts/player/story/bottanmission.lua" then
            setTrackThisMission()
            break
        elseif path == "data/scripts/player/story/smugglerdelivery.lua" then
            setTrackThisMission()
            break
        elseif path == "data/scripts/player/story/smugglerletter.lua" then
            setTrackThisMission()
            break
        end

        ::continue::
    end
end
mission.phases[1].playerCallbacks = {
    {
        name = "onMailRead",
        func = function(playerIndex, mailIndex, mailId)
            if mailId == "Story_Smuggler_Letter" then
                mission.data.description[1] = mission.data.custom.descriptionUpdate
                sync()
            end
        end
    }
}

-- phase 2: Player got the ingredient list from the engineer -> wait for him to deliver
mission.phases[2] = {}
mission.phases[2].onBegin = function()
    updateDescription()

    local ship = Player().craft
    if not ship then return end
    ship:registerCallback("onCargoChanged", "updateDescription")
end
mission.phases[2].onStartDialog = function(entityId)
    local sector = Sector()
    local x, y = sector:getCoordinates()
    if x ~= mission.data.custom.interaction.x or y ~= mission.data.custom.interaction.y then return end

    local engineer = sector:getEntitiesByScript("smugglerengineer.lua")
    if engineer.id == entityId then
        local scriptUI = ScriptUI(engineer)
        if not scriptUI then return end

        scriptUI:addDialogOption("I have your goods. /*smugglerretaliation*/"%_t, "onDeliver")
        updateDescription()
    end
end
mission.phases[2].playerCallbacks = {}
mission.phases[2].playerCallbacks[1] = {
    name = "onShipChanged",
    func = function()
        local ship = Player().craft
        if not ship then return end
        ship:registerCallback("onCargoChanged", "updateDescription")
        updateDescription() -- update immediately as well
    end
}
mission.phases[2].onRestore = function()
    local ship = Player().craft
    if not ship then return end
    ship:registerCallback("onCargoChanged", "updateDescription")

    if onServer() and atTargetLocation() then
        local x, y = Sector():getCoordinates()
        Smuggler.spawnEngineer(x, y)
    end
end
mission.phases[2].noBossEncountersTargetSector = true
mission.phases[2].noPlayerEvenetsTargetSector = true

-- phase 3: Player delivered -> Engineer sends player to kill Bottan
--          Engineer should have fallback dialog option in case player lost hyper blocker upgrade
mission.phases[3] = {}
mission.phases[3].onBegin = function()

    -- remove ingredient list from description
    local numBullets = #mission.data.custom.ingredients

    for i = 2, numBullets + 2 do
        mission.data.description[i] = ""
    end

    mission.data.description[2] = "The engineer gave you a hyperspace overloader, use it to jam Bottan's hyperspace engine and defeat him."%_T
    mission.data.description[3] = {text = "The engineer will stick around for a bit. Go back to sector (${x}:${y}) if you need help."%_T, arguments = {x = mission.data.location.x, y = mission.data.location.y}}
end
mission.phases[3].onStartDialog = function(entityId)
    local interaction = mission.data.custom.interaction

    local sector = Sector()
    local x, y = sector:getCoordinates()
    if interaction and x ~= interaction.x or y ~= interaction.y then return end

    local engineer = sector:getEntitiesByScript("smugglerengineer.lua")
    if engineer.id == entityId then
        local scriptUI = ScriptUI(engineer)
        if not scriptUI then return end

        scriptUI:addDialogOption("I might have misplaced the Overloader.."%_t, "onLostBlocker")
        scriptUI:addDialogOption("How do I find that guy Bottan again?"%_t, "onHowFindBottan")
    end
end
mission.phases[3].onRestore = function()
    if onServer() and atTargetLocation() then
        local x, y = Sector():getCoordinates()
        Smuggler.spawnEngineer(x, y)
    end
end
mission.phases[3].sectorCallbacks = {
    {
        name = "onDestroyed",
        func = function(index)
            local entity = Sector():getEntitiesByScript("smuggler.lua")
            if entity and entity.id == index then
                onBottanDestroyed()
            end
        end
    }
}
mission.phases[3].noBossEncountersTargetSector = true
mission.phases[3].noPlayerEvenetsTargetSector = true


function setLocation(x, y)
    mission.data.location = {x = x, y = y}
end

function startCollecting(goods, entityIndex)
    if mission.currentPhase == mission.phases[1] then
        -- set ingredient list and move player to phase 2
        mission.data.custom.ingredients = goods
        mission.data.custom.interaction = {x = mission.data.location.x, y = mission.data.location.y, entity = entityIndex.string}
        setPhase(2)
    end
end

function updateDescription(objectIndex, delta, good)

    if mission.internals.phaseIndex ~= 2 then return end

    local bulletPoint = 2
    local craft = Player().craft
    if not craft then return end

    local cargos = craft:getCargos()

    for _, ingredient in pairs(mission.data.custom.ingredients or {}) do

        local have = 0
        local needed = ingredient.amount
        bulletPoint = bulletPoint + 1
        local good = goods[ingredient.name]:good()

        for good, amount in pairs(cargos) do
            if ingredient.name == good.name then
                have = amount
                break
            end
        end
        mission.data.description[bulletPoint] = {text = "${good}: ${have}/${needed}"%_T, arguments = {good = good.name, have = have, needed = needed}, bulletPoint = true, fulfilled = false}
    end
    sync()
end

function onDeliver(entityId)

    local needs = findMissingGoods(Player().craft)

    local dialog = {}
    if #needs > 0 then
        local missing = enumerate(needs, function(g) return g.amount .. " " .. g.name end)

        dialog.text = string.format("I'm afraid you don't. My scanners show me that you're still missing %s."%_t, missing)
    else
        dialog.text = "Very good. I'll build the system. It'll be done in no time."%_t
        dialog.onEnd = "giveSystem"
        dialog.followUp = {text = "Here you go. With this built into your ship you should be able to destroy Bottan's hyperspace drive."%_t, followUp = {
        text = "But keep in mind that this system might get destroyed when you use it. It's very possible that you have one shot and that's it."%_t}}
    end

    ScriptUI(entityId):showDialog(dialog)
end

function findMissingGoods(ship)
    local needs = {}
    for _, g in pairs(mission.data.custom.ingredients) do
        local has = ship:getCargoAmount(g.name)

        if has < g.amount then
            local good = goods[g.name]
            good = good:good()
            table.insert(needs, {name = good:displayName(g.amount - has), amount = g.amount - has})
        end
    end

    return needs
end

function giveSystem()
    if onClient() then
        invokeServerFunction("giveSystem")
        return
    end

    -- go to phase 3
    setPhase(3)

    local player = Player(callingPlayer)
    local ship = player.craft

    -- recheck goods before taking them
    local needs = findMissingGoods(ship)
    if #needs > 0 then return end

    for _, g in pairs(mission.data.custom.ingredients) do
        -- remove goods
        ship:removeCargo(g.name, g.amount)
    end

    player:getInventory():addOrDrop(SystemUpgradeTemplate("data/scripts/systems/smugglerblocker.lua", Rarity(RarityType.Exotic), Seed(0)))
end
callable(nil, "giveSystem")

function onLostBlocker()
    if onServer() then invokeClientFunction(Player(), "onLostBlocker") return end

    local dialog = {}
    local badjoke = {}
    local reset = {}

    dialog.text = "That's not good, but oh well. If you give me new ingredients I can craft another one."%_t
    dialog.answers = {
        {answer = "Sorry, bad joke. I still have it."%_t, followUp = badjoke},
        {answer = "Thank you. You're really helping me out here."%_t, followUp = reset}
    }

    badjoke.text = "Haha... Don't do that again."%_t

    reset.text = "Sure, everything to get my revenge.\n\nI'll sent the ingredients list to your ship again. Come back once you have them."%_t
    reset.onEnd = "resetToIngredientsStage"

    local sector = Sector()
    local engineer = sector:getEntitiesByScript("story/smugglerengineer")
    if not engineer then return end
    local scriptUI = ScriptUI(engineer)
    if not scriptUI then return end

    scriptUI:showDialog(dialog)
end

function onHowFindBottan()
    if onServer() then invokeClientFunction(Player(), "onHowFindBottan") return end

    local dialog = {}

    dialog.text = "Easiest way is probably through his smuggling network. Just talk to one of his smuggler friends that hide near Smuggler's Markets.\n\nThey're usually very eager to find someone to transport illegal goods to Bottan."%_t
    dialog.answers = {{answer = "I will try that."%_t}}

    local sector = Sector()
    local engineer = sector:getEntitiesByScript("story/smugglerengineer")
    if not engineer then return end
    local scriptUI = ScriptUI(engineer)
    if not scriptUI then return end

    scriptUI:showDialog(dialog)
end

function resetToIngredientsStage()
    if onClient() then invokeServerFunction("resetToIngredientsStage") return end
    setPhase(2)
end
callable(nil, "resetToIngredientsStage")

function onBottanDestroyed()
    -- we don't care at which point the player destroyed Bottan, the quest is finished anyway
    accomplish()
end
callable(nil, "onBottanDestroyed")

function playerHasOverloader()
    local player = Player()

    -- check inventory
    local inventory = player:getInventory()
    local upgrades = inventory:getItemsByType(InventoryItemType.SystemUpgrade)
    for _, u in pairs(upgrades) do
        local upgrade = u.item
        if upgrade.script == "data/scripts/systems/smugglerblocker.lua" then
            return true
        end
    end

    -- check all ships, if the player has it somewhere we assume he was on his way to kill bottan
    local shipNames = {player:getShipNames()}
    for _, name in pairs(shipNames) do
        for system, _ in pairs(player:getShipSystems(name)) do
            if system.script == "data/scripts/systems/smugglerblocker.lua" then
                return true
            end
        end
    end

    return false
end
