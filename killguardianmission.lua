package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("structuredmission")
include("callable")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Guardian"%_T
mission.data.title = "The Guardian"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.description =
{
    "The source of the Xsotan is in the center of the galaxy."%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {text = "(optional) Find a Resistance Outpost and ask for help"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Kill the Guardian"%_T, bulletPoint = true, fulfilled = false, visible = false},
}

mission.data.custom.guardianSpawned = 0
mission.data.location = {x = 0, y = 0}

mission.globalPhase.updateTargetLocationServer = function()
    local guardian = {Sector():getEntitiesByScript("data/scripts/entity/story/wormholeguardian.lua")}

    if mission.data.custom.guardianSpawned == 0 and guardian[1] then
        mission.data.custom.guardianSpawned = 1
    end

    if mission.data.custom.guardianSpawned == 1 and not guardian[1] then
        accomplish()
    end
end

mission.globalPhase.onAccomplish = function()
    if onServer() then
        local player = Player()
        player:invokeFunction("storyquestutility.lua", "onKillGuardianAccomplished")
    end
end

-- send mail with info about guardian and outposts
mission.phases[1] = {}
mission.phases[1].onBeginServer = function()
    local player = Player()
    local mail = Mail()
    mail.text = Format("Hello!\n\nMy friend, I have one more adventure for you.\nOn my last tour to sell some sweet Avorion I came across this Resistance Outpost. They told me that they know that the Xsotan are guarding something in the center of the galaxy. Whenever they try to come close there’s tons of Xsotan.\n\nThey tried a lot to destroy this guardian, but until now nobody managed. Not the best warriors and not even the upgraded AI that they built.\n\nDo you think you could do it? Wouldn’t that be the adventure of a lifetime?\nI’d say go for it!\n\nGreetings and good luck!\n%1%"%_T, MissionUT.getAdventurerName())
    mail.header = "Destroy the Guardian /*Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_Kill_Guardian_Mission"
    player:addMail(mail)
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_Kill_Guardian_Mission" then
            setPhase(2)
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true
    mission.data.description[4].visible = true
end

