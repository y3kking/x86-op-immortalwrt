package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("callable")

local MissionUT = include("missionutility")

-- this is a collection of all important mission data.
-- this should contain:
-- * "location.x", "location.y" or location should be nil
-- * "brief" for the brief description of the mission
-- * "description" for the long description of the mission
-- * "title" that will be shown upon completion/abandonment/failing/starting
-- * "justStarted"  that should be set to true in the "initialize" function when the
--                  mission is first initialized.
--                  this variable will be reset to nil upon synchronizing and is
--                  meant for the client to detect when the mission has just started,
--                  so it can display the "NEW MISSION: [Title]" text.
-- * "autoTrackMission" set to true to have mission automatically be tracked for the player
--                  IF he currently has no other mission tracked
missionData = {}
missionData.brief = ""
missionData.description = ""
missionData.title = ""
missionData.location = nil -- use something like {x = 2, y = -300}
missionData.justStarted = nil
missionData.timeLimit = nil
missionData.timePassed = nil
missionData.interactions = {}
missionData.timers = {}
missionData.fulfilled = false
missionData.autoTrackMission = false



-- call this function if you want to activate several comfortable callbacks
-- onTargetLocationEntered(x, y) will be called if missionData.location is set and the player enters the sector
function initMissionCallbacks()
    if onClient() then
        Player():registerCallback("onStartDialog", "Mission_onStartDialog")
        Player():registerCallback("onPostRenderHud", "Mission_onPostRenderHud")
    end

    if onServer() then
        Player():registerCallback("onSectorEntered", "Mission_onSectorEntered")
    end
end

function updateMission(timeStep)
    if missionData.timeLimit then
        missionData.timePassed = (missionData.timePassed or 0) + timeStep

        if missionData.timePassed > missionData.timeLimit then
            if missionData.fulfilled and (missionData.fulfilled == 1 or missionData.fulfilled == true) then
                finish()
            else
                fail()
            end
        end
    end

    for key, timer in pairs(missionData.timers) do
        timer.count = timer.count or 0
        timer.count = timer.count + timeStep
        timer.time = timer.time or 0

        if timer.count > timer.time then
            if timer.callback then
                timer.callback()
            end

            missionData.timers[key] = nil
        end

    end
end

function addTimer(time, callback)
    table.insert(missionData.timers, {time = time, callback = callback})
end

function addDialogInteraction(text, callback, entityId, x, y, test)
    missionData.interactions = missionData.interactions or {}

    -- don't add the same interaction twice
    for _, interaction in pairs(missionData.interactions) do
        if interaction.text == text
                and interaction.callback == callback
                and interaction.x == x
                and interaction.y == y
                and interaction.entity == entityId then
            return
        end
    end

    table.insert(missionData.interactions, {text = text, callback = callback, x = x, y = y, entity = entityId, test = test})
end

if onClient() then

function sync(data_in)
    if data_in then
        missionData = data_in

        if onSync then onSync() end
        if updateDescription then updateDescription() end

        if missionData.justStarted then
            showMissionStarted()

            -- check if we can track mission:
            -- * no other mission is currently being tracked
            -- * mission has autoTrack enabled
            if onClient() then
                if missionData.autoTrackMission and not getTrackedMissionScriptIndex() then
                    setTrackThisMission()
                end
            end
        end
    else
        invokeServerFunction("sync")
    end
end

else

function sync()
    local player
    if callingPlayer then
        player = Player(callingPlayer)
    else
        player = Player()
    end

    invokeClientFunction(player, "sync", missionData)

    missionData.justStarted = nil
end
callable(nil, "sync")

end

function showMissionStarted(text)
    if onServer() then
        invokeClientFunction(Player(), "showMissionStarted", text)
        return
    end

    displayMissionAccomplishedText("NEW MISSION"%_t, (text or missionData.title or "")%_t % missionData)
end

function showMissionAccomplished(text)
    if onServer() then
        invokeClientFunction(Player(), "showMissionAccomplished", text)
        return
    end

    displayMissionAccomplishedText("MISSION ACCOMPLISHED"%_t, (text or missionData.title or "")%_t % missionData)
    playSound("interface/mission-accomplished", SoundType.UI, 1)
end

function showMissionFailed(text)
    if onServer() then
        invokeClientFunction(Player(), "showMissionFailed", text)
        return
    end

    displayMissionAccomplishedText("MISSION FAILED"%_t, (text or missionData.title or "")%_t % missionData)
end

function showMissionAbandoned(text)
    if onServer() then
        invokeClientFunction(Player(), "showMissionAbandoned", text)
        return
    end

    displayMissionAccomplishedText("MISSION ABANDONED"%_t, (text or missionData.title or "")%_t % missionData)
end

function showMissionUpdated(text)
    if onServer() then
        invokeClientFunction(Player(), "showMissionUpdated", text)
        return
    end

    displayMissionAccomplishedText("MISSION UPDATED"%_t, (text or missionData.title or "")%_t % missionData)
end

function abandon()
    if onClient() then
        invokeServerFunction("abandon")
        return
    end

    if missionData.title then
        showMissionAbandoned()
    end

    terminate()
end
callable(nil, "abandon")

function fail()
    showMissionFailed()
    terminate()
end

function finish()
    showMissionAccomplished()
    terminate()
end

function Mission_onSectorEntered(player, x, y)
    if missionData.location and missionData.location.x and missionData.location.y then
        if x == missionData.location.x and y == missionData.location.y then
            if onTargetLocationEntered then
                onTargetLocationEntered(x, y)
            end
        end
    end
end

function Mission_onStartDialog(entityId)

    local x, y = Sector():getCoordinates()

    missionData.interactions = missionData.interactions or {}
    for _, i in pairs(missionData.interactions) do

        if i.text and i.callback then

            if i.x and i.y then
                if i.x ~= x or i.y ~= y then
                    goto continue
                end
            end

            if i.entity and Uuid(i.entity) ~= entityId then
                goto continue
            end

            if i.test and not i.test(entityId) then
                goto continue
            end

            ScriptUI(entityId):addDialogOption(i.text, i.callback)
        end

        ::continue::
    end

end

function Mission_onPostRenderHud()
    local targets = getMissionTargets()
    if not targets then return end
    if #targets == 0 then return end

    local player = Player()
    if player.state == PlayerStateType.BuildCraft or player.state == PlayerStateType.BuildTurret then return end

    local renderer = UIRenderer()
    for _, target in pairs(targets) do
        if not target then goto continue end

        local object = Entity(target)
        if not object then goto continue end

        renderer:renderEntityTargeter(object, MissionUT.getBasicMissionColor())
        renderer:renderEntityArrow(object, 30, 10, 250, MissionUT.getBasicMissionColor())

        ::continue::
    end

    renderer:display()
end

function getMissionBrief()
    return (missionData.brief%_t or "") % missionData
end

function getMissionIcon()
    return missionData.icon or ""
end

function getMissionPriority()
    return missionData.priority or 0
end

function getMissionTargets()
    return missionData.targetIds
end

function getMissionDescription()
    local description = ""
    if type(missionData.description) == "table" then
        description = string.join(missionData.description, "\n\n", function(_, str) return GetLocalizedString(str) end)
    elseif type(missionData.description) == "string" then
        description = missionData.description % _t
    end

    if missionData.showTimeLimit then
        local description = missionData.description or ""
        local timeLeft = plural_t("1 minute", "${i} minutes", math.floor(missionData.timeLeft / 60))

        if missionData.timeLeft < 60 then
            timeLeft = "< 1 minute"%_t
        end

        return (description%_t .. "\n\n" .. "Time Left: "%_t .. timeLeft)
    end

    return description % missionData
end

function getMissionLocation()
    if missionData.location then
        return missionData.location.x, missionData.location.y
    end
end

function secure()
    if onSecure then onSecure() end

    return missionData
end

function restore(data)
    missionData = data
    missionData.justStarted = false

    if onRestore then onRestore() end
    if updateDescription then updateDescription() end
end
