package.path = package.path .. ";data/scripts/lib/?.lua"

include ("utility")
include ("structuredmission")
include ("player")
include ("randomext")
include ("faction")

local SectorSpecifics = include ("sectorspecifics")
local SectorGenerator = include ("SectorGenerator")
local AsyncPirateGenerator = include ("asyncpirategenerator")
local BlackMarketUT = include("internal/dlc/blackmarket/lib/blackmarketutility.lua")
local WaveUtility = include("waveutility")
local ShipGenerator = include("shipgenerator")

--mission.tracing = true

mission.data.title = {text = "WANTED: ${target} ${name}"%_T}
mission.data.brief = {text = "WANTED: ${target} ${name}"%_T}

mission.data.autoTrackMission = true

mission.data.brief.arguments = {target = mission.data.custom.targetTitle or "", name = mission.data.custom.targetName or ""}
mission.data.title.arguments = {target = mission.data.custom.targetTitle or "", name = mission.data.custom.targetName or ""}
mission.data.custom.location = {}
mission.data.targets = {}

mission.data.description = {}
mission.data.description[1] = {text = "Fulfill the bounty hunting contract and make these sectors safe again!"%_T}
mission.data.description[2] = {text = "Go to sector (${x}:${y})"%_T, bulletPoint = true, visible = false, fulfilled = false}
mission.data.description[3] = {text = "", bulletPoint = true, visible = false, fulfilled = false}
mission.data.description[4] = {text = "Go to sector (${x}:${y})"%_T, bulletPoint = true, visible = false, fulfilled = false}
mission.data.description[5] = {text = "Defeat the pirates"%_T, bulletPoint = true, visible = false, fulfilled = false}
mission.data.description[6] = {text = "Return to the freighter in sector (${x}:${y})"%_T, bulletPoint = true, visible = false, fulfilled = false}

mission.globalPhase.noBossEncountersTargetSector = true
mission.globalPhase.noPlayerEventsTargetSector = true
mission.globalPhase.noLocalPlayerEventsTargetSector = true
mission.globalPhase.onRestore = function()
    if not mission.data.custom.targetTitleIndex then
        mission.data.custom.targetTitleIndex = 1
    end
end

-- update descriptions
----------------------------------------------------
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    mission.data.custom.targetTitle = mission.data.arguments.targetTitle or ""
    mission.data.custom.targetName = mission.data.arguments.targetName or ""
    mission.data.custom.targetTitleIndex = mission.data.arguments.targetTitleIndex
    mission.data.custom.options = mission.data.arguments.options
    mission.data.custom.employerName = mission.data.arguments.employerName
    mission.data.brief.arguments = {target = mission.data.custom.targetTitle or "", name = mission.data.custom.targetName or ""}
    mission.data.title.arguments = {target = mission.data.custom.targetTitle or "", name = mission.data.custom.targetName or ""}

    mission.data.custom.firstStep = mission.data.custom.options[1] -- variable needed in test
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].visible = true

    Player():addMail(makeStartMail())

    Player():sendChatMessage(mission.data.custom.employerName, ChatMessageType.Normal, "Start looking for the target in \\s(%1%:%2%)."%_T, mission.data.location.x, mission.data.location.y)
    goToNextStep()
end
mission.phases[1].onRestore = function()
    setPhase(1)
end
mission.phases[1].showUpdateOnEnd = true

function makeStartMail()
    local mail = Mail()
    if mission.data.custom.targetTitleIndex < 4 then
        mail.text = Format("Thank you for accepting the contract.\n\nYour target: %1% %2%. \n\nThey have been causing trouble, attacking ships and stations and stealing from us.\n\nThey claim to belong to a large syndicate, but it turns out they're just outcasts.\n\nDo not misunderstand us, we need them dead, do not try to capture them!\n\n%3%"%_T, mission.data.custom.targetTitle or "", mission.data.custom.targetName, mission.data.custom.employerName)
    else
        mail.text = Format("Thank you for accepting the contract.\n\nYour target: %1% %2%. \n\nHe and his pirates have been terrorizing our people for far too long. We can no longer close our eyes to this threat.\n\nEliminate him and his followers. Do not attempt to take him alive.\n\nThis is meant to set an example: Destroy every last one of their ships!\n\n%3%"%_T, mission.data.custom.targetTitle or "", mission.data.custom.targetName, mission.data.custom.employerName)
    end

    mail.header = "Wanted Dead, Not Alive /* Mail Subject */"%_T
    mail.sender = mission.data.custom.employerName
    mail.id = "BountyHunt_1"

    return mail
end

-- FINAL BOSS: mothership
-----------------------------------------------
mission.phases[2] = {}
local finalDialogStarted = false
mission.phases[2].onTargetLocationEntered = function()
    if onServer() then
        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Defeat ${target} ${name}"%_T}
        mission.data.description[3].arguments = {target = (mission.data.custom.targetTitle or "")%_t, name = mission.data.custom.targetName}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true

        mission.data.custom.mothershipBackup = {}
        findOrSpawnMothershipBackup(random():getInt(4, 6))
        local generator = AsyncPirateGenerator(nil, onMothershipCreated)
        generator:createScaledBoss()
        mission.data.custom.mothershipActivated = false
    end
end
mission.phases[2].onTargetLocationArrivalConfirmed = function()
    mission.data.custom.arrivedInTargetSector = true
    sync()
end
mission.phases[2].updateTargetLocationClient = function()
    local mothership = Sector():getEntitiesByScriptValue("is_mothership", true)
    if  mission.data.custom.arrivedInTargetSector == true and mothership and finalDialogStarted == false then
        deferredCallback(3, "startFinalDialog")
        finalDialogStarted = true
    end
end
mission.phases[2].updateServer = function(timeStep)
    if not MissionUT.playerInTargetSector(Player(), mission.data.location) then return end

    mission.data.custom.mothershipBackupCount = #{Sector():getEntitiesByScriptValue("is_wave")}

    if mission.data.custom.mothershipActivated == true and mission.data.custom.mothershipBackupCount == 0 then
        local player = Player()
        player:addMail(makeEndMail())

        local reward = mission.data.reward
        local faction = Faction(mission.data.giver.factionIndex)

        if faction and faction.isAIFaction then
            if player.craft then
                changeRelations(player.craft.factionIndex, faction, reward.relations)
            else
                changeRelations(player, faction, reward.relations)
            end
        end

        accomplish()
    end

    if mission.data.custom.mothershipBackupCount <= 2 and mission.data.custom.mothershipGenerated == true
            and Entity(mission.data.custom.mothershipId) and not mission.data.custom.mothershipActivated then

        local mothership = Entity(mission.data.custom.mothershipId)
        mothership.invincible = false
        ShipAI(mothership):setAggressive()
        mission.data.custom.mothershipActivated = true
    end
end
mission.phases[2].onTargetLocationLeft = function()
    fail()
end
mission.phases[2].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(2)
end

local finalDialogOnEnd = makeDialogServerCallback("finalDialogOnEnd", 2, function()
    local player = Player()
    local ai = ShipAI(mission.data.custom.mothershipId)
    local player = Player()

    ai:setAggressive()
    ai:registerEnemyFaction(player.index)
    if player.allianceIndex then
        ai:registerEnemyFaction(player.allianceIndex)
    end

    for _, ship in pairs(mission.data.custom.mothershipBackup) do
        if Entity(ship) then
            registerEnemies(ship)
        end
    end
end)

-- pirate dialog
function startFinalDialog()
    if onServer() then
        invokeClientFunction(Player(), "startFinalDialog")
        return
    end

    local dialogFinal_0 = {}
    local dialogFinal_1 = {}

    dialogFinal_0.text = "Ah. So the rumors are true!\n\nThey sent out bounty hunters for us!"%_t
    dialogFinal_0.answers = {{answer = "Yes. Feeling flattered?"%_t, followUp = dialogFinal_1}}

    dialogFinal_1.text = "And you believe that you can capture us, you worm?\n\nWe'll see about that."%_t
    dialogFinal_1.onEnd = finalDialogOnEnd

    local mothership = Sector():getEntitiesByScriptValue("is_mothership", true)
    if mothership then
        ScriptUI(mothership.id):interactShowDialog(dialogFinal_0, false)
    end
end

function makeEndMail()
    local reward = createMonetaryString(mission.data.reward.credits)
    local r = mission.data.reward
    local mail = Mail()
    mail.text = Format("Greetings!\n\nThank you for taking care of our little Problem.\n\nPlease find your reward of %1%¢ in the attachment.\n\nWe hope you will consider doing business with us in the future.\n\n%2%"%_T, reward, mission.data.custom.employerName)
    mail.header = "Target Eliminated /* Mail Subject */"%_T
    mail.sender = mission.data.custom.employerName
    mail.money = r.credits
    mail:setResources(r.iron, r.titanium, r.naonite, r.trinium, r.xanion, r.ogonite, r.avorion)
    mail.id = "BountyHunt_2"

    return mail
end

-- OPTION 1: find coordinates in package
----------------------------------------------------
mission.phases[3] = {}
mission.phases[3].onTargetLocationEntered = function()
    if onServer() then
        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Search the container field for information"%_T}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true

        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}

        spawnTemporaryContainers()

        for _, entity in pairs({Sector():getEntitiesByType(EntityType.Container)}) do
            if not entity:hasScript("data/scripts/entity/stash.lua")
                    and not entity:hasScript("internal/dlc/blackmarket/entity/hackablecontainer.lua")
                    and not entity:hasScript("data/scripts/entity/piratestash.lua") then

                entity:addScriptOnce("data/scripts/entity/stash.lua", true)
                entity:setValue("bountyHunt_1_container", true)
                mission.data.custom.containerId = entity.id.string
                break
            end
        end

        table.insert(mission.data.targets, mission.data.custom.containerId)
    end
end
mission.phases[3].playerCallbacks = {}
mission.phases[3].playerCallbacks[1] =
{
    name = "onStashOpened",
    func = function(entityId)

        local container = Entity(entityId)
        if not container:getValue("bountyHunt_1_container") then return end

        local player = Player()
        local craft = player.craft
        local reservedFor
        if not craft then
            reservedFor = player
        else
            reservedFor = Faction(craft.factionIndex)
        end

        local sector = Sector()
        local position = container.translationf

        local packageId = sector:dropVanillaItem(position, player, nil, bountyHuntPackage()).id.string
        mission.data.targets = {}
        table.insert(mission.data.targets, packageId)
        sync()
    end
}
mission.phases[3].playerCallbacks[2] =
{
    name = "onItemAdded",
    func = function(index, amount, amountBefore)
        if onServer() then
            local player = Player()
            local item = player:getInventory():find(index)
            if not item then return end

            if item.itemType == InventoryItemType.VanillaItem then
                if item:getValue("bountyHuntItem") == true then
                    if not mission.data.custom.location
                            or not mission.data.custom.location.x
                            or not mission.data.custom.location.y then
                        local x, y = findNearbyEmptySector()
                        mission.data.custom.location = {x = x, y = y}
                    end

                    player:sendChatMessage("", ChatMessageType.Normal, "Found an empty package. Signature indicates sector \\s(%1%:%2%) as origin."%_T, mission.data.custom.location.x, mission.data.custom.location.y)

                    mission.data.location = mission.data.custom.location
                    mission.data.description[3].visible = false
                    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
                    mission.data.description[2].fulfilled = false
                    mission.data.targets = {}
                    goToNextStep()
                end
            end
        end
    end
}
mission.phases[3].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(3)
end
mission.phases[3].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}
    mission.data.custom.location = mission.data.location
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(3)
end
mission.phases[3].showUpdateOnEnd = true

-- OPTION 2: search wreckage
----------------------------------------------------
mission.phases[4] = {}
mission.phases[4].onTargetLocationEntered = function()
    if onServer() then
        spawnWreckages(5)
        table.insert(mission.data.targets, mission.data.custom.firstWreck)
        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}

        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Search the wreck"%_T}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true
    end
end
mission.phases[4].playerCallbacks = {}
mission.phases[4].playerCallbacks[1] =
{
    name = "onStoryHintWreckageSearched",
    func = function(entityId)
        if mission.data.custom.firstWreck == entityId then
            ScriptUI(entityId):interactShowDialog(makeOption2WreckageHint())
        end
    end
}
mission.phases[4].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(4)
end
mission.phases[4].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(4)
end
mission.phases[4].showUpdateOnEnd = true

local option2HintOnEnd = makeDialogServerCallback("option2HintOnEnd", 4, function()
    mission.data.location = mission.data.custom.location
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.targets = {}
    goToNextStep()
end)

function makeOption2WreckageHint()
    local dialog = {}
    local dialog1 = {}

    dialog.text = string.format("Log Files of Freighter ${name}"%_t % {name = makeRandomNames()})
    dialog.answers = {{answer = "Proceed"%_t, followUp = dialog1}}

    dialog1.text = string.format("Showing most recent entries:\n\nWe were attacked in sector (${x}:${y})!\nManaged to initiate emergency hyperspace jump.\nPursuers still on scanners, we'll try to ..."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
    dialog1.answers = {{answer = "Close"%_t}}
    dialog1.onEnd = option2HintOnEnd

    return dialog
end

-- OPTION 3: ask freighter
----------------------------------------------------
mission.phases[5] = {}
mission.phases[5].onTargetLocationEntered = function()
    if onServer() then
        findOrSpawnFreighter()
        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}        
        table.insert(mission.data.targets, mission.data.custom.freighterId)

        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Talk to the freighter"%_T}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true

        local freighter = Entity(mission.data.custom.freighterId)
        freighter.invincible = false
        local damage = (freighter.maxDurability or 0) * 0.5
        freighter:inflictDamage(damage, 1, DamageType.Physical, 0, vec3(), Entity(mission.data.custom.freighterId).id)
        freighter.invincible = true
    end
end
mission.phases[5].onStartDialog = function(entityId)
    if entityId.string == mission.data.custom.freighterId then
        ScriptUI(mission.data.custom.freighterId):addDialogOption("[Ask for target]"%_t, "startFreighterDialog")
    end
end
mission.phases[5].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(5)
end
mission.phases[5].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(5)
end
mission.phases[5].showUpdateOnEnd = true

-- freighter dialog
local freighterDialogOnEnd = makeDialogServerCallback("freighterDialogOnEnd", 5, function()
    mission.data.location = mission.data.custom.location
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.targets = {}
    goToNextStep()
end)

function startFreighterDialog()
    if onServer() then
        invokeClientFunction(Player(), "startFreighterDialog")
        return
    end

    local dialog3_0 = {}
    local dialog3_1 = {}
    local dialog3_2 = {}
    local dialog3_3 = {}
    local dialog3_4 = {}

    dialog3_0.text = "What do you want? Can't you see we have problems of our own?"%_t
    dialog3_0.answers = {{answer = "What's going on?"%_t, followUp = dialog3_1}}

    if mission.data.custom.targetTitleIndex == 1 then
        dialog3_1.text = "We were attacked by a group of ships.\n\nThe said they belonged to the syndicate 'the Cavaliers', but there's no way that's true!\n\nThey said that we needed to be taught a lesson for working for 'The Commune'.\n\nBut then they made us drop our cargo and just left, so why were they talking about righteousness? Bloody pirates!"%_t
    elseif mission.data.custom.targetTitleIndex == 2 then
        dialog3_1.text = "We were attacked by a group of ships.\n\nThe said they belonged to the syndicate 'the Family', but we didn't believe that.\n\nThey said that we delivered weapons to 'The Cavaliers'.\n\nBut we're just doing our job moving freight! We don't deserve to get attacked for that!"%_t
    elseif mission.data.custom.targetTitleIndex == 3 then
        dialog3_1.text = "We were attacked by a group of ships.\n\nThe said they belonged to the syndicate 'the Commune', but we didn't believe that.\n\nThey claimed we were working for a corporation that was suppressing workers, and that we needed to be punished for that.\n\nBut we're just doing our job moving freight! We don't deserve to get attacked for that!"%_t
    elseif mission.data.custom.targetTitleIndex >= 4 then
        dialog3_1.text = "We were attacked by a pirate called ${target} ${name}.\n\nHe said we were flying through his territory and that we had to pay a toll.\n\nWhen we refused, they damaged our ship instead and told us that they were going to destroy us next time!"%_t % {target = (mission.data.custom.targetTitle or "")%_t, name = mission.data.custom.targetName}
    end

    dialog3_1.answers = {{answer = "Where did they go?"%_t, followUp = dialog3_2}}

    dialog3_2.text = "Why do you care? Are you hunting them?"%_t
    dialog3_2.answers = {{answer = "Yes, I want the bounty."%_t, followUp = dialog3_3}}

    dialog3_3.text = "Good. They'll get what they deserve!\n\nOur scanners showed that they jumped to sector (${x}:${y}) afterwards, but then we stopped tracking them."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    dialog3_3.answers = {{answer = "Thank you."%_t, followUp = dialog3_4}}

    dialog3_4.text = "Good luck! You're doing a good deed here!"%_t
    dialog3_4.onEnd = freighterDialogOnEnd

    ScriptUI(mission.data.custom.freighterId):interactShowDialog(dialog3_0, false)
end

-- OPTION 4: ask second freighter
----------------------------------------------------
mission.phases[6] = {}
mission.phases[6].onTargetLocationEntered = function()
    if onServer() then
        findOrSpawnFreighter()
        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}        
        table.insert(mission.data.targets, mission.data.custom.freighterId)

        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Talk to the freighter"%_T}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true
    end
end
mission.phases[6].onStartDialog = function(entityId)
    if entityId.string == mission.data.custom.freighterId then
        ScriptUI(mission.data.custom.freighterId):addDialogOption("[Ask for target]"%_t, "startOption4FreighterDialog")
    end
end
mission.phases[6].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(6)
end
mission.phases[6].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(6)
end
mission.phases[6].showUpdateOnEnd = true

-- station dialog
local option4FreighterDialogOnEnd = makeDialogServerCallback("option4FreighterDialogOnEnd", 6, function()
    mission.data.location = mission.data.custom.location
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.targets = {}
    goToNextStep()
end)

function startOption4FreighterDialog()
    if onServer() then
        invokeClientFunction(Player(), "startoption4FreighterDialog")
        return
    end

    local dialog4_1 = {}
    local dialog4_2 = {}
    local dialog4_3 = {}
    local dialog4_4 = {}

    dialog4_1.text = "Hey, what are you doing here? I already called for backup, so don't even try to attack us."%_t
    dialog4_1.answers = {{answer = "Don't worry. We are on a bounty hunt."%_t, followUp = dialog4_2}}

    if mission.data.custom.targetTitleIndex == 1 then
        dialog4_2.text = "Oh, I think I know who you're looking for. The Cavaliers are looking for them, too.\n\nWe saw them at a factory not too long ago.\n\nTried to scare the workers a bit, telling them stories about an Emperor.\n\nBut they left when security was alerted."%_t
    elseif mission.data.custom.targetTitleIndex == 2 then
        dialog4_2.text = "Oh, I think I know who you're looking for. The Family is looking for them, too.\n\nWe saw them at a trading post not too long ago.\n\nTried to snoop around, said they were looking for 'business opportunities'.\n\nBut they left when security was alerted."%_t
    elseif mission.data.custom.targetTitleIndex == 3 then
        dialog4_2.text = "Oh, I think I know who you're looking for. The Commune is looking for them, too.\n\nWe saw them at a factory not too long ago.\n\nPretended to care about the workers, started handing out pamphlets.\n\nBut they left when security was alerted."%_t
    elseif mission.data.custom.targetTitleIndex >= 4 then
        dialog4_2.text = "Oh, are you looking for ${target} ${name}?\n\nWe saw him and his people at a trading post not too long ago.\n\nStarted asking around, wanted to hire crew.\n\nBut they left when security was alerted."%_t % {target = (mission.data.custom.targetTitle or "")%_t, name = mission.data.custom.targetName}
    end

    dialog4_2.answers = {{answer = "Where are they now?"%_t, followUp = dialog4_3}}

    dialog4_3.text = "Well, if you can bring them down, you'd be doing everyone a favor.\n\nThey jumped to sector (${x}:${y})."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    dialog4_3.answers = {{answer = "Thank you."%_t, followUp = dialog4_4}}

    dialog4_4.text = "Happy hunting!"%_t
    dialog4_4.onEnd = option4FreighterDialogOnEnd

    ScriptUI(mission.data.custom.freighterId):interactShowDialog(dialog4_1, false)
end

-- OPTION 5: ask freighter but get job
----------------------------------------------------
mission.phases[7] = {}
mission.phases[7].onTargetLocationEntered = function()
    if onServer() then
        findOrSpawnFreighter()
        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}
        table.insert(mission.data.targets, mission.data.custom.freighterId)

        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Talk to the freighter"%_T}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true
    end
end
mission.phases[7].onStartDialog = function(entityId)
    if entityId.string == mission.data.custom.freighterId then
        ScriptUI(mission.data.custom.freighterId):addDialogOption("[Ask for target]"%_t, "startOption5FreighterDialog")
    end
end
mission.phases[7].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(7)
end
mission.phases[7].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(7)
end
mission.phases[7].showUpdateOnEnd = true

-- defeat pirates
mission.phases[8] = {}
mission.phases[8].onBeginServer = function()
    resetWaveData()
end
mission.phases[8].onTargetLocationEntered = function()
    mission.data.description[4].fulfilled = true
    mission.data.description[5].visible = true
end
mission.phases[8].updateServer = function(timeStep)
    updateWaveEncounter()

    if mission.data.custom.readyForDialog == true and mission.data.custom.dialogStarted == false then
        mission.data.custom.dialogStarted = true
        startOption5PirateDialog()
    end

    if mission.data.custom.allDefeated == true then nextPhase() end
end
mission.phases[8].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[4].fulfilled = false
    mission.data.description[5].visible = false
    setPhase(8)
end
mission.phases[8].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].fulfilled = true
    mission.data.description[4].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[4].fulfilled = false
    mission.data.description[5].visible = false
    setPhase(8)
end
mission.phases[8].showUpdateOnEnd = true

-- return to freighter
mission.phases[9] = {}
mission.phases[9].onBeginServer = function()
    mission.data.location = mission.data.custom.stationLocation
    mission.data.description[6].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[6].visible = true
    mission.data.description[5].fulfilled = true
    sync()
end
mission.phases[9].onTargetLocationEntered = function()
    if onServer() then
        findOrSpawnFreighter()
        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}
        table.insert(mission.data.targets, mission.data.custom.freighterId)
    end
end
mission.phases[9].onStartDialog = function(entityId)
    if entityId.string == mission.data.custom.freighterId then
        ScriptUI(mission.data.custom.freighterId):addDialogOption("[Report]"%_t, "startOption5FreighterDialog2")
    end
end
mission.phases[9].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(9)
end
mission.phases[9].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(9)
end
mission.phases[9].showUpdateOnEnd = true

-- station dialog
local option5FreighterDialogOnEnd = makeDialogServerCallback("option5FreighterDialogOnEnd", 7, function()
    local x, y = Sector():getCoordinates()
    mission.data.custom.stationLocation = {x = x, y= y}
    mission.data.location = mission.data.custom.location

    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
    mission.data.description[4].arguments = {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    mission.data.targets = {}
    setPhase(8)
end)

function startOption5FreighterDialog()
    if onServer() then
        invokeClientFunction(Player(), "startOption5FreighterDialog")
        return
    end

    local dialog5_2 = {}
    local dialog5_3 = {}
    local dialog5_4 = {}

    dialog5_2.text = "We know your kind.\n\nYou're bounty hunters!\n\nWe don't want you here."%_t
    dialog5_2.answers = {{answer = "Come on, just help us out."%_t, followUp = dialog5_3}}

    dialog5_3.text = "Nothing is for free in this galaxy.\n\nBut you can do something for us: get rid of those pirates in sector (${x}:${y}).\n\nReturn after destroying them and we will give you the information you seek."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    dialog5_3.answers = {{answer = "Are you serious?"%_t, followUp = dialog5_4}}

    dialog5_4.text = "Yes. Get rid of those pirates or we won't help you.\n\nBut if you do get rid of them, you will get paid for your services, of course."%_t
    dialog5_4.onEnd = option5FreighterDialogOnEnd

    ScriptUI(mission.data.custom.freighterId):interactShowDialog(dialog5_2, false)
end

local option5PirateDialogOnEnd = makeDialogServerCallback("option5PirateDialogOnEnd", 8, function()
    mission.data.custom.piratesAggressive = true
    local player = Player()
    for _, shipId in pairs(mission.data.custom.wavePirates) do
        if Entity(shipId) then
            registerEnemies(shipId)
        end
    end
end)

function startOption5PirateDialog()
    if onServer() then
        invokeClientFunction(Player(), "startOption5PirateDialog")
        return
    end

    local dialog5_0 = {}
    local dialog5_1 = {}

    dialog5_0.text = "Look guys, now we don't even have to chase our victims, they come to us!"%_t
    dialog5_0.answers = {{answer = "Actually, we're coming FOR you."%_t, followUp = dialog5_1}}

    dialog5_1.text = "They think they can defeat us! Let's show them what we're made of!"%_t
    dialog5_1.onEnd = option5PirateDialogOnEnd

    ScriptUI(mission.data.custom.wavePirates[1]):interactShowDialog(dialog5_0, false)
end

-- station dialog 2
local option5FreighterDialog2OnEnd = makeDialogServerCallback("option5FreighterDialog2OnEnd", 9, function()
    -- additional random reward
    local credits = random():getInt(10000, 15000) * Balancing_GetSectorRewardFactor(Sector():getCoordinates())
    local roundedCredits = makePrettyNumber(credits)
    Player():receive("Received %1% Credits for destroying pirates."%_T, roundedCredits)

    mission.data.location = mission.data.custom.location
    mission.data.description[6].visible = false
    mission.data.description[5].visible = false
    mission.data.description[4].visible = false
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false

    goToNextStep()
end)

function startOption5FreighterDialog2()
    if onServer() then
        invokeClientFunction(Player(), "startOption5FreighterDialog2")
        return
    end

    local dialog5 = {}

    dialog5.text = "You kept your end of the bargain, so we'll tell you what you want to know.\n\nYou should be able to find them or their associates in sector (${x}:${y}).\n\nWe don't need to tell you that they're going to be tough to defeat.\n\nYou're a professional."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    dialog5.answers = {{answer = "Thanks."%_t}}
    dialog5.onEnd = option5FreighterDialog2OnEnd

    ScriptUI(mission.data.custom.freighterId):interactShowDialog(dialog5, false)
end

-- OPTION 6: ask pirates
----------------------------------------------------
mission.phases[10] = {}
mission.phases[10].onBeginServer = function()
    resetWaveData()

    local x, y = findNearbyEmptySector()
    mission.data.custom.location = {x = x, y = y}
end
mission.phases[10].updateTargetLocationServer = function(timeStep)
    updateWaveEncounter()

    if mission.data.custom.readyForDialog == true and mission.data.custom.dialogStarted == false then
        mission.data.custom.dialogStarted = true
        mission.data.custom.firstPirate = Entity(mission.data.custom.wavePirates[1])
        mission.data.custom.firstPirate:addScriptOnce("data/scripts/entity/utility/kobehavior.lua")
        mission.data.custom.firstPirate:addScriptOnce("data/scripts/entity/utility/basicinteract.lua")
        startOption6PirateDialog()
    end

    if mission.data.custom.wave2Spawned then
        if mission.data.custom.firstPirate then
            mission.data.custom.firstPirate:setValue("is_wave", false)
        end
    end

    if mission.data.custom.waveGenerated == true and mission.data.custom.allDefeated == true and mission.data.custom.endDialogStarted == false then
        registerFriends(mission.data.custom.wavePirates[1])
        startOption6PirateDialog2()
        mission.data.custom.endDialogStarted = true
    end
end
mission.phases[10].onTargetLocationEntered = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3] = {text = "Get information from the pirates"%_T}
    mission.data.description[3].bulletPoint = true
    mission.data.description[3].visible = true

    resetWaveData()
end
mission.phases[10].onTargetLocationLeft = function()
    fail()
end
mission.phases[10].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(10)
end
mission.phases[10].showUpdateOnEnd = true

local option6PirateDialogOnEnd = makeDialogServerCallback("option6PirateDialogOnEnd", 10, function()
    mission.data.custom.piratesAggressive = true
    local player = Player()

    for _, ship in pairs(mission.data.custom.wavePirates) do
        if Entity(ship) then
            registerEnemies(ship)
        end
    end
end)

-- pirate dialog
function startOption6PirateDialog()
    if onServer() then
        invokeClientFunction(Player(), "startOption6PirateDialog")
        return
    end

    local dialog6_0 = {}
    local dialog6_1 = {}
    local dialog6_2 = {}
    local dialog6_3 = {}

    dialog6_0.text = "What do you want?"%_t
    dialog6_0.answers = {{answer = "We're looking for someone: ${target} ${name}."%_t % {target = (mission.data.custom.targetTitle or "")%_t, name = mission.data.custom.targetName}, followUp = dialog6_1}}

    dialog6_1.text = "Wait a minute...\n\nThe name of your ship ... ${name} ... that sounds familiar?"%_t % {name = Player().craft.name}
    dialog6_1.answers = {{answer = "It does?"%_t, followUp = dialog6_2}}

    dialog6_2.text = "Yes it does! You're the dog that attacked our buddy Johnson!"%_t
    dialog6_2.answers = {{answer = "What?"%_t, followUp = dialog6_3}}

    dialog6_3.text = "You're going to pay for that!"%_t
    dialog6_3.onEnd = option6PirateDialogOnEnd

    ScriptUI(mission.data.custom.wavePirates[1]):interactShowDialog(dialog6_0, false)
end

-- end dialog
local option6PirateDialog2OnEnd = makeDialogServerCallback("option6PirateDialog2OnEnd", 10, function()
    mission.data.location = mission.data.custom.location
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false

    goToNextStep()
end)

function startOption6PirateDialog2()
    if onServer() then
        invokeClientFunction(Player(), "startOption6PirateDialog2")
        return
    end

    local dialog6_0 = {}
    local dialog6_1 = {}
    local dialog6_2 = {}

    dialog6_0.text = "Okay, okay! Stop shooting!"%_t
    dialog6_0.answers = {{answer = "Are you ready to talk?"%_t, followUp = dialog6_1}}

    dialog6_1.text = "We recently did a job for the ones you're looking for.\n\nWe met them in sector (${x}:${y}).\n\nBut don’t tell them where you got the coordinates from!"%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    dialog6_1.answers = {{answer = "Thanks."%_t, followUp = dialog6_2}}

    dialog6_2.text = "Go die in a hole."%_t
    dialog6_2.onEnd = option6PirateDialog2OnEnd

    local pirate = Sector():getEntitiesByScript("data/scripts/entity/utility/kobehavior.lua")
    if pirate then
        ScriptUI(pirate.id):interactShowDialog(dialog6_0, false)
    end
end

-- OPTION 7: search wreckage
----------------------------------------------------
mission.phases[11] = {}
mission.phases[11].onBeginServer = function()
    resetWaveData()
end
mission.phases[11].onTargetLocationEntered = function()
    if onServer() then
        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}

        spawnWreckages(5)
        table.insert(mission.data.targets, mission.data.custom.firstWreck)

        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Search the wreck"%_T}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true
    end
end
mission.phases[11].updateServer = function(timeStep)
    updateWaveEncounter()

    if mission.data.custom.readyForDialog == true and mission.data.custom.dialogStarted == false then
        mission.data.custom.dialogStarted = true
        startOption7PirateDialog()
    end
end

mission.phases[11].playerCallbacks = {}
mission.phases[11].playerCallbacks[1] =
{
    name = "onStoryHintWreckageSearched",
    func = function(entityId)
        if mission.data.custom.firstWreck == entityId then
            ScriptUI(entityId):interactShowDialog(makeOption7WreckageHint())
        end
    end
}
mission.phases[11].onTargetLocationLeft = function()
    fail()
end
mission.phases[11].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(11)
end
mission.phases[11].showUpdateOnEnd = true

local option7PirateDialogOnEnd = makeDialogServerCallback("option7PirateDialogOnEnd", 11, function()
    mission.data.custom.piratesAggressive = true
    local player = Player()

    for _, ship in pairs(mission.data.custom.wavePirates) do
        if Entity(ship) then
            registerEnemies(ship)
        end
    end
end)

-- pirate dialog
function startOption7PirateDialog()
    if onServer() then
        invokeClientFunction(Player(), "startOption7PirateDialog")
        return
    end

    local dialog7_0 = {}
    local dialog7_1 = {}
    local dialog7_2 = {}

    dialog7_0.text = "Get lost, this is our loot!"%_t
    dialog7_0.answers = {{answer = "Did you defeat those ships?"%_t, followUp = dialog7_1}}

    dialog7_1.text = "Well...\n\nNot quite... \n\nBut we found the wreckages, and we're gonna salvage them!"%_t
    dialog7_1.answers = {{answer = "I need info from those wreckages."%_t, followUp = dialog7_2}}

    dialog7_2.text = "That's too bad. You're gonna have to go through us!"%_t
    dialog7_2.onEnd = option7PirateDialogOnEnd

    ScriptUI(mission.data.custom.wavePirates[1]):interactShowDialog(dialog7_0, false)
end

local option7HintOnEnd = makeDialogServerCallback("option7HintOnEnd", 11, function()
    mission.data.location = mission.data.custom.location
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false

    goToNextStep()
end)

function makeOption7WreckageHint()
    local dialog = {}
    local dialog1 = {}

    dialog.text = string.format("Log Files of Freighter ${name}"%_t % {name = makeRandomNames()})
    dialog.answers = {{answer = "Proceed"%_t, followUp = dialog1}}

    dialog1.text = string.format("Showing most recent entries:\n\nHyperspace engine overheated!\nWe're stranded!\nScanners show more pursuers in sector (${x}:${y})!"%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y})
    dialog1.answers = {{answer = "Close"%_t}}
    dialog1.onEnd = option7HintOnEnd

    return dialog
end

-- OPTION 8: bribe or defeat patrol ship
-----------------------------------------------
mission.phases[12] = {}
mission.phases[12].onTargetLocationEntered = function()
    if onServer() then
        local x, y = findNearbyEmptySector()
        mission.data.custom.location = {x = x, y = y}

        findOrSpawnPatrolShip()

        table.insert(mission.data.targets, mission.data.custom.patrolId)

        mission.data.description[2].fulfilled = true
        mission.data.description[3] = {text = "Get information from the patrol ship"%_T}
        mission.data.description[3].bulletPoint = true
        mission.data.description[3].visible = true
    end
end
mission.phases[12].onTargetLocationArrivalConfirmed = function()
    table.insert(mission.data.targets, mission.data.custom.patrolId)
    startOption8PatrolDialog()
    sync()
end
mission.phases[12].onStartDialog = function(entityId)
    if entityId.string == mission.data.custom.patrolId then
        ScriptUI(mission.data.custom.patrolId):addDialogOption("[Ask for target]"%_t, "startOption8PatrolDialog")
    end
end
mission.phases[12].sectorCallbacks = {
    {
        name = "onEntityKOed",
        func = function(entityId, revivedId)
            if entityId == mission.data.custom.patrolId then
                local patrol = Entity(mission.data.custom.patrolId)
                if patrol then
                    registerFriends(patrol)
                end

                startOption8PatrolDialog2()
            end
        end
    }
}
mission.phases[12].onTargetLocationLeft = function()
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(12)
end
mission.phases[12].onRestore = function()
    local x, y = findNearbyEmptySector()
    mission.data.location = {x = x, y = y}

    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.description[3].visible = false
    setPhase(12)
end
mission.phases[12].showUpdateOnEnd = true


-- patrol dialog
local option8PatrolDialogOnEndFight = makeDialogServerCallback("option8PatrolDialogOnEndFight", 12, function()
    local patrol = Entity(mission.data.custom.patrolId)
    if patrol then
        local ai = ShipAI(patrol)
        ai:setAggressive()
        registerEnemies(patrol)
    end
end)

local option8PatrolDialogOnEndBribe = makeDialogServerCallback("option8PatrolDialogOnEndBribe", 12, function()
    -- player pays bribe
    local player = Player()
    player:pay("Paid a bribe of %1% Credits."%_T, mission.data.custom.bribe)

    mission.data.location = mission.data.custom.location
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.targets = {}
    goToNextStep()
end)

function startOption8PatrolDialog()
    if onServer() then
        setBribeMoney()
        invokeClientFunction(Player(), "startOption8PatrolDialog")
        return
    end

    local dialog8_0 = {}
    local dialog8_1 = {}
    local dialog8_2 = {}
    local dialog8_3 = {}
    local dialog8_4 = {}
    local dialog8_5 = {}
    local dialog8_6 = {}
    local dialog8_7 = {}
    local dialog8_8 = {}
    local dialog8_9 = {}

    dialog8_0.text = "Who are you and what do you want?"%_t
    dialog8_0.answers = {{answer = "We're looking for someone: ${target} ${name}."%_t % {target = (mission.data.custom.targetTitle or "")%_t, name = mission.data.custom.targetName}, followUp = dialog8_1}}

    dialog8_1.text = "We don't care."%_t
    dialog8_1.answers = {{answer = "Have you seen them?"%_t, followUp = dialog8_2}}

    dialog8_2.text = "Oh, we see everyone who passes through here.\n\nAnd we've seen the ones you're looking for, we even know where they went.\n\nBut why would we tell you anything?"%_t

    dialog8_2.answers = {}
    if mission.data.custom.bribe and mission.data.custom.bribe >= 100 then
        table.insert(dialog8_2.answers, {answer = "[Transfer ${bribe}¢]"%_t % {bribe = mission.data.custom.bribe}, followUp = dialog8_5})
    end

    table.insert(dialog8_2.answers, {answer = "You won't get destroyed."%_t, followUp = dialog8_3})

    dialog8_3.text = "Are you threatening us?"%_t
    dialog8_3.answers = {{answer = "Yes."%_t, followUp = dialog8_4}}

    dialog8_4.text = "Wrong move, buddy. We're going to obliterate your ship!"%_t
    dialog8_4.onEnd = option8PatrolDialogOnEndFight

    dialog8_5.text = "It seems you really needed this information. We wouldn’t want to cause you any more distress.\n\nOur scanners showed that they went to sector (${x}:${y}).\n\nHave a safe trip."%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    dialog8_5.answers = {{answer = "Thank you. You too."%_t}}
    dialog8_5.onEnd = option8PatrolDialogOnEndBribe

    ScriptUI(mission.data.custom.patrolId):interactShowDialog(dialog8_0, false)
end

function setBribeMoney()
    local player = Player()
    local faction = player.craftFaction
    local factionMoney = faction.money

    mission.data.custom.bribe = 5000 * Balancing_GetSectorRichnessFactor(Sector():getCoordinates())

    if factionMoney <= mission.data.custom.bribe then
        mission.data.custom.bribe = math.floor(factionMoney * 0.25)
    end

    mission.data.custom.bribe = makePrettyNumber(mission.data.custom.bribe)

    sync()
end
callable(nil, "setBribeMoney")

local option8PatrolDialog2OnEnd = makeDialogServerCallback("option8PatrolDialog2OnEnd", 12, function()
    mission.data.location = mission.data.custom.location
    mission.data.description[3].visible = false
    mission.data.description[2].arguments = {x = mission.data.location.x, y = mission.data.location.y}
    mission.data.description[2].fulfilled = false
    mission.data.targets = {}
    goToNextStep()
end)

function startOption8PatrolDialog2()
    if onServer() then
        invokeClientFunction(Player(), "startOption8PatrolDialog2")
        return
    end

    local dialog8_1 = {}

    dialog8_1.text = "All right, all right, we get it!\n\nThe ones you're looking for went to sector (${x}:${y}).\n\nJust leave us alone now!"%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    dialog8_1.onEnd = option8PatrolDialog2OnEnd

    ScriptUI(mission.data.custom.patrolId):interactShowDialog(dialog8_1, false)
end

-- HELPER FUNCTIONS
--------------------------------------------
function goToNextStep()
    if #mission.data.custom.options > 0 then
        local nextStep = mission.data.custom.options[1]
        table.remove(mission.data.custom.options, 1)
        setPhase(nextStep)
    else
        setPhase(2) -- go to the final phase where the player catches his target
    end
end

function findNearbyEmptySector()
    local target = nil
    local cx, cy = Sector():getCoordinates()
    local playerInsideBarrier = MissionUT.checkSectorInsideBarrier(cx, cy)
    local otherMissionLocations = MissionUT.getMissionLocations()

    local test = function(x, y, regular, offgrid, blocked, home, dust, factionIndex, centralArea)
        if regular then return end
        if blocked then return end
        if offgrid then return end
        if home then return end
        if Balancing_InsideRing(x, y) ~= playerInsideBarrier then return end
        if otherMissionLocations:contains(x, y) then return end

        return true
    end

    local specs = SectorSpecifics(cx, cy, GameSeed())

    for i = 0, 20 do
        local target = specs:findSector(random(), cx, cy, test, 20 + i * 15, i * 15)

        if target then
            return target.x, target.y
        end
    end

    -- cancel mission if we can't find a location
    if not target then
        print ("Bounty Hunting Mission: Error: couldn't find location")
        -- function is called by makeBulletin as well => if we aren't attached to a player yet we simply return
        if not Player() then return end

        sendTargetEliminatedMail()
        mission.data.reward.credits = mission.data.reward.credits * 0.3
        reward()
        terminate()
    end
end

function sendTargetEliminatedMail()
    if onClient() then return end

    local mail = Mail()
    mail.text = Format("Dear Contractor,\n\nSomebody else has already eliminated the target.\nWe've sent you some money as compensation for your efforts.\n\nSincerely,\n%1%"%_T, mission.data.custom.employerName or "")
    mail.header = "Contract Canceled /* Mail Subject */"%_T
    mail.sender = mission.data.custom.employerName
    mail.id = "BountyHunt_3"

    Player():addMail(mail)
end

-- SPAWN FUNCTIONS:
-----------------------------------------------------------
-- spawn freighter
-----------------------------------------------------------
function findOrSpawnFreighter()
    if mission.data.custom.freighterId then
        if Entity(mission.data.custom.freighterId) then
            mission.data.custom.freighterId = Entity(mission.data.custom.freighterId).id.string
            return
        end
    end

    local x, y = Sector():getCoordinates()
    local faction = Galaxy():getNearestFaction(x, y)
    local translation = random():getDirection() * 1000
    local position = MatrixLookUpPosition(-translation, vec3(0, 1, 0), translation)
    local freighter = ShipGenerator.createFreighterShip(faction, position)

    freighter:removeScript("data/scripts/entity/civilship.lua")
    freighter:removeScript("data/scripts/entity/dialogs/storyhints.lua")
    freighter:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")
    freighter:addScriptOnce("data/scripts/entity/utility/basicinteract.lua")
    mission.data.custom.freighterId = freighter.id.string
    freighter.dockable = false
    freighter.invincible = true
    Boarding(freighter).boardable = false
end

-- mothership
-----------------------------------------------------------
function onMothershipCreated(generated)
    if not valid(generated) then return end

    if mission.data.custom.targetTitleIndex < 4 then
        generated.title = "Renegade Leader /* meaning 'leader of the renegades'*/"%_t
    else
        generated.title = "${target} ${name}"%_t % {target = (mission.data.custom.targetTitle or "")%_t, name = mission.data.custom.targetName}
    end

    generated.factionIndex = mission.data.custom.targetFaction
    mission.data.custom.mothershipId = generated.id.string
    local ai = ShipAI(generated.id)
    local player = Player()
    ai:setPassiveShooting(false)
    ai:registerFriendFaction(mission.data.custom.targetFaction)
    registerFriends(generated.id)

    generated.invincible = true
    generated:setValue("is_mothership", true)
    generated:setValue("is_wave", true)
    generated.dockable = false
    generated:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")

    local bossLoot = Loot(generated.id)

    -- adds legendary turret drop
    generated:addScriptOnce("internal/common/entity/background/legendaryloot.lua", 0.05)

    for _, turret in pairs(WaveUtility.generateTurrets()) do
        bossLoot:insert(turret)
    end

    mission.data.custom.mothershipGenerated = true
end

-- mothership backup
-----------------------------------------------------------
function findOrSpawnMothershipBackup(numShips)
    if onClient() then return end

    local cavaliers = {Sector():getEntitiesByScriptValue("mothership_backup", true)}
    if #cavaliers >= 2 then return end

    local faction
    if mission.data.custom.targetTitleIndex == 1 then
        local factionName = "Former Cavaliers"%_T%_T
        faction = findOrCreateFaction(factionName)
        mission.data.custom.targetFaction = faction.index
        mission.data.custom.targetShipName = "Former Cavaliers Soldier"%_T

    elseif mission.data.custom.targetTitleIndex == 2 then
        local factionName = "Former Family"%_T
        faction = findOrCreateFaction(factionName)
        mission.data.custom.targetFaction = faction.index
        mission.data.custom.targetShipName = "Former Family Associate"%_T

    elseif mission.data.custom.targetTitleIndex == 3 then
        local factionName = "Former Commune"%_T
        faction = findOrCreateFaction(factionName)
        mission.data.custom.targetFaction = faction.index
        mission.data.custom.targetShipName = "Former Commune Comrade"%_T

    else
        local factionName = "Pirates"%_T
        faction = findOrCreateFaction(factionName)
        mission.data.custom.targetFaction = faction.index
        mission.data.custom.targetShipName = "Pirate"%_T
    end

    local generator = AsyncShipGenerator(nil, onMothershipBackupSpawned)
    local volume = Balancing_GetSectorShipVolume(Sector():getCoordinates()) * 1.5

    generator:startBatch()
    for i = 1, numShips do
        local translation = random():getDirection() * 1000
        local position = MatrixLookUpPosition(-translation, vec3(0, 1, 0), translation)
        generator:createMilitaryShip(faction, position, volume)
    end

    generator:endBatch()
end

function findOrCreateFaction(factionName)
    faction = Galaxy():findFaction(factionName)
    if not faction then
        local x, y = Sector():getCoordinates()
        faction = Galaxy():createFaction(factionName, x, y)
        faction.initialRelations = 0
        faction.initialRelationsToPlayer = 0
        faction.staticRelationsToPlayers = true
    end

    return faction
end

function onMothershipBackupSpawned(ships)
    mission.data.custom.mothershipBackup = {}
    local player = Player()

    for _, ship in pairs(ships) do
        ship.title = mission.data.custom.targetShipName
        ship.damageMultiplier = 1
        ship:setValue("is_wave", true)
        ship:setValue("mothership_backup", true)
        ship:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")

        local ai = ShipAI(ship)
        local player = Player()
        ai:setIdle()
        ai:registerFriendFaction(mission.data.custom.targetFaction)
        registerFriends(ship)

        table.insert(mission.data.custom.mothershipBackup, ship.id.string)
    end
end

-- military ship
-----------------------------------------------------------
function findOrSpawnPatrolShip()
    local faction = MissionUT.getMissionFaction()
    local shipName = "Patrol Unit ${name}"%_T % {name = makeRandomNames()}

    local ships = {Sector():getEntitiesByType(EntityType.Ship)}
    for _, p in pairs(ships) do
        if p.title == shipName then
            mission.data.custom.patrolId = p.id.string
            return
        end
    end

    local volume = Balancing_GetSectorShipVolume(Sector():getCoordinates()) * 3

    local translation = random():getDirection() * 1000
    local position = MatrixLookUpPosition(-translation, vec3(0, 1, 0), translation)

    local ship = ShipGenerator.createMilitaryShip(faction, position, volume)

    ship.title = shipName
    ship:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")
    ship:addScriptOnce("data/scripts/entity/utility/kobehavior.lua")
    ship:addScriptOnce("data/scripts/entity/utility/basicinteract.lua")

    ShipAI(ship.id.string):setIdle()

    mission.data.custom.patrolId = ship.id.string
    sync()
end

-- containerfield with asteroids
-----------------------------------------------------------
function spawnTemporaryContainers()
    local generator = SectorGenerator(Sector():getCoordinates())

    local containers = {}
    containers = generator:createContainerField(nil, nil, 1)

    local sector = Sector()
    sector:addScriptOnce("sector/deleteentitiesonplayersleft.lua", {EntityType.Container})
end

-- package in container
-----------------------------------------------------------
function bountyHuntPackage()
    local package = VanillaInventoryItem()

    package.stackable = false
    package.name = "Empty Package"%_t

    package.rarity = Rarity(RarityType.Common)
    package:setValue("bountyHuntItem", true)
    package.icon = "data/textures/icons/crate.png"
    package.iconColor = package.rarity.color
    package.price = 0
    package.tradeable = false
    package.droppable = false
    package.missionRelevant = true
    package:setTooltip(makebountyHuntPackageTooltip(package))

    return package
end

function makebountyHuntPackageTooltip(package)
    local tooltip = Tooltip()
    tooltip.icon = package.icon

    local title = package.name

    local headLineSize = 25
    local headLineFontSize = 15
    local line = TooltipLine(headLineSize, headLineFontSize)
    line.ctext = title
    line.ccolor = package.rarity.color
    tooltip:addLine(line)

    -- empty line
    tooltip:addLine(TooltipLine(14, 14))
    local line = TooltipLine(18, 14)
    line.ltext = "This package is empty."%_t
    tooltip:addLine(line)
    -- empty line
    tooltip:addLine(TooltipLine(14, 14))
    local line = TooltipLine(20, 14)
    line.ltext = "Origin: sector (${x}:${y})"%_t % {x = mission.data.custom.location.x, y = mission.data.custom.location.y}
    tooltip:addLine(line)

    return tooltip
end

-- wreckages
-----------------------------------------------------------
function spawnWreckages(numWreckages)
    local generator = SectorGenerator(Sector():getCoordinates())
    for i = 1, numWreckages do
        local wreckage = generator:createWreckage(BlackMarketUT.getCavaliersFaction(), nil, 0)
        wreckage:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")
        wreckage:removeScript("data/scripts/entity/story/captainslogs.lua")
        if i == 1 then
            wreckage:addScriptOnce("data/scripts/entity/story/storyhintwreckage.lua")
            mission.data.custom.firstWreck = wreckage.id.string
        end
    end
end

-- normal pirate wave
-----------------------------------------------------------
function onPirateWaveGenerated(entities)
    mission.data.custom.wavePirates = {}
    for  _, pirate in pairs(entities) do
        if not valid(pirate) then return end
        pirate:setValue("is_wave", true)
        pirate:addScriptOnce("data/scripts/entity/deleteonplayersleft.lua")
        if mission.data.custom.piratesAggressive == true then
            registerEnemies(pirate)
        else
            registerFriends(pirate)
        end

        table.insert(mission.data.custom.wavePirates, pirate.id.string)
    end

    mission.data.custom.waveGenerated = true
end

-- wave encounters
-----------------------------------------------------------
function resetWaveData()
    -- reset all values
    mission.data.custom.waitTime = 0
    mission.data.custom.dialogStarted = false
    mission.data.custom.readyForDialog = false
    mission.data.custom.piratesAggressive = false
    mission.data.custom.endDialogStarted = false
    mission.data.custom.wave1Spawned = false
    mission.data.custom.wave2Spawned = false
    mission.data.custom.wavePirates = {}
    mission.data.custom.waveNumber = 1
    mission.data.custom.waves = {}
    mission.data.custom.waveGenerated = false
    mission.data.custom.allDefeated = false
    mission.data.targets = {}
end

function updateWaveEncounter()
    if MissionUT.playerInTargetSector(Player(), mission.data.location) then
        local count = WaveUtility.getNumEnemies()
        if not mission.data.custom.wave1Spawned then
            mission.data.custom.waves = WaveUtility.getWaves(nil, 2)
            local newWave = mission.data.custom.waves[mission.data.custom.waveNumber]            
            if not newWave then print("Oh no, no first wave " .. mission.data.custom.waveNumber) return end
            if #newWave < 3 then table.insert(newWave, 1) end

            WaveUtility.createPirateWave(nil, newWave, onPirateWaveGenerated)
            mission.data.custom.wave1Spawned = true
            count = WaveUtility.getNumEnemies()
        end

        if mission.data.custom.wave1Spawned == true and mission.data.custom.readyForDialog == false then
            if #mission.data.custom.wavePirates > 0 then
                local entity = Sector():getEntity(mission.data.custom.wavePirates[1])
                if valid(entity) then
                    mission.data.custom.waitTime = mission.data.custom.waitTime + 1
                    if mission.data.custom.waitTime == 5 then
                        mission.data.custom.readyForDialog = true
                        sync()
                    end
                end
            end
        end

        if mission.data.custom.waveGenerated == true and count == 0 then
            mission.data.custom.allDefeated = true

        elseif count <= 2 and mission.data.custom.waveGenerated == true and not mission.data.custom.wave2Spawned then
            mission.data.custom.wave2Spawned = true
            mission.data.custom.waveNumber = mission.data.custom.waveNumber + 1
            if not mission.data.custom.waves then mission.data.custom.waves = WaveUtility.getWaves(nil, 2) end

            local newWave = mission.data.custom.waves[mission.data.custom.waveNumber]
            if not newWave then print("Oh no, no 2nd wave ".. mission.data.custom.waveNumber) return end

            WaveUtility.createPirateWave(nil, mission.data.custom.waves[mission.data.custom.waveNumber], onPirateWaveGenerated)
        end
    end
end

function registerEnemies(shipId)
    local player = Player()
    local ai = ShipAI(shipId)
    if not ai then return end

    ai:setAggressive()
    ai:registerEnemyFaction(player.index)
    if player.allianceIndex then
        ai:registerEnemyFaction(player.allianceIndex)
    end
end

function registerFriends(shipId)
    local player = Player()
    local ai = ShipAI(shipId)
    if not ai then return end

    ai:setIdle()
    ai:registerFriendFaction(player.index)
    if player.allianceIndex then
        ai:registerFriendFaction(player.allianceIndex)
    end
end

function makeRandomNames()
    local numbers = "0123456789"
    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

    local s1 = random():getInt(1, #letters)
    local s2 = random():getInt(1, #letters)
    local s3 = random():getInt(1, #numbers)
    local s4 = random():getInt(1, #numbers)
    local s5 = random():getInt(1, #letters)
    local s6 = random():getInt(1, #letters)
    local s7 = random():getInt(1, #letters)
    local combination = "" .. letters:sub(s1, s1) .. letters:sub(s2, s2) .. numbers:sub(s3, s3) .. numbers:sub(s4, s4) .. letters:sub(s5, s5) .. letters:sub(s6, s6) .. letters:sub(s7, s7)

    return combination
end

function makePrettyNumber(number)
    if not number then return end

    -- round the number to the next round number, e.g. 5234 to 5000
    local tmp = number / 1000
    if tmp >= 1 then
        tmp = math.floor(tmp)
        number = tmp * 1000
    else
        tmp = number/100
        if tmp >= 1 then
            tmp = math.floor(tmp)
            number = tmp * 100
        else
            tmp = number / 10
            if tmp >= 1 then
                tmp = math.floor(tmp)
                number = tmp * 100
            end
        end
    end

    return number
end

-- calculate mission data
--------------------------------------------
function calculateMissionData(station)
    -- find a random employer:
    mission.data.custom.possibleEmployers = {"The Cavaliers"%_T, "The Family"%_T, "The Commune"%_T, Faction(station.factionIndex).name}
    mission.data.custom.employerNumber = random():getInt(1, 4)
    mission.data.custom.employerName = mission.data.custom.possibleEmployers[mission.data.custom.employerNumber]

    -- find a random target, but make sure target and employer are not the same
    mission.data.custom.possibleTargets = {"The renegades of the Cavaliers"%_T, "The renegades of the Family"%_T, "The renegades of the Commune"%_T, "Admiral"%_T, "Commander"%_T, "Captain"%_T, "Don"%_T, "Baron"%_T, "The Great"%_T}
    mission.data.custom.targetTitleIndex = random():getInt(1, 9)
    if mission.data.custom.targetTitleIndex == mission.data.custom.employerNumber and mission.data.custom.targetTitleIndex < 4 then
        mission.data.custom.targetTitleIndex = mission.data.custom.targetTitleIndex + 1
    end

    mission.data.custom.targetTitle = mission.data.custom.possibleTargets[mission.data.custom.targetTitleIndex]
    mission.data.custom.targetName = " "

    if mission.data.custom.targetTitleIndex >= 4 then
        local language = Language()
        language.seed = random():createSeed()
        mission.data.custom.targetName = language:getName()
    end

    local x, y = findNearbyEmptySector()
    mission.data.custom.location = {x = x, y = y}
    -- calculate how many steps the mission will have
    mission.data.custom.numberOfSteps = random():getInt(2, 3)
    if Server():getValue("playAll_bountyhunt_test", true) then
        mission.data.custom.numberOfSteps = 8
    end

    -- decide which options will be played
    mission.data.custom.options = {3, 4, 5, 6, 7, 10, 11, 12} -- these numbers are the phases the options start at, don't change that unless you change the phases
    shuffle(random(), mission.data.custom.options)

    local stepsToRemove = #mission.data.custom.options - mission.data.custom.numberOfSteps
    for i = 1, stepsToRemove do
        table.remove(mission.data.custom.options, #mission.data.custom.options)
    end
end

-- bulletin
--------------------------------------------
mission.makeBulletin = function(station)
    local x, y = findNearbyEmptySector()
    if not x and not y then return end
    if x == 0 and y == 0 then return end

    if not station then return end

    calculateMissionData(station)

    local rewardFactor = 1
    for _, step in pairs(mission.data.custom.options) do
        if step < 7 then
            rewardFactor = rewardFactor + 1
        elseif step == 7 then
            rewardFactor = rewardFactor + 4
        elseif step >= 12 then
            rewardFactor = rewardFactor + 2
        else
            rewardFactor = rewardFactor + 3
        end
    end

    local balancing = Balancing_GetSectorRewardFactor(Sector():getCoordinates())
    rewardFactor = rewardFactor * 5000 * balancing
    reward = {credits = makePrettyNumber(10000 * balancing + rewardFactor), relations = 7000 + (rewardFactor * 0.05)}
    local materialAmount = round(random():getInt(7000, 8000) / 100) * 100
    MissionUT.addSectorRewardMaterial(x, y, reward, materialAmount)


    local bulletin =
    {
        brief = "WANTED DEAD, NOT ALIVE"%_T,
        title = "WANTED DEAD, NOT ALIVE"%_T,
        reward = "¢${reward}"%_T,
        formatArguments = {x = x, y = y, reward = createMonetaryString(reward.credits)},
        description = "Looking for a bounty hunter.\n\nThe target is wanted for multiple crimes against civilians.\n\nMore details will follow once you accept the task."%_T,
        difficulty = "Medium /*difficulty"%_T,
        script = "data/scripts/player/missions/bountyhuntmission.lua",
        arguments = {{
            location = {x = x, y = y},
            giver = station.id,
            reward = reward,
            targetTitle = mission.data.custom.targetTitle  or "",
            targetName =  mission.data.custom.targetName,
            targetTitleIndex = mission.data.custom.targetTitleIndex,
            options = mission.data.custom.options,
            employerName = mission.data.custom.employerName
            }},
    }

    return bulletin
end

