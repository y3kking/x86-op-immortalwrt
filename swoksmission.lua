package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("stringutility")
include("structuredmission")
include("callable")
include("randomext")
local MissionUT = include("missionutility")
local Swoks = include("story/swoks")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Pirate Boss"%_T
mission.data.title = "The Pirate Boss"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10

mission.data.custom.location = {} -- used to store location before player knows it

mission.data.description =
{
    "Find the notorious Pirate Boss"%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "Ask traders for a hint on the whereabouts of the Pirate Boss"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "", bulletPoint = true, fulfilled = false, visible = false}, -- this is updated with correct location later
    {text = "Defeat the Pirate Boss"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Collect the teleporter key"%_T, bulletPoint = true, fulfilled = false, visible = false}
}

-- on accomplish frame mission has to be moved on
mission.globalPhase.onAccomplish = function()
    local player = Player()
    player:invokeFunction("storyquestutility.lua", "onSwoksAccomplished")
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
                    if item.script == "data/scripts/systems/teleporterkey3.lua" then
                        accomplish()
                    end
                end
            end
        end
    }
}

-- send introductory mail
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    local player = Player()
    local mail = Mail()
    mail.text = Format("Hello!\n\nTraders around here have been telling me about this pirate boss that’s terrorizing the area. Apparently, he has some secret technology on him. You should keep your ears open and listen to what everybody here has to say, maybe you can find him. While you do that, I’ll try to find out what this technology might be and what it does.\n\nGreetings,\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "Pirates terrorizing Traders /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_Swoks_Mission"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks =
{
    {
        name = "onMailRead",
        func = function(playerIndex, mailIndex, mailId)
            if mailId == "Story_Swoks_Mission" then
                setPhase(2)
            end
        end
    }
}
mission.phases[1].showUpdateOnEnd = true

-- send player to find a location hint by talking to traders
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true
    -- try to find location
    determineSwoksLocation()
end
mission.phases[2].onSectorEntered = function()
    if onServer() and mission.data.custom.location.x == nil then
        determineSwoksLocation()
    end
end
mission.phases[2].onStartDialog = function(entityId)
    local entity = Entity(entityId)
    if not entity then return end
    if entity:hasScript("data/scripts/entity/dialogs/storyhints.lua") then
        ScriptUI(entityId):addDialogOption("I heard of a Pirate Boss around here.\nDo you know something?"%_t, "onSwoksHintAsked")
    end
end
mission.phases[2].showUpdateOnEnd = true

-- show location to player and have him go there
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    -- now you know where to go - go there
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
    mission.data.description[4].text = "Meet the Pirate Boss in sector (${x}:${y})"%_t
    mission.data.description[4].arguments = {x = mission.data.location.x, y = mission.data.location.y}
end
mission.phases[3].onTargetLocationEntered = function(x, y)
    if onServer() then
        Swoks.spawn(Player(), x, y)
        nextPhase()
    end
end
mission.phases[3].showUpdateOnEnd = true

-- wait for player to kill Swoks
mission.phases[4] = {}
mission.phases[4].onBeginServer = function()
    mission.data.description[4].fulfilled = true
    mission.data.description[5].visible = true
end
mission.phases[4].onEntityDestroyed = function(index, lastDamageInflictor)
    if onServer() then
        local destroyed = Entity(index)
        if destroyed:hasScript("data/scripts/entity/story/swoks.lua") then
            setPhase(5)
        end
    end
end
mission.phases[4].onTargetLocationLeft = function()
    -- in case player doesn't kill swoks (dialog option pay), he has to respawn
    if onServer() then
        setPhase(3)
    end
end
mission.phases[4].onRestore = function()
    if onServer() then
        local x, y = Sector():getCoordinates()
        if x == mission.data.location.x and y == mission.data.location.y then
            local entities = {Sector():getEntitiesByType(EntityType.Ship)}
            local SwoksStillThere = false
            for _, ship in pairs(entities) do
                if ship:hasScript("data/scripts/entity/story/swoks.lua") then
                    SwoksStillThere = true
                end
            end
            if SwoksStillThere == false then
                Swoks.spawn(Player(), x, y)
            end
        end
    end
end

mission.phases[5] = {}
mission.phases[5].onBeginServer = function()
    mission.data.description[5].fulfilled = true
    mission.data.description[6].visible = true
end

-- calculates the spawn location of Swoks
-- -> only do it if close enough, so that player has a short travel way once he knows the location
function determineSwoksLocation()
    if onClient() then invokeServerFunction("determineSwoksLocation") return end

    -- don't calculate sector, if player isn't in correct region
    if not getExactLocationPossible() then return end

    local location = {Sector():getCoordinates()}
    local x, y = MissionUT.getSector(location[1], location[2], 1, 20, false, false, false, false)
    if not x and not y then setPhase(2) return end -- if we didn't find a sector retry
    mission.data.custom.location = {x = x, y = y}
    sync()
end
callable(nil, "determineSwoksLocation")

local hintAskedOnEnd = makeDialogServerCallback("hintAskedOnEnd", 2, function()
    -- player now knows location - so show it on map
    mission.data.location.x = mission.data.custom.location.x
    mission.data.location.y = mission.data.custom.location.y
    if mission.internals.phaseIndex == 2 then setPhase(3) end
end)

function getExactLocationPossible()
    local location = {Sector():getCoordinates()}
    local distance2 = location[1]*location[1] + location[2]*location[2]
    -- don't give hint if player is outside the swoks spawn region
    if distance2 < 350*350 or distance2 > 430*430 then return false end
    return true
end

function onSwoksHintAsked(entityId)
    if not entityId then return end
    if getExactLocationPossible() then
        if mission.data.custom.location.x == nil then
            local dialogNo = {}
            dialogNo.text = "Yeah, I've heard talk of him. But I don't know what to make of it. Ask someone else if you need to know."%_t
            dialogNo.answers = {
                {answer = "Okay, thanks."%_t}
            }
            ScriptUI(entityId):showDialog(dialogNo)
        else
            local dialogYes = {}
            dialogYes.text = string.format("Yeah, I've heard talk of him. All traders are told to not go near the sectors around (${x}:${y}). If you're looking for him you can start there. But I wouldn't recommend it, they say he's really strong."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
            dialogYes.answers = {
                {answer = "Thanks for your help."%_t}
            }
            dialogYes.onEnd = hintAskedOnEnd

            ScriptUI(entityId):showDialog(dialogYes)
        end
    end

    if not getExactLocationPossible() then
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

        if distance2 < 350*350 then
            ScriptUI(entityId):showDialog(dialogFurtherOut)
        elseif distance2 > 430*430 then
            ScriptUI(entityId):showDialog(dialogFurtherIn)
        end
    end
end
