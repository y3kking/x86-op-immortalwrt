package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"

include("utility")
include("stringutility")
include("structuredmission")
include("callable")
local MissionUT = include("missionutility")
local RecallDeviceUT = include("recalldeviceutility")
local AdventurerGuide = include("story/adventurerguide")
local Hermit = include("data/scripts/entity/story/hermit")

--mission.tracing = true

abandon = nil -- this mission is not abandonable
mission.data.autoTrackMission = true
mission.data.brief = "The Hermit"%_T
mission.data.title = "The Hermit"%_T
mission.data.icon = "data/textures/icons/story-mission.png"
mission.data.priority = 10
mission.data.custom.consecutiveJumps = 0
mission.data.custom.location = {}
mission.data.description = {
    "The adventurer heard some interesting rumors. He thinks he knows someone that could help you find out more about the Xsotan."%_T,
    {text = "Read the Adventurer's mail"%_T, bulletPoint = true, fulfilled = false},
    {}, -- placeholder for adventurer meeting point in phase 1
    {text = "Wait for new information"%_T, bulletPoint = true, fulfilled = false, visible = false},
    {text = "Read the second mail"%_T, bulletPoint = true, fulfilled = false, visible = false},
}


mission.globalPhase.onAccomplish = function()
    local player = Player()
    player:invokeFunction("storyquestutility.lua", "onHermitAccomplished")
end

mission.phases[1] = {}
-- adventurer tells player about hermit
mission.phases[1].onBeginServer = function()
    -- find meet-up location
    local coords = {Sector():getCoordinates()}
    local x, y = findEmptySectorNearby(coords[1], coords[2])
    mission.data.custom.location = {x = x, y = y}
    local player = Player()
    mission.data.description[3] = {text = "Meet the Adventurer in sector (${xCoord}:${yCoord})"%_T, arguments = {xCoord = x, yCoord = y}, bulletPoint = true, visible = false}

    -- send player mail
    local mail = Mail()
    mail.text = Format("Hello!\n\nYou’ve found an interesting artifact. You should hang on to it! Meet me in sector (%1%:%2%). I‘ve found out a lot about the Xsotan! There is only one small hitch... Let's talk about that in person.\n\nGreetings,\n%3%"%_T, x, y, MissionUT.getAdventurerName())
    mail.header = "Need to talk /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_Hermit_Mission_1"
    player:addMail(mail)

    if not RecallDeviceUT.hasRecallDevice(player) then
        RecallDeviceUT.sendFollowUpToHermitMail(player)
    end
end
mission.phases[1].playerCallbacks = {}
mission.phases[1].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_Hermit_Mission_1" then
            nextPhase()
        end
    end
}
mission.phases[1].showUpdateOnEnd = true

-- create adventurer
mission.phases[2] = {}
mission.phases[2].onBeginServer = function()
    mission.data.location = mission.data.custom.location
    mission.data.description[2].fulfilled = true
    mission.data.description[3].visible = true
end
mission.phases[2].onTargetLocationEntered = function()
    if onServer() then
        createAdventurer()
    end
end
mission.phases[2].onTargetLocationEnteredReportedByClient = function()
    nextPhase()
end
mission.phases[2].noBossEncountersTargetSector = true
mission.phases[2].noPlayerEventsTargetSector = true
mission.phases[2].showUpdateOnEnd = true

-- talk with adventurer - nextPhase in end of talk
mission.phases[3] = {}
mission.phases[3].onBeginServer = function()
    local adventurer = Sector():getEntitiesByScript("data/scripts/entity/story/missionadventurer.lua")
    if not adventurer then createAdventurer() end
end
local adventurerDialogStarted = false
mission.phases[3].updateClient = function()
    local adventurer = Sector():getEntitiesByScript("data/scripts/entity/story/missionadventurer.lua")
    if not adventurer then return end

    if not adventurerDialogStarted then
        adventurer:invokeFunction("story/missionadventurer.lua", "setData", true, false, createAdventurerDialog())
        adventurerDialogStarted = true
    end
end
mission.phases[3].onRestore = function()
    if atTargetLocation() then
        if onServer() then
            -- new location and send player there
            local cx, cy = Sector():getCoordinates()
            local x, y = findEmptySectorNearby(cx, cy)
            mission.data.location = {x = x, y = y}
            mission.data.custom.location = mission.data.location
            mission.data.description[3].arguments = {xCoord = x, yCoord = y}
            setPhase(2)
        end
    end
end
mission.phases[3].onStartDialog = function(entityId)
    local adventurer = Sector():getEntitiesByScript("data/scripts/entity/story/missionadventurer.lua")
    if adventurer and adventurer.id == entityId then
        adventurer:invokeFunction("story/missionadventurer.lua", "setData", true, false, createAdventurerDialog())
    end
end
mission.phases[3].onTargetLocationLeft = function()
    if onServer() then
        setPhase(2)
    end
end

-- waiting period
mission.phases[4] = {}
mission.phases[4].onBeginServer = function()
    mission.data.description[3].fulfilled = true
    mission.data.description[4].visible = true
    mission.data.location = nil
end
mission.phases[4].onSectorEnteredReportedByClient = function()
    mission.data.custom.consecutiveJumps = mission.data.custom.consecutiveJumps + 1

    if mission.data.custom.consecutiveJumps == 1 then
        mission.data.location = nil
    end
    if mission.data.custom.consecutiveJumps >= 3 then
        mission.data.description[4].fulfilled = true
        nextPhase()
    end
end
mission.phases[4].showUpdateOnEnd = true

-- give player loation
mission.phases[5] = {}
mission.phases[5].onBeginServer = function()

    -- find meet-up location
    local xSpawn, ySpawn = Hermit.getLocation(Sector():getCoordinates())
    mission.data.custom.location = {x = xSpawn, y = ySpawn}
    local player = Player()
    player:invokeFunction("storyquestutility.lua", "onHermitLocationCalculated", mission.data.custom.location.x, mission.data.custom.location.y)
    local player = Player()
    mission.data.description[5].visible = true
    mission.data.description[6] = {text = "Meet the Hermit in sector (${xCoord}:${yCoord})"%_T, arguments = {xCoord = mission.data.custom.location.x, yCoord = mission.data.custom.location.y}, bulletPoint = true, visible = false}

    -- send player mail with location
    local mail = Mail()
    mail.text = Format("Hello!\n\nThe person who might help us is known as the Hermit. He lives in sector (%1%:%2%). Look for the giant asteroid he has made his home.\n\nGreetings,\n%3%"%_T, mission.data.custom.location.x, mission.data.custom.location.y, MissionUT.getAdventurerName())
    mail.header = "Meet Up Location /* Mail Subject */"%_T
    mail.sender = Format("%1%, the Adventurer"%_T, MissionUT.getAdventurerName())
    mail.id = "Story_Hermit_Mission_2"
    player:addMail(mail)
end
mission.phases[5].playerCallbacks = {}
mission.phases[5].playerCallbacks[1] =
{
    name = "onMailRead",
    func = function(playerIndex, mailIndex, mailId)
        if mailId == "Story_Hermit_Mission_2" then
            nextPhase()
        end
    end
}
mission.phases[5].showUpdateOnEnd = true

-- create hermit
mission.phases[6] = {}
mission.phases[6].onBeginServer = function()
    -- these have to be here for testing
    mission.data.description[5].fulfilled = true
    mission.data.description[6].visible = true
    mission.data.location = mission.data.custom.location
end
mission.phases[6].onTargetLocationEntered = function()
    if onServer() then
        local hermit = Hermit.spawn()
        mission.data.custom.hermitId = hermit.id.string
    end
end
mission.phases[6].onTargetLocationEnteredReportedByClient = function()
    mission.data.description[5].fulfilled = true
    nextPhase()
end

mission.phases[6].noBossEncountersTargetSector = true
mission.phases[6].noPlayerEventsTargetSector = true
mission.phases[6].showUpdateOnEnd = true

-- talk with hermit - accomplish on talking finished
mission.phases[7] = {}
local dialogStarted
mission.phases[7].updateClient = function()
    if not dialogStarted then
        if not mission.data.custom.hermitId then return end
        local scriptUi = ScriptUI(mission.data.custom.hermitId)
        if not scriptUi then return end
        scriptUi:interactShowDialog(createHermitDialog(), false)
        dialogStarted = true
    end
end
mission.phases[7].onStartDialog = function(entityId)
    if tostring(entityId) == mission.data.custom.hermitId then
        local scriptUi = ScriptUI(mission.data.custom.hermitId)
        if not scriptUi then return end
        scriptUi:interactShowDialog(createHermitDialog(), false)
    end
end
mission.phases[7].onRestore = function()
    if onServer() then
        local x, y = Sector():getCoordinates()
        if x == mission.data.location.x and y == mission.data.location.y then
            local hermit = Hermit.spawn()
            mission.data.custom.hermitId = hermit.id.string
        end
    end

    dialogStarted = false
end


-- helper functions
function createAdventurer()
    local adventurer = AdventurerGuide.spawnOrFindMissionAdventurer(Player())
    if not adventurer then
        setPhase(2) -- try again on re-enter
        return
    end
    if not adventurer then return end
    adventurer.invincible = true
    adventurer.dockable = false
    MissionUT.deleteOnPlayersLeft(adventurer)
    mission.data.custom.adventurerId = adventurer.id
    adventurer:invokeFunction("story/missionadventurer.lua", "setInteractingScript", "player/story/hermitmission.lua")
    sync()
end

local onAdventurerDialogEnd = makeDialogServerCallback("onAdventurerDialogEnd", 3, function()
    setPhase(4)
end)

local onHermitDialogEnd = makeDialogServerCallback("onHermitDialogEnd", 7, function()
    accomplish()
end)

function createAdventurerDialog()
    local d0_HiThere = {}
    local d1_IveManaged = {}
    local d2_TheGoodNews = {}
    local d3_TheBadNews = {}
    local d4_DoYouKnow = {}
    local d5_WeCant = {}
    local d6_IHaveHeard = {}
    local d7_Yes = {}

    d0_HiThere.text = "Hello! Thank you for coming!"%_t
    d0_HiThere.answers = {
        {answer = "What’s up?"%_t, followUp = d1_IveManaged},
        {answer = "Sure!"%_t, followUp = d1_IveManaged}
    }
    d0_HiThere.onEnd = onAdventurerDialogEnd

    d1_IveManaged.text = "I’ve managed to find out something interesting! There is good news and bad news."%_t
    d1_IveManaged.answers = {{answer = "Tell me, please!"%_t, followUp = d2_TheGoodNews}}

    d2_TheGoodNews.text = "The good news is that I know where the Xsotan might have their bases."%_t
    d2_TheGoodNews.answers = {{answer = "That’s great!"%_t, followUp = d3_TheBadNews}}

    d3_TheBadNews.text = "The bad news is that they are coming from the other side of the Barrier."%_t
    d3_TheBadNews.answers = {{answer = "That sounds bad."%_t, followUp = d4_DoYouKnow}}

    d4_DoYouKnow.text = "Do you know what the Barrier is?"%_t
    d4_DoYouKnow.answers = {
        {answer = "I’m not sure..."%_t, followUp = d5_WeCant},
        {answer = "I've heard of it."%_t, followUp = d6_IHaveHeard}
    }

    d5_WeCant.text = "We can’t jump to the center of the galaxy anymore. The sectors there are not normal sectors, they are more like rifts that you can’t jump into or across. \n\nThe ring around the center is called the Barrier. I don’t really know much about this. But there is more good news!"%_t
    d5_WeCant.answers = {{answer = "Tell me."%_t, followUp = d6_IHaveHeard}}

    d6_IHaveHeard.text = "I have heard of somebody who knows a lot about the Barrier."%_t
    d6_IHaveHeard.answers = {{answer ="Will he help us?"%_t, followUp = d7_Yes}}

    d7_Yes.text = "I hope so. We should definitely go talk to him. I need to find out where exactly we can find him. \n\nOnce I've done this I’ll send you an email with the coordinates of his location."%_t
    d7_Yes.answers = {{answer = "See you soon."%_t}}

    return d0_HiThere
end

function createHermitDialog()
    local d0_WhyAreYou = {}
    local d1_NowThat = {}
    local d2_TheBarrier = {}
    local d3_TheUnitedAlliances = {}
    local d4_AsFarAs = {}
    local d5_Yes = {}
    local d6_Sadly = {}
    local d7_SinceThe = {}
    local d8_YesALot = {}
    local d9_IMSure = {}

    d0_WhyAreYou.text = "Why are you disturbing my solitude?"%_t
    d0_WhyAreYou.answers = {
        {answer = "I’m sorry. Should I leave?"%_t, followUp = d1_NowThat},
        {answer = "I heard you know a lot of things."%_t, followUp = d1_NowThat}
    }

    d1_NowThat.text = "Now that I was disturbed in my meditations already, I might as well talk to you."%_t
    d1_NowThat.answers = {{answer ="Tell me about the barrier."%_t, followUp = d2_TheBarrier}}

    d2_TheBarrier.text = "The Barrier? The Barrier is a ring of torn Hyperspace fabric around the center of the galaxy. \n\nIt appeared after what is generally called the Event, 200 years ago."%_t
    d2_TheBarrier.answers = {{answer = "What happened?"%_t, followUp = d3_TheUnitedAlliances}}

    d3_TheUnitedAlliances.text = "The United Alliances were fighting a Great War against the Xsotan. \n\nThe Xsotan were losing, they were being pushed back towards the center of the galaxy. Suddenly, there was a great shudder in the energy tissue of the galaxy.\n\nThe next thing that is known is that a lot of rifts had appeared everywhere and that the center and everyone in it was cut off from the outer reaches by a Barrier that nobody except the Xsotan could cross."%_t
    d3_TheUnitedAlliances.answers = {{answer = "What happened in the center?"%_t, followUp = d4_AsFarAs}}

    d4_AsFarAs.text = "As far as we know, they are still there. A couple of decades ago, one of their ships crossed the Barrier. \n\nThe crew told us they thought they were on a suicide mission. \n\nThe factions on the inside believe that the Event destroyed everything outside of the Barrier and that the entire galaxy has shrunk to the size of the center."%_t
    d4_AsFarAs.answers = {{answer = "They can cross it?"%_t, followUp = d5_Yes}}

    d5_Yes.text = "Yes, they have a material they are calling ‘Avorion’, which apparently was created during the Event, and which allows them to cross the Barrier."%_t
    d5_Yes.answers = {{answer = "They brought it out here?"%_t, followUp = d6_Sadly}}

    d6_Sadly.text = "Sadly, the Avorion they brought was destroyed when scientists began fighting over it because they wanted to experiment on it. \n\nThis is exactly why I’m a Hermit. I’ll stay away from all this stupidity."%_t
    d6_Sadly.answers = {
        {answer = "Experiments are important!"%_t, followUp = d7_SinceThe},
        {answer = "I understand your aversion."%_t, followUp = d7_SinceThe}
    }

    d7_SinceThe.text = "Since the factions inside the Barrier won’t bring any Avorion out to us, the only way to get in might be Xsotan technology."%_t
    d7_SinceThe.answers = {{answer ="You mean Xsotan artifacts?"%_t, followUp = d8_YesALot}}

    d8_YesALot.text = "Yes. There are some that are looking for ways to get to the core, and apparently there are Xsotan artifacts that will allow you to do just that. \n\nI know of one such artifact that is for sale. I can send you an email with the details if you like?"%_t
    d8_YesALot.answers = {{answer = "Thank you so much!"%_t, followUp = d9_IMSure}}

    d9_IMSure.text = "I’m sure the factions that live on the inside of the Barrier would be eternally grateful to you if you could show them that the galaxy outside of the Barrier still exists."%_t
    d9_IMSure.onEnd = onHermitDialogEnd

    return d0_WhyAreYou
end

function findEmptySectorNearby(x, y, offset)
    local offset = offset or 0

    local xCoord, yCoord = MissionUT.getSector(x, y, 3, 7 + offset, false, false, false, false)
    if not xCoord or not yCoord then
        if offset > 100 then return nil, nil end -- break off if there's no chance of success

        findEmptySectorNearby(x, y, offset + 1)
    end

    return xCoord, yCoord
end
