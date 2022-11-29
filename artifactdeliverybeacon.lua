package.path = package.path .. ";data/scripts/lib/?.lua"

The4 = include("story/the4")
include ("stringutility")
include ("callable")

function initialize()
    Entity().title = "Scanner Beacon"%_t
end

function interactionPossible(playerIndex, option)
    return true
end

function initUI()
    ScriptUI():registerInteraction("Activate"%_t, "onActivate")
end

function spawnTheFour()
    if onClient() then
        invokeServerFunction("spawnTheFour")
        return
    end

    if canSpawn() then
        The4.spawn(Sector():getCoordinates())
        terminate()
    end
end
callable(nil, "spawnTheFour")

function canSpawn()
    if onServer() then
        -- actual check before spawning
        local runtime = Server().unpausedRuntime

        for _, player in pairs ({Sector():getPlayers()}) do
            local lastSpawned = player:getValue("last_spawned_the4")
            local lastKilled = player:getValue("last_killed_the4")
            if not lastSpawned or runtime - lastSpawned >= 35 * 60 then
                if not lastKilled or runtime - lastKilled >= 30 * 60 then
                    return true
                end
            end
        end
    else
        -- preliminary check on client (used in onActivate dialog)
        local runtime = Client().unpausedRuntime
        local player = Player()

        local lastSpawned = player:getValue("last_spawned_the4")
        local lastKilled = player:getValue("last_killed_the4")
        if not lastSpawned or runtime - lastSpawned >= 35 * 60 then
            if not lastKilled or runtime - lastKilled >= 30 * 60 then
                return true
            end
        end
    end
end


function onActivate()
    local dialog = {text = "OnActivate"}
    dialog.text = "Scanning..."%_t

    local positive = {}
    positive.text = "Success. Calling the collector."%_t
    positive.followUp = {text = "Please be patient. Extraction will begin soon."%_t, onEnd = "spawnTheFour"}

    local negative = {}
    negative.text = "Negative. No artifacts on board."%_t

    local unspawnable = {}
    unspawnable.text = "You again? Just you wait. We'll regroup and get your artifact soon enough."%_t

    local ship = Player().craft

    -- check if the ship has a key equipped
    if not canSpawn() then
        dialog.followUp = unspawnable
    elseif ship:hasScript("systems/teleporterkey") then
        dialog.followUp = positive
    else
        dialog.followUp = negative
    end


    ScriptUI():showDialog(dialog)
end
