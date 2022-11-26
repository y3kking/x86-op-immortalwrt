package.path = package.path .. ";data/scripts/lib/?.lua"

include ("mission")
include ("stringutility")
The4 = include ("story/the4")

function initialize(x, y)
    initMissionCallbacks()

    if onServer() then

        if not x or not y then return end

        missionData.location = {x = x, y = y}
        missionData.justStarted = true
        missionData.brief = "Artifact Delivery"%_t
        missionData.title = "Artifact Delivery"%_t
        missionData.icon = "data/textures/icons/story-mission.png"
        missionData.priority = 10
        missionData.description = "Some people who call themselves 'The Brotherhood' have posted bulletins and are looking for Xsotan artifacts. They seem to pay a high reward to people who bring them artifacts."%_t

    else
        sync()
    end

end

function getUpdateInterval()
    return 0.5
end

function updateServer()
    if The4.checkForEnd() then
        showMissionAccomplished()
        terminate()
    end
end

function onTargetLocationEntered(x, y)
    The4.spawnBeacon()
end

function getTargetLocation()
    if not missionData.location then return 0, 0 end
    return missionData.location.x, missionData.location.y
end
