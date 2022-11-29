package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"

include ("randomext")
include ("galaxy")
include ("utility")
include ("defaultscripts")
include ("goods")
include ("stringutility")
PlanGenerator = include ("plangenerator")
ShipUtility = include ("shiputility")
SectorSpecifics = include ("sectorspecifics")
SectorTurretGenerator = include ("sectorturretgenerator")
SectorGenerator = include ("SectorGenerator")
include("weapontype")

local The4 = {}
local lastPosition
local lastSector = {}

function The4.getFaction()
    local name = "The Brotherhood"%_T
    local faction = Galaxy():findFaction(name)

    if not faction then
        faction = Galaxy():createFaction(name, 150, 0)

        -- those dudes are completely neutral in the beginning
        faction.initialRelations = 0
        faction.initialRelationsToPlayer = 0
    end

    faction.homeSectorUnknown = true

    return faction
end

function The4.checkForEnd()
    -- if it's the last one, then drop the key
    local faction = The4.getFaction()
    local position = nil

    -- make sure this is all happening in the same sector
    local x, y = Sector():getCoordinates()
    if lastSector.x ~= x or lastSector.y ~= y then
        -- this must be set in order to drop the loot
        -- if the sector changed, simply unset it
        lastPosition = nil
    end
    lastSector.x = x
    lastSector.y = y

    local entity = Sector():getEntitiesByFaction(faction.index)
    if entity then
        position = entity.translationf

    end

    -- if there are no bosses now but there have been before, drop the upgrade & end the mission
    local ended
    if position == nil and lastPosition ~= nil then
        local players = {Sector():getPlayers()}
        local runtime = Server().unpausedRuntime

        for _, player in pairs(players) do        
            -- skip the players that already had the upgrade dropped lately in case someone snuck in after they spawned
            local lastKilled = player:getValue("last_killed_the4")

            if not lastKilled or runtime - lastKilled >= 30 * 60 then
                local system = SystemUpgradeTemplate("data/scripts/systems/teleporterkey5.lua", Rarity(RarityType.Legendary), Seed(1))
                Sector():dropUpgrade(lastPosition, player, nil, system)

                player:setValue("last_killed_the4", runtime)
            end
        end

        ended = true
    end

    lastPosition = position

    return ended
end

function The4.createShip(faction, position, volume, styleName)
    position = position or Matrix()
    volume = volume or Balancing_GetSectorShipVolume(Sector():getCoordinates()) * Balancing_GetShipVolumeDeviation()

    local plan = PlanGenerator.makeShipPlan(faction, volume, styleName)
    local ship = Sector():createShip(faction, "", plan, position, EntityArrivalType.Jump)

    ship.crew = ship.idealCrew
    ship.shieldDurability = ship.shieldMaxDurability

    AddDefaultShipScripts(ship)
    SetBoardingDefenseLevel(ship)

    Boarding(ship).boardable = false
    ship.dockable = false

    return ship
end

function The4.createHealingTurret()
    -- create custom heal turrets
    local generator = SectorTurretGenerator(Seed(153))
    generator.coaxialAllowed = false

    local turret = generator:generate(150, 0, 0, Rarity(RarityType.Common), WeaponType.RepairBeam)
    local weapons = {turret:getWeapons()}
    turret:clearWeapons()
    for _, weapon in pairs(weapons) do
        weapon.reach = 800
        weapon.blength = 800

        weapon.shieldRepair = 250
        weapon.hullRepair = 0
        weapon.bouterColor = ColorRGB(0.1, 0.2, 0.4);
        weapon.binnerColor = ColorRGB(0.2, 0.4, 0.9);
        weapon.shieldPenetration = 0.0
        turret:addWeapon(weapon)

        weapon.hullRepair = 250
        weapon.shieldRepair = 0
        weapon.bouterColor = ColorRGB(0.1, 0.5, 0.1);
        weapon.binnerColor = ColorRGB(1.0, 1.0, 1.0);
        weapon.shieldPenetration = 1.0
        turret:addWeapon(weapon)
    end

    turret.turningSpeed = 2.0
    turret.crew = Crew()

    return turret
end

function The4.createPlasmaTurret()
    -- create custom plasma turrets
    local generator = SectorTurretGenerator(Seed(151))
    generator.coaxialAllowed = false

    local turret = generator:generate(150, 0, 0, Rarity(RarityType.Common), WeaponType.PlasmaGun)
    local weapons = {turret:getWeapons()}
    turret:clearWeapons()
    for _, weapon in pairs(weapons) do
        weapon.reach = 800
        weapon.reach = 800
        weapon.pmaximumTime = weapon.reach / weapon.pvelocity
        weapon.hullDamageMultiplier = 0.25
        turret:addWeapon(weapon)
    end

    turret.turningSpeed = 2.0
    turret.crew = Crew()

    return turret
end

function The4.createRailgunTurret()
    -- create custom railgun turrets
    local generator = SectorTurretGenerator(Seed(151))
    generator.coaxialAllowed = false

    local turret = generator:generate(150, 0, 0, Rarity(RarityType.Common), WeaponType.RailGun)
    local weapons = {turret:getWeapons()}
    turret:clearWeapons()
    for _, weapon in pairs(weapons) do
        weapon.reach = 800
        weapon.blength = 800
        weapon.shieldDamageMultiplier = 0.1
        turret:addWeapon(weapon)
    end

    turret.turningSpeed = 2.0
    turret.crew = Crew()

    return turret
end

function The4.createLaserTurret()
    -- create custom heal turrets
    local generator = SectorTurretGenerator(Seed(152))
    generator.coaxialAllowed = false

    local turret = generator:generate(450, 0, 0, Rarity(RarityType.Petty), WeaponType.Laser)
    local weapons = {turret:getWeapons()}
    turret:clearWeapons()
    for _, weapon in pairs(weapons) do
        weapon.reach = 600
        weapon.blength = 600
        turret:addWeapon(weapon)
    end

    turret.turningSpeed = 2.0
    turret.crew = Crew()

    return turret
end

function The4.spawnHealer(x, y)
    local faction = The4.getFaction()
    local volume = Balancing_GetSectorShipVolume(faction:getHomeSectorCoordinates()) * 8

    local translation = random():getDirection() * 500
    local position = MatrixLookUpPosition(-translation, vec3(0, 1, 0), translation)

    local boss = The4.createShip(faction, position, volume, "Style 1")
    local turret = The4.createHealingTurret()
    ShipUtility.addTurretsToCraft(boss, turret, 15, 15)
    ShipUtility.addBossAntiTorpedoEquipment(boss)
    boss.title = "Reconstructo"
    boss:addScript("story/healer")
    boss:addScript("story/the4")

    Loot(boss.index):insert(InventoryTurret(SectorTurretGenerator():generate(x, y, 0, Rarity(RarityType.Exotic), WeaponType.RepairBeam)))
    boss:setDropsAttachedTurrets(false)

    return boss
end

function The4.spawnShieldBreaker(x, y)
    local faction = The4.getFaction()
    local volume = Balancing_GetSectorShipVolume(faction:getHomeSectorCoordinates()) * 10

    local translation = random():getDirection() * 500
    local position = MatrixLookUpPosition(-translation, vec3(0, 1, 0), translation)

    local boss = The4.createShip(faction, position, volume, "Style 2")
    local turret = The4.createPlasmaTurret()
    ShipUtility.addTurretsToCraft(boss, turret, 15, 15)
    ShipUtility.addBossAntiTorpedoEquipment(boss)
    boss.title = "Shieldbreaker"
    boss:addScript("story/the4")

    Loot(boss.index):insert(InventoryTurret(SectorTurretGenerator():generate(x, y, 0, Rarity(RarityType.Exotic), WeaponType.PlasmaGun)))
    boss:setDropsAttachedTurrets(false)

    return boss
end

function The4.spawnHullBreaker(x, y)
    local faction = The4.getFaction()
    local volume = Balancing_GetSectorShipVolume(faction:getHomeSectorCoordinates()) * 10

    local translation = random():getDirection() * 500
    local position = MatrixLookUpPosition(-translation, vec3(0, 1, 0), translation)

    local boss = The4.createShip(faction, position, volume, "Style 2")
    local turret = The4.createRailgunTurret()
    ShipUtility.addTurretsToCraft(boss, turret, 15, 15)
    ShipUtility.addBossAntiTorpedoEquipment(boss)
    boss.title = "Hullbreaker"
    boss:addScript("story/the4")

    Loot(boss.index):insert(InventoryTurret(SectorTurretGenerator():generate(x, y, 0, Rarity(RarityType.Exotic), WeaponType.RailGun)))
    boss:setDropsAttachedTurrets(false)

    return boss
end

function The4.spawnTank(x, y)
    local faction = The4.getFaction()
    local volume = Balancing_GetSectorShipVolume(faction:getHomeSectorCoordinates()) * 20

    local translation = random():getDirection() * 500
    local position = MatrixLookUpPosition(-translation, vec3(0, 1, 0), translation)

    local boss = The4.createShip(faction, position, volume, "Style 3")
    local turret = The4.createLaserTurret()
    ShipUtility.addTurretsToCraft(boss, turret, 20, 20)
    ShipUtility.addBossAntiTorpedoEquipment(boss)
    boss.title = "Tankem"
    boss:addScript("story/the4")

    -- adds legendary turret drop
    boss:addScriptOnce("internal/common/entity/background/legendaryloot.lua")
    boss:addScriptOnce("utility/buildingknowledgeloot.lua")

    Loot(boss.index):insert(InventoryTurret(SectorTurretGenerator():generate(x, y, 0, Rarity(RarityType.Exotic), WeaponType.Laser)))
    boss:setDropsAttachedTurrets(false)

    return boss
end


function The4.spawn(x, y)

    local ships = {Sector():getEntitiesByFaction(The4.getFaction().index)}

    for _, ship in pairs(ships) do
        if ship:hasComponent(ComponentType.Title) then
            if ship.title == "Tankem"
                or ship.title == "Shieldbreaker"
                or ship.title == "Hullbreaker"
                or ship.title == "Reconstructo" then

                return
            end
        end
    end

    print ("spawning the The 4!")

    -- set the last_spawned value for all players in the sector
    local players = {Sector():getPlayers()}
    local runtime = Server().unpausedRuntime
    for _, player in pairs(players) do
        player:setValue("last_spawned_the4", runtime)
    end

    -- spawn
    local healer = The4.spawnHealer(x, y)
    local dd1 = The4.spawnShieldBreaker(x, y)
    local dd2 = The4.spawnHullBreaker(x, y)
    local tank = The4.spawnTank(x, y)

    enemies = {}
    table.insert(enemies, healer)
    table.insert(enemies, dd1)
    table.insert(enemies, dd2)
    table.insert(enemies, tank)

    local players = {Sector():getPlayers()}

    for _, boss in pairs(enemies) do
        ShipAI(boss.index):setAggressive()

        -- like all players
        for _, player in pairs(players) do
            ShipAI(boss.index):registerFriendFaction(player.index)
        end
    end

    print ("The 4 spawned!")

    -- send sector callback on finished spawning
    Sector():sendCallback("onThe4Spawned", healer.id, dd1.id, dd2.id, tank.id, Sector():getCoordinates())

    return healer, dd1, dd2, tank
end

function The4.spawnBeacon()
    local generator = SectorGenerator(Sector():getCoordinates())

    local beacon = generator:createBeacon(Matrix(), nil, "Scanners online."%_t)
    beacon:addScript("story/artifactdeliverybeacon")
    beacon:addScript("deleteonplayersleft")
    beacon.dockable = false

end

local description = [[
Fellow Galaxy Dweller,

In times like these, where the Xsotan threat is looming at all times, we are trying to protect you. Dangerous artifacts of the Xsotan have been found all over the galaxy, causing great harm to everyone near them.
Should you find any of those artifacts, you must bring them to us. We will take care of them and destroy them, to eradicate the Xsotan threat and to make the galaxy a better place.
Even if your life may be at risk, what is your life compared to the safety of trillions?
You can find one of our outposts at (${x}, ${y}).
We will pay a reward of 100.000.000 Credits for each delivered artifact.
The Brotherhood]]%_t

function The4.tryPostBulletin(entity)
    entity = entity or Entity()

    if random():getFloat() > 0.25 then return end

    local mind = 150
    local maxd = 180


    local distance = length(vec2(Sector():getCoordinates()))
    if not (distance >= mind and distance < maxd) then
        return
    end

    local location
    local x, y = Sector():getCoordinates()

    local specs = SectorSpecifics()
    local coordinates = specs.getShuffledCoordinates(random(), x, y, 0, 40)
    local seed = Server().seed

    for _, coords in pairs(coordinates) do

        local distance = length(vec2(coords.x, coords.y))
        if distance >= mind and distance < maxd then

            local regular, offgrid, blocked, home = specs:determineContent(coords.x, coords.y, seed)
            if offgrid and not regular and not blocked and not home then

                specs:initialize(coords.x, coords.y, seed)
                if string.match(specs:getScript(), "wreckagefield") then
                    location = {x = coords.x, y = coords.y}
                    break
                end
            end
        end
    end

    -- if no location could be found, don't post
    if not location then
        return
    end

    local bulletin =
    {
        brief = "Looking for Xsotan Artifacts"%_t,
        description = description,
        icon = "data/textures/icons/story-mission.png",
        difficulty = "Hard"%_t,
        reward = "¢100.000.000"%_t,
        script = "story/artifactdelivery.lua",
        arguments = {location.x, location.y},
        formatArguments = {x = location.x, y = location.y},
        checkAccept = [[
            local self, player = ...
            if player:hasScript("story/artifactdelivery") then
                player:removeScript("data/scripts/player/story/artifactdelivery.lua")
            end
            return 1
        ]],
        onAccept = [[ ]]
    }

    entity:invokeFunction("bulletinboard", "postBulletin", bulletin)
end


return The4;
