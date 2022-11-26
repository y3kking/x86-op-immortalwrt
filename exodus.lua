package.path = package.path .. ";data/scripts/lib/?.lua"

local OperationExodus = include("story/operationexodus")
local SectorGenerator = include("SectorGenerator")
local Placer = include("placer")
include("utility")
include("mission")
include("stringutility")

missionData.title = "Operation Exodus"%_t
missionData.brief = "Operation Exodus"%_t
missionData.priority = 10
missionData.additionalInfo = ""
missionData.icon = "data/textures/icons/story-mission.png"
missionData.location = {}
missionData.foundRendezvousPoint = false
missionData.locationInDescription = false
missionData.inFinalSector = false
missionData.nextBeaconLocation = {}
missionData.code = {}
missionData.codeADiscovered = false
missionData.codeBDiscovered = false

local corners
local nextBeaconLocation = {}

function initialize(start)
    if onServer() then
        local player = Player()
        player:registerCallback("onSectorEntered", "onSectorEntered")
        player:registerCallback("onItemAdded", "onItemAdded")

        corners = OperationExodus.getCornerPoints()
        missionData.code = OperationExodus.getCodeFragments()

        if start then missionData.justStarted = true end
    else
        Player():registerCallback("onStartDialog", "onStartDialog")
        sync()
    end
end

function onSectorEntered(player, x, y)
    -- when arriving in one of the final sectors
    for _, coords in pairs(corners) do
        if coords.x == x and coords.y == y then
            -- only update description, the rest is now handled in exodussectorgenerator.lua
            missionData.location = {x = x, y = y}
            missionData.inFinalSector = true
            sync()
            return
        end
    end

    if missionData.location then
        if missionData.location.x == x and missionData.location.y == y then
--            print ("entered point: " .. x .. " " .. y)
            findNextPoint(x, y)
            placeWayWreckages()
            placeWormholeBeacon(missionData.nextBeaconLocation.x, missionData.nextBeaconLocation.y)
            showMissionUpdated()
            sync()
        end
    end

    -- reset on entering a rendez-vous point
    local points = OperationExodus.getRendezVousPoints()
    for _, p in pairs(points) do
        if p.x == x and p.y == y then
--            print("entered rendez-vous point")
            findNextPoint(x, y)
            placeWormholeBeacon(missionData.nextBeaconLocation.x, missionData.nextBeaconLocation.y)
            showMissionUpdated()
            sync()
            break;
        end
    end

--    if missionData.location then
--        print ("next point: " .. missionData.location.x .. " " .. missionData.location.y)
--        for _, corner in pairs(corners) do
--            print ("corner: " .. corner.x .. " " .. corner.y)
--        end
--    else
--        print ("next point: nil")
--    end

end

function onItemAdded(index, amount, amountBefore)
    local player = Player()
    local item = player:getInventory():find(index)

    if not item then return end

    if item.itemType == InventoryItemType.SystemUpgrade then
        if item.script:find("data/scripts/systems/teleporterkey1.lua") then
           showMissionAccomplished()
           terminate()
        end
    end
end

function findNextPoint(x, y)
    missionData.nextBeaconLocation = OperationExodus.getFollowingPoint(x, y)
    missionData.foundRendezvousPoint = true
end

function onStartDialog(entityId)
    invokeServerFunction("onBeaconMessageRead", entityId)
end

function onBeaconMessageRead(entityId)
    local sector = Sector()
    local beacons = {sector:getEntitiesByScriptValue("exodus_beacon", true)}
    for _, beacon in pairs(beacons) do
        if beacon.id.string == entityId.string then
            if not missionData.inFinalSector then
                missionData.location = missionData.nextBeaconLocation
            end

            if missionData.foundRendezvousPoint == true then
                missionData.descriptionLocation = missionData.nextBeaconLocation
                sync()
                missionData.locationInDescription = true

                local gridPosition = OperationExodus.getSectorGridCode(sector:getCoordinates())
                if gridPosition == "A" then
                    missionData.codeADiscovered = true
                else
                    missionData.codeBDiscovered = true
                end
            end

            showMissionUpdated()
            sync()
        end
    end
end
callable(nil, "onBeaconMessageRead")

function beaconFound(x, y)
    local coord, index, useX = OperationExodus.getBeaconData(x, y)

    local text
    if useX then
        text = string.format("#%i X = %i", index, coord)
    else
        text = string.format("#%i Y = %i", index, coord)
    end

    if not string.find(missionData.additionalInfo, text, 1, true) then
        missionData.additionalInfo = missionData.additionalInfo .. text .. "\n"

        if onServer() then
            showMissionUpdated()
            sync()
        end
    end

end

function placeWormholeBeacon(nextLocationX, nextLocationY)
    local beacons = {Sector():getEntitiesByScriptValue("exodus_beacon", true)}

    -- remove all old beacons as they might have no code values yet (if it is an old galaxy) or wrong ones
    if #beacons > 0 then
        for _, beacon in pairs(beacons) do
            Sector():deleteEntity(beacon)
        end
    end

    local text = "Operation Exodus:${remaining}"%_t
    local remaining

    if not missionData.code then
        missionData.code = OperationExodus.getCodeFragments()
        sync()
    end

    local x, y = Sector():getCoordinates()
    local sectorCode = OperationExodus.getSectorGridCode(x, y)

    if sectorCode == "A" then
        remaining = "\n\n" .. string.format("X = %i\nY = %i", nextLocationX, nextLocationY) .."\n\n" .. "Code Fragment A = /* first part of a code that has to be used on a keypad later */"%_t .. " ".. missionData.code.a
    else
        remaining = "\n\n" .. string.format("X = %i\nY = %i", nextLocationX, nextLocationY) .."\n\n" .. "Code Fragment B = /* second part of a code that has to be used on a keypad later */"%_t .. " ".. missionData.code.b
    end

    local exodusBeacon = SectorGenerator(Sector():getCoordinates()):createBeacon(nil, nil, text, {remaining = remaining})
    exodusBeacon:addScriptOnce("data/scripts/entity/story/exoduswormholebeacon.lua")
    exodusBeacon:setValue("exodus_beacon", true)
end

function placeWayWreckages()

    if math.random() < 0.5 then return end

    local wreckages = {Sector():getEntitiesByType(EntityType.Wreckage)}
    if #wreckages > 0 then return end

    local faction = OperationExodus.getFaction()
    local generator = SectorGenerator(faction:getHomeSectorCoordinates())

    for i = 1, math.random(1, 3) do
        generator:createWreckage(faction)
    end

    Placer.resolveIntersections()

end

function getMissionDescription()
    if missionData.inFinalSector == true then
         return "Explore the final sector"%_t
    else
        if missionData.locationInDescription == true then
            local message = "After deciphering the beacons, you found another beacon leading to a new location: "%_t  .. missionData.descriptionLocation.x .. " : " .. missionData.descriptionLocation.y

            if missionData.codeADiscovered and missionData.code and missionData.code.a then
                message = message .. "\n\n" .. "Code Fragment A = /* first part of a code that has to be used on a keypad later */"%_t .. " ".. missionData.code.a
            end

            if missionData.codeBDiscovered and missionData.code and missionData.code.b then
                message = message .. "\n\n" .. "Code Fragment B = /* second part of a code that has to be used on a keypad later */"%_t .. " ".. missionData.code.b
            end

            return message
        else
            local additionalText = ""
            if missionData.additionalInfo and missionData.additionalInfo ~= "" then
                additionalText = "Messages:\n"%_t .. missionData.additionalInfo
            end

            return "You found a beacon with a cryptic message for all participants of the so-called 'Operation Exodus'."%_t .. "\n\n" .. additionalText
        end
    end
end


