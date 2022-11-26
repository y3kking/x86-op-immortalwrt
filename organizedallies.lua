package.path = package.path .. ";data/scripts/lib/?.lua"

include ("randomext")
include ("utility")
include ("mission")
include ("stringutility")
include ("callable")

local Dialog = include ("dialogutility")

local descriptionText = [[
Organize allies for the fight against the Xsotan Wormhole Guardian.

To find allies, you should ask at their faction's headquarters if they will assist you.

]]%_t

missionData.title = "One Against All And All Against One"%_t
missionData.brief = "One Against All And All Against One"%_t
missionData.icon = "data/textures/icons/story-mission.png"
missionData.priority = 10


function initialize()
    if onClient() then
        Player():registerCallback("onStartDialog", "onStartDialog")
        sync()
    else
        missionData.allies = {}
        missionData.description = descriptionText
        missionData.justStarted = true
    end
end

function updateDescription()
    missionData.description = descriptionText

    for _, p in pairs(missionData.allies) do
        local faction = Faction(p.factionIndex)
        if not faction then goto continue end
        local data = {name = faction.name, amount = p.amount}
        missionData.description = missionData.description .. ("${amount} ships from ${name}"%_t % data) .. "\n"
        ::continue::
    end
end

function add(factionIndex, amount)
    if not factionIndex then return end

    -- don't add factions twice
    if getNumShips(factionIndex) then return end

    amount = amount or random():getInt(3, 4)

    table.insert(missionData.allies, {factionIndex = factionIndex, amount = amount})

    showMissionUpdated()
    sync()
end
callable(nil, "add")

function deny(factionIndex)
    add(factionIndex, 0)
end
callable(nil, "deny")

function getNumShips(factionIndex)
    for _, p in pairs(missionData.allies) do
        if factionIndex == p.factionIndex then return p.amount end
    end
end

function remove(factionIndex)
    if not factionIndex then return end

    local new = {}
    for _, value in pairs(missionData.allies) do
        if value ~= factionIndex then
            table.insert(new, factionIndex)
        end
    end

    missionData.allies = new
end

function getAllies()
    return missionData.allies
end

function onStartDialog(entityId)
    local entity = Entity(entityId)

    if entity:hasScript("merchants/headquarters.lua") then
        ScriptUI(entityId):addDialogOption("Will you assist in destroying the Xsotan Wormhole Guardian?"%_t, "onAssist")
    end
end

local interactedEntityIndex
function onAssist(entityId)
    interactedEntityIndex = entityId
    local dialog

    local entity = Entity(entityId)
    -- gets player or faction depending of owner of ship
    local faction = Player().craftFaction
    local relations = faction:getRelations(entity.factionIndex)

    local numShips = getNumShips(entity.factionIndex)
    if numShips then
        if numShips == 0 then
            dialog = {text = "We already told you that we don't think this is a good idea. We won't risk our ships for some lunatic. Goodbye."%_t}
        else
            dialog = {text = "We pledged our support to you already. Open the wormholes and we will come."%_t}
        end
    else
        if relations < -10000 then
            dialog = makeBadDialog()
        elseif relations >= 70000 then
            dialog = makeGoodDialog()
        else
            dialog = makeDialog()
        end
    end

    ScriptUI(entityId):showDialog(dialog)
end

function makeDialog()
    local d0_TheWhat = {}
    local d1_AndYouWantToDes = {}
    local d2_How = {}
    local d3_HowDoWeKnowThat = {}
    local d5_ThisIsNoneOfOur = {}

    d0_TheWhat.text = "The what?"%_t
    d0_TheWhat.answers = {
        {answer = "The Xsotan mothership at the galaxy center."%_t, followUp = d1_AndYouWantToDes},
        {answer = "Never mind."%_t}
    }

    d1_AndYouWantToDes.text = "And you want to destroy it?"%_t
    d1_AndYouWantToDes.answers = {
        {answer = "Exactly."%_t, followUp = d2_How},
        {answer = "Never mind."%_t}
    }

    d2_How.text = "How?"%_t
    d2_How.answers = {
        {answer = "I'll open wormholes that will allow you to break through."%_t, followUp = d3_HowDoWeKnowThat},
        {answer = "Never mind."%_t}
    }

    d3_HowDoWeKnowThat.text = "How do we know that this is going to work? That this isn't some kind of suicide mission? Or even a trick?"%_t
    d3_HowDoWeKnowThat.answers = {
        {answer = "You will have to trust me."%_t, followUp = d5_ThisIsNoneOfOur},
        {answer = "Never mind."%_t}
    }

    d5_ThisIsNoneOfOur.text = "This is none of our business. Why exactly should we trust you? Or help you?"%_t
    d5_ThisIsNoneOfOur.answers = {
        {answer = "This is your chance to be the saviors of the galaxy."%_t, onSelect = "saveGalaxy", followUp = Dialog.empty()},
        {answer = "The Xsotan mothership will have a lot of loot."%_t, onSelect = "lotsOfLoot", followUp = Dialog.empty()},
        {answer = "This is your time for revenge."%_t, onSelect = "revenge", followUp = Dialog.empty()},
        {answer = "It's only a matter of time until the Xsotan arrive here, too."%_t, onSelect = "arriveHereToo", followUp = Dialog.empty()},
        {answer = "Don't you want to do something instead of sitting around?"%_t, onSelect = "doSomething", followUp = Dialog.empty()},
        {answer = "Because it's the right thing to do."%_t, onSelect = "rightThingToDo", followUp = Dialog.empty()},
        {answer = "Never mind."%_t}
    }

    return d0_TheWhat
end

function makeBadDialog()
    local d0_WhoAreYouWeDont = {}

    d0_WhoAreYouWeDont.text = "Who are you? We don't want anything to do with you."%_t
    d0_WhoAreYouWeDont.answers = {
        {answer = "Never mind."%_t}
    }

    return d0_WhoAreYouWeDont
end

function makeGoodDialog()
    local d0_YouAreOurAllyOf = {}

    d0_YouAreOurAllyOf.text = "You are our ally. You can count on our assistance."%_t
    d0_YouAreOurAllyOf.onStart = "help"
    d0_YouAreOurAllyOf.answers = {
        {answer = "Thank you."%_t}
    }

    return d0_YouAreOurAllyOf
end

function help()
    local entity = Entity(interactedEntityIndex)
    local faction = Faction(entity.factionIndex)

    invokeServerFunction("add", faction.index)
end

function arriveHereToo()
    traitCheck("smart", "paranoid", "passive", "naive")
end

function doSomething()
    traitCheck("empathic", "forgiving", "active", "naive")
end

function lotsOfLoot()
    traitCheck("opportunistic", "greedy", "naive")
end

function revenge()
    traitCheck("strict", "aggressive", "sadistic")
end

function rightThingToDo()
    traitCheck("honorable", "brave", "generous", "naive")
end

function saveGalaxy()
    traitCheck("honorable", "brave", "peaceful", "naive")
end

function traitCheck(...)
    local entity = Entity(interactedEntityIndex)
    local faction = Faction(entity.factionIndex)

    local traits = {...}

    -- gets player or faction depending of owner of ship
    local playerFaction = Player().craftFaction

    local threshold = lerp(playerFaction:getRelations(faction.index), 25000, 70000, 0.95, 0.25)

    local willHelp = false
    for _, trait in pairs(traits) do
        if faction:getTrait(trait) > threshold then
            willHelp = true
        end
    end

    local dialog
    if willHelp then
        dialog = {text = "Alright, you can count on us. Once the wormhole to our sectors is open, we'll assist you in the battle."%_t}
        help()
    else
        dialog = {text = "This doesn't sound like a good idea.\n\nWe wish you best of luck in your struggles."%_t}
        invokeServerFunction("deny", faction.index)
    end

    ScriptUI(interactedEntityIndex):showDialog(dialog)

    return false
end
