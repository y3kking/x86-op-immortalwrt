package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/player/background/simulation/?.lua"

local CommandType = include ("commandtype")
local SimulationUtility = include ("simulationutility")
local CaptainUtility = include("captainutility")
local Galaxy = include ("galaxy")
local GatesMap = include ("gatesmap")
local ShipUtility = include ("shiputility")
local UpgradeGenerator = include ("upgradegenerator")
local SectorSpecifics = include("sectorspecifics")

include ("utility")
include ("stringutility")
include ("randomext")

local ExpeditionCommand = {}
ExpeditionCommand.__index = ExpeditionCommand
ExpeditionCommand.type = CommandType.Expedition

-- all commands need this kind of "new" to function within the bg simulation framework
local function new(ship, area, config)
    local command = setmetatable({
        -- all commands need these variables to function within the bg simulation framework
        -- type contains the CommandType of the command, required to restore
        type = CommandType.Expedition,

        -- the ship that has the command
        shipName = ship,

        -- the area where the ship is doing its thing
        area = area,

        -- config that was given to the ship
        config = config,

        -- holds any data necessary to fulfill the command, that should be saved to database, eg. timers and so on
        -- this should only contain variables that can be saved to database (eg. returned in a secure()) call
        -- this will be automatically restored/secured
        data = {},

        -- will be set from external, only listed here for completeness' sake
        simulation = nil,
    }, ExpeditionCommand)

    command.data.runTime = 0

    return command
end

function ExpeditionCommand:initialize()
    local parent = getParentFaction()
    local prediction = self:calculatePrediction(parent.index, self.shipName, self.area, self.config)
    self.data.prediction = prediction

    self.data.duration = self.config.duration * 60
end

-- executed when an area analysis involving this type of command starts
-- this will be called on a temporary instance of the command. all values written to "self" will not persist
function ExpeditionCommand:onAreaAnalysisStart(results, meta)
    results.possibleSectors = {}
end

-- executed when an area analysis involving this type of command is checking a specific sector
-- this will be called on a temporary instance of the command. all values written to "self" will not persist
function ExpeditionCommand:onAreaAnalysisSector(results, meta, x, y)

end

-- executed when an area analysis involving this type of command finished
-- this will be called on a temporary instance of the command. all values written to "self" will not persist
function ExpeditionCommand:onAreaAnalysisFinished(results, meta)
    -- only pick sectors that are no-man's-space
    local reachableSectors = results.reachableCoordinates
    local nonFactionSectors = {}
    results.nonFactionSectors = {}
    results.possibleSectors = {}

    if #reachableSectors == 0 then
        return
    end

    for _, sector in pairs(reachableSectors) do
        if sector.faction == 0 then
            table.insert(nonFactionSectors, sector)
        end
    end

    if #nonFactionSectors / #reachableSectors > 0.66 then
        results.validArea = true
    else
        results.validArea = false
    end

    if #nonFactionSectors < 5 then
        results.validArea = false
    end

    local usedSectors = {}

    -- pick 5 random sectors from the sectors that may be used
    shuffle(nonFactionSectors)
    for i = 1, 5 do
        table.insert(usedSectors, nonFactionSectors[i])
    end

    results.nonFactionSectors = nonFactionSectors
    results.possibleSectors = usedSectors
end

-- executed when the command starts for the first time (not when being restored)
function ExpeditionCommand:onStart()
    self.data.yieldNumber = 0
    self.data.yieldCounter = 0
    self.data.regularYieldsTime = 20 * 60
    self.data.possibleSectors = self.area.analysis.possibleSectors
    self.data.adventures = {}
    local numAdventures = #self:generateAdventures()

    for i = 1, numAdventures do
        table.insert(self.data.adventures, i)
    end

    shuffle(self.data.adventures)

    local parent = getParentFaction()
    local entry = ShipDatabaseEntry(parent.index, self.shipName)
    entry:setStatusMessage("Exploring"%_t)

    -- save position from which ship is going to start
    local startX, startY = entry:getCoordinates()
    self.data.startCoordinates = { x = startX, y = startY }

    if self.data.prediction.attackLocation then
        if self.simulation.disableAttack then return end -- for unit test

        local attackTime = 10 * 60 + ((self.config.duration * 60 - 20 * 60) * random():getFloat(0.3, 0.7))
        self:registerForAttack(self.data.possibleSectors[1], nil, attackTime, "Expedition: Ship %1% is under attack in sector \\s(%2%:%3%)."%_t, {self.shipName, self.data.possibleSectors[1].x, self.data.possibleSectors[1].y})
    end
end

function ExpeditionCommand:update(timeStep)
    self.data.runTime = self.data.runTime + timeStep
    self.data.yieldCounter = self.data.yieldCounter + timeStep

    if self.data.runTime >= self.config.duration * 60 then
        self:finish()
        return
    end

    if self.data.yieldCounter >= self.data.regularYieldsTime then
        self.data.yieldCounter = self.data.yieldCounter - self.data.regularYieldsTime
        self.data.yieldNumber = self.data.yieldNumber + 1
        self.data.regularYieldsTime = 30 * 60

        local entry = ShipDatabaseEntry(getParentFaction().index, self.shipName)
        local captain = entry:getCaptain()

        -- smuggler captains don't have to slow down when transporting special goods
        if not captain:hasClass(CaptainUtility.ClassType.Smuggler) then
            local stolenOrIllegal, dangerousOrSuspicious = SimulationUtility.getSpecialCargoCategories(entry:getCargo())

            -- merchant captains don't have to slow down when transporting dangerous or suspicious goods
            if captain:hasClass(CaptainUtility.ClassType.Merchant) then
                dangerousOrSuspicious = false
            end

            -- cargo on ship that would lead to controls causes the captain to hide and therefore to experience fewer adventures
            if stolenOrIllegal or dangerousOrSuspicious then
                if self.data.regularYieldsTime == 30 * 60 then
                    self.data.regularYieldsTime = 40 * 60
                    return -- this is the first yield. Skip it
                end

                self.data.regularYieldsTime = 40 * 60
            end
        end

        -- pick an adventure
        local currentAdventure = table.remove(self.data.adventures)

        if self.simulation.playFirstAdventure then currentAdventure = 1 end -- for unit tests

        self:calculateYield(self.data.yieldNumber, currentAdventure)        
    end
end

-- select random goods out of all possible uncomplicated goods
function ExpeditionCommand:getRandomGoods(min, max)
    local goodsIndices = {}
    local allGoods = {}
    local yieldGoods = {}
    local numGoods = random():getInt(min, max)

    for _, good in pairs(uncomplicatedSpawnableGoods) do
        table.insert(allGoods, good)
    end

    shuffle(allGoods)

    for i = 1, numGoods do
        local good = table.remove(allGoods)
        table.insert(yieldGoods, good)
    end

    return yieldGoods
end

-- executed when the ship is being recalled by the player
function ExpeditionCommand:onRecall()
end

-- executed when the command is finished
function ExpeditionCommand:onFinish()
    self:calculateYield(5, 0)

    local parent = getParentFaction()
    local entry = ShipDatabaseEntry(parent.index, self.shipName)
    local captain = entry:getCaptain()

    if captain:hasClass(CaptainUtility.ClassType.Explorer) then
        self:onExplorerFinish(captain)
    end

    -- restore starting position of expedition command
    if self.data.startCoordinates then
        local startX = self.data.startCoordinates.x
        local startY = self.data.startCoordinates.y
        entry:setCoordinates(startX, startY)
    end

    -- send chat message that ship is finished
    local x, y = entry:getCoordinates()
    parent:sendChatMessage(self.shipName, ChatMessageType.Information, "%1% has returned from the expedition and is awaiting your next orders in \\s(%2%:%3%)."%_T, self.shipName, x, y)
end

function ExpeditionCommand:onExplorerFinish(captain)
    local faction = getParentFaction()
    local specs = SectorSpecifics()
    local seed = Server().seed

    local notes = {}
    table.insert(notes, "Commander, I marked this sector on the map for you.\n\nRegards, Captain ${name}"%_T)
    table.insert(notes, "Commander, we discovered this sector that you didn't have on the map yet.\n\nRegards, Captain ${name}"%_T)
    table.insert(notes, "Discovered a sector here.\n\nRegards, Captain ${name}"%_T)
    table.insert(notes, "As a small courtesy, I explored this sector for you.\n\nRegards, Captain ${name}"%_T)

    local revealed = 0
    local gatesMap

    for _, coords in pairs(self.area.analysis.reachableCoordinates) do
        local x, y = coords.x, coords.y
        local regular, offgrid = specs.determineFastContent(x, y, seed)

        -- regular and offgrid can be changed into each other depending on central region or no man's space
        if not regular and not offgrid then goto continue end

        local regular, offgrid, blocked, home = specs:determineContent(x, y, seed)
        if not regular then goto continue end -- no regular content -> continue
        if blocked then goto continue end -- there can't be anything if the sector is blocked

        local view = faction:getKnownSector(x, y)
        if view then goto continue end -- don't override existing data

        view = SectorView()
        gatesMap = gatesMap or GatesMap(GameSeed())

        specs:initialize(x, y, seed)
        specs:fillSectorView(view, gatesMap, true)

        view.note = NamedFormat(randomEntry(notes), {name = captain.name})

        -- make sure that no new icons are created
        if view.tagIconPath == "" then view.tagIconPath = "data/textures/icons/nothing.png" end

        faction:addKnownSector(view)

        revealed = revealed + 1
        if revealed >= 5 then break end

        ::continue::
    end
end

function ExpeditionCommand:calculateYield(yieldNumber, currentAdventure)
    local x = self.data.possibleSectors[yieldNumber].x
    local y = self.data.possibleSectors[yieldNumber].y

    -- yield
    local messages = {}
    local ship = self.shipName
    local money = 0
    local resources = {}
    local items = {}

    --loot
    local types = Balancing_GetWeaponProbability(x, y)

    types[WeaponType.RepairBeam] = nil
    types[WeaponType.MiningLaser] = nil
    types[WeaponType.SalvagingLaser] = nil
    types[WeaponType.RawSalvagingLaser] = nil
    types[WeaponType.RawMiningLaser] = nil
    types[WeaponType.ForceGun] = nil

    local attackTurrets = {}
    for weaponType, _ in pairs(types) do
        table.insert(attackTurrets, weaponType)
    end

    local miningTurrets = {WeaponType.MiningLaser, WeaponType.RawMiningLaser}
    local salvagingTurrets = {WeaponType.SalvagingLaser, WeaponType.RawSalvagingLaser}
    local tcs = {"data/scripts/systems/militarytcs.lua", "data/scripts/systems/arbitrarytcs.lua", "data/scripts/systems/autotcs.lua"}

    local adventures = {}

    if yieldNumber < 5 then
        adventures = self:generateAdventures()
    else
        adventures[currentAdventure] = self:generateLastAdventure()
        if x > 0 then x = x - 20 else x = x + 20 end
        if y > 0 then y = y - 20 else y = y + 20 end
    end

    -- check what kinds of yields the adventure gives (money, resources, subsystems, turrets ...)
    if adventures[currentAdventure].money then
        money = adventures[currentAdventure].money
    end

    if adventures[currentAdventure].resources then
        -- see which materials the captain might find here
        local probabilities = Galaxy.GetMaterialProbability(x, y)
        local materialProbabilities = {}
        for i, probability in pairs(probabilities) do
            materialProbabilities[i+1] = probability
        end

        for i = 1, 7 do
            resources[i] = math.floor(adventures[currentAdventure].resources * (materialProbabilities[i] or 0))
        end
    end

    local subsystems = {}
    if adventures[currentAdventure].subsystems then
        for i = 1, random():getInt(adventures[currentAdventure].subsystems.min, adventures[currentAdventure].subsystems.max) do
            if adventures[currentAdventure].subsystems.type == "randomSubsystems" then
                table.insert(subsystems, { x = x, y = y, seed = random():createSeed(), rarity = self:calculateYieldRarity(number), }) -- giving no type gives you a random system
            elseif adventures[currentAdventure].subsystems.type == "tcs" then
                table.insert(subsystems, { x = x, y = y, seed = random():createSeed(), type = randomEntry(tcs), rarity = self:calculateYieldRarity(number), })
            else
                table.insert(subsystems, { x = x, y = y, seed = random():createSeed(), type = adventures[currentAdventure].subsystems.type, rarity = self:calculateYieldRarity(number), })
            end
        end
    end

    local turrets = {}
    if adventures[currentAdventure].turrets then
        for i = 1, random():getInt(adventures[currentAdventure].turrets.min, adventures[currentAdventure].turrets.max) do
            if adventures[currentAdventure].turrets.type == "attackTurrets" then
                table.insert(turrets,  { x = x, y = y, seed = random():createSeed(), type = randomEntry(attackTurrets), rarity = self:calculateYieldRarity(number), })
            elseif adventures[currentAdventure].turrets.type == "miningTurrets" then
                table.insert(turrets,  { x = x, y = y, seed = random():createSeed(), type = randomEntry(miningTurrets), rarity = self:calculateYieldRarity(number), })
            elseif adventures[currentAdventure].turrets.type == "salvagingTurrets" then
                table.insert(turrets,  { x = x, y = y, seed = random():createSeed(), type = randomEntry(salvagingTurrets), rarity = self:calculateYieldRarity(number), })
            end
        end
    end

    local blueprints = {}
    if adventures[currentAdventure].blueprints then
        for i = 1, random():getInt(adventures[currentAdventure].blueprints.min, adventures[currentAdventure].blueprints.max) do
            if adventures[currentAdventure].blueprints.type == "attackTurrets" then
                table.insert(blueprints,  { x = x, y = y, seed = random():createSeed(), type = randomEntry(attackTurrets), rarity = self:calculateYieldRarity(number), })
            elseif adventures[currentAdventure].blueprints.type == "miningTurrets" then
                table.insert(blueprints,  { x = x, y = y, seed = random():createSeed(), type = randomEntry(miningTurrets), rarity = self:calculateYieldRarity(number), })
            elseif adventures[currentAdventure].blueprints.type == "salvagingTurrets" then
                table.insert(blueprints,  { x = x, y = y, seed = random():createSeed(), type = randomEntry(salvagingTurrets), rarity = self:calculateYieldRarity(number), })
            end
        end
    end

    items.subsystems = subsystems
    items.turrets = turrets
    items.blueprints = blueprints

    self:addYield(randomEntry(adventures[currentAdventure].messages), money, resources, items)

    -- add cargo to the ship's cargo bay
    if adventures[currentAdventure].cargoBayFillRatio then
        local entry = ShipDatabaseEntry(getParentFaction().index, self.shipName)
        local freeCargoSpace = entry:getFreeCargoSpace()
        local cargos, cargoHold = entry:getCargo()
        local yieldGoods = self:getRandomGoods(2, 5)

        local cargoSpaceForAdventure = freeCargoSpace * adventures[currentAdventure].cargoBayFillRatio
        local spacePerCargo = math.floor(cargoSpaceForAdventure / #yieldGoods)
        local valueOfGoods = 0
        local valueLimit = 5000 * Balancing_GetSectorRichnessFactor(x, y)

        for _, good in pairs(yieldGoods) do
            local tradingGood = goods[good.name]:good()
            local budgetLeft = valueLimit - valueOfGoods
            local amountAccordingToCargoHold = math.floor(spacePerCargo / tradingGood.size)
            local amountAccordingToBudget = math.floor(budgetLeft / tradingGood.price)

            local amount

            if amountAccordingToBudget >= amountAccordingToCargoHold then
                amount = amountAccordingToCargoHold
            else
                amount = amountAccordingToBudget
            end

            valueOfGoods = valueOfGoods + (tradingGood.price * amount)

            if valueOfGoods <= valueLimit then
                cargos[tradingGood] = (cargos[tradingGood] or 0) + amount
            else
                break
            end

            entry:setCargo(cargos)
        end
    end
end

function ExpeditionCommand:generateAdventures()
    local adventures = {}

 --         "This comment is here to show how long a sentence may be to completely fill the 'message' lines of the yield. Do not write any messages longer than this, or they will not fit into the 'message' lines of the yield!"

    -- resources, mining turrets and mining subsystems
    local adventure =
    {
        messages =
        {
            "We found an abandoned mine. When we entered it, my entire crew said they had a 'bad feeling' about it, so we left as quickly as possible. However, we did take some mining equipment that had been left behind."%_t,
            "We came across an abandoned mine. The asteroid was basically falling apart, they had mined every last piece of copper off of it. But we found some mining equipment that was left behind."%_t,
            "We found a mining ship just floating through space. All the escape pods were missing and no trace of the crew and no log files."%_t,
            "The dockmaster at a station sold a ship to us. It was taking up dock space, and no member of the crew had shown their face there in months. We towed it to a scrapyard but kept the equipment on it."%_t,
        },
        resources = random():getInt(4000, 7000) *  Balancing_GetSectorRichnessFactor(x, y, 10),
        subsystems = {type = "data/scripts/systems/miningsystem.lua", min = 1, max = 1},
        turrets = {type = "miningTurrets", min = 1, max = 3},
    }

    table.insert(adventures, adventure)

    -- money and trading overview
    local adventure =
    {
        messages =
        {
            "We answered a distress call from a merchant who was being attacked by pirates. He was very grateful and to show his gratitude he gave us a trading overview."%_t,
            "We ran into a merchant who was trying to escape from Xsotan. We blasted them to pieces and the merchant was grateful and gave us a trading overview."%_t,
            "We met two really small explorer ships called 'Aphelion' and 'Perihelion'. The crews may not be very creative with their names, but they did give us a trading overview."%_t,
        },
        money = random():getInt(7500, 12500) * Balancing_GetSectorRichnessFactor(x, y),
        subsystems = {type = "data/scripts/systems/tradingoverview.lua", min = 1, max = 1},
    }

    table.insert(adventures, adventure)

    -- tcs, attack turrets and cargo
    local adventure =
    {
        messages =
        {
            "We went to answer a distress call, but it turned out to be fake. It was pirates, trying to lure helpful souls into their trap. We punished them for that!"%_t,
            "We found a pirate station in a sector with a yellow blip. They must have been on a raid because there was only one ship defending it. We destroyed that ship and got out of there as fast as we could."%_t,
            "Some pirates tried to attack us, but they soon realized that it was a bad idea. We looted their ships after we were done with them."%_t,
        },
        subsystems = {type = "tcs", min = 1, max = 1},
        turrets = {type = "attackTurrets", min = 2, max = 3},
        cargoBayFillRatio = 0.25,
    }

    table.insert(adventures, adventure)

    -- tcs and attack turrets
    local adventure =
    {
        messages =
        {        
            "A couple of pirates tried to attack us. It was such a half-hearted attempt that we felt sorry for them and didn't destroy their ship. We did take their weapons and tcs, though."%_t,
            "We were just minding our own business when a ship fired a torpedo at us. We fired back and they jumped out of the sector. We tried to chase them but all we found was another victim of theirs. No trace of them."%_t,
            "We found the wrecks of military ships. It seemed like the fight hadn't been too long ago, so we only took a couple of turrets and subsystems and got out of there, in case backup to either party showed up."%_t,
            "We joined a raid the 'Cavaliers' were leading against a pirate station and they gave us a sweet reward."%_t,
        },
        subsystems = {type = tcs, min = 1, max = 2},
        turrets = {type = "attackTurrets", min = 2, max = 3},
    }

    table.insert(adventures, adventure)

    -- only subsystems
    local adventure =
    {
        messages =
        {
            "We found a lone container just floating through space. It wasn't even locked."%_t,
            "We met a self-replicating drone. I've never seen such an outdated 3D printer, but it's amazing that it still works. Who knows how old it might be?"%_t,
            "We came across the wreck of half a ship. We checked the log, it seems they were about to go through a wormhole when the recording stopped. I don't even want to think about wormholes just collapsing..."%_t,
            "We found two bots in an escape pod close to some desert planet. There were some valuable things in the pod, but the bots are scrap. This is not the kind of bot we were looking for."%_t,
            "We were just flying toward a gate when another ship scraped past us. They lost a container they had docked to them and our paint job was scratched. We kept the contents of the container as compensation."%_t,
            "We disturbed some pirates hacking a container. They fled, and we tried to determine the container's owner but had no luck. Long story short, we just took the contents."%_t,
        },
        subsystems = {type = "randomSubsystems", min = 2, max = 4},
     }

    table.insert(adventures, adventure)

    -- only money
    local adventure =
    {
        messages =
        {
            "A ship's hyperspace engine had busted after a long jump. They were lucky we came across them and that our engineers were able to help them fix it. We even had the spare parts they needed!"%_t,
            "Somebody tried to sell drugs to us, but we alerted the authorities instead. The local faction gave us a reward for helping them apprehend a notorious drug dealer."%_t,
            "Our scanners barely registered a ship with all of its engines turned off. We hailed them to see if they needed assistance, but they just told us they were going to pay us to go away. So we took the money."%_t,
            "We ran into some people who were preparing a race, and since we know a lot about spaceships, we could immediately tell which ship would be the fastest, so we bet on it. Here is part of our winnings."%_t,
            "A ship had broken down right at a gate and the ships coming through the gate were just piling up on top of it. Oh, the property damage! We helped clear the path and the local faction rewarded us."%_t,
            "We got paid for transporting a herd of cattle. They did some damage to the ship, but the insurance of the owner paid way more than we needed for the repairs. Would have been even more if it had been alpacas."%_t,
            "Some dude really wanted to be taken off a casino. Don't know why, but he paid us a whole lot of money. So did the casino security."%_t,
        },
        money = random():getInt(15000, 25000) * Balancing_GetSectorRichnessFactor(x, y),
     }

    table.insert(adventures, adventure)

    -- only resources
    local adventure =
    {
        messages =
        {
            "We crashed into a satellite, just floating through space and not emitting any signals. Who just leaves their junk out like that? But at least we got to scrap it and got some resources out of it!"%_t,
            "We rescued a golden alpaca from some pirates. The owner was super happy to get it back and he gave us a huge reward!"%_t,
            "We found a stash with a message on it: 'To call in a staff meeting, combine a Lightning Gun, Hacking Upgrade, Laser, Railgun and PDC at a research station.'"%_t,
        },
        resources = random():getInt(4000, 7000) *  Balancing_GetSectorRichnessFactor(x, y, 10),
    }

    table.insert(adventures, adventure)

    -- only cargo
    local adventure =
    {
        messages =
        {
            "We found the wreck of a freighter. We believe it must have been attacked by Xsotan, because there were still goods in the cargo bay, and pirates would have taken those. They are in our cargo bay now."%_t,
            "We somehow ended up at an auction that was being held at a station. There weren't very many people there, so we managed to get some great deals!"%_t,
            "We just came across a very old freighter. It was so old, in fact, that it was literally falling apart. We took crew and cargo on board, and they let us keep the cargo after we had taken them to a station."%_t,
            "We found an abandoned station. We had a look around and we found a storage unit that still had goods inside it. We put them into our cargo bay."%_t,
            "We landed on a planet and found a whole bunch of interesting stuff. We should do that more often!"%_t,
            "The 'Commune' hired us to babysit some junkie. He went crazy and we had to chase his ship. This would have been the one time we really could have used some force turrets!"%_t,
        },
        cargoBayFillRatio = 0.5,
    }

    table.insert(adventures, adventure)

    -- only attack blueprints
    local adventure =
    {
        messages =
        {
            "We ran into an old 'friend' who owed us. She gave us turret blueprints."%_t,
            "We found an abandoned ship. Their log files said they were following traces of an ancient alien life form. The only things left on board were turret blueprints."%_t,
            "We met somebody at a rather dodgy bar. He claimed he was an inventor. A guy came in and tried to beat him up because 'his blueprints sucked'. We protected him, and he gave us some of his blueprints."%_t,
        },
        blueprints = {type = "attackTurrets", min = 2, max = 4},
    }

    table.insert(adventures, adventure)

    -- only attack turrets
    local adventure =
    {
        messages =
        {
            "Some Xsotan were attacking a mine, for some reason. We blasted them into pieces. The miners were too poor to pay us a reward, but we looted the Xsotan vessels."%_t,
            "We ran into some Xsotan and they attacked us. But we showed them that we are not as helpless as we might seem!"%_t,
            "We found a wreckage full of deactivated combat bots. We took the liberty to loot their armory."%_t,
            "We heard that a bounty had been put on some renegades of the Cavaliers. We tried to find them, but someone else had already destroyed their ships. We did find some turrets floating in the sector, though."%_t,
            "The sector we just entered still had wreckage parts floating all over it. Somebody had clearly tried to salvage them, but the impacts of the missiles had shot the parts all over the sector."%_t,
        },
        turrets = {type = "attackTurrets", min = 2, max = 4},
    }

    -- cargo and money
    local adventure =
    {
        messages =
        {
            "Some convoy hired us to escort them. I don't really like escort missions, and the ships were always either a bit too slow or a bit too fast, but we were paid well in the end."%_t,
            "We ran into two small ships that said they needed the location of a volcano planet. They also said something about some ring. They did give us money when we pointed them in the right direction."%_t,
            "Some dude called 'Moretti' paid us a lot of money to deliver alcoholic beverages to his friends. No idea why he paid so much, but when it's about sums like this one, I don't ask questions."%_t,
        },
        money = random():getInt(7500, 12500) * Balancing_GetSectorRichnessFactor(x, y),
        cargoBayFillRatio = 0.3,

    }

    -- money and subsytems
    local adventure =
    {
        messages =
        {
            "We received a distress call, but we got there too late. Sad affair. Or it would have been sad, if we hadn't found all this loot."%_t,
            "We took part in a bounty hunt! We had to share the reward, but it was still worth our while."%_t,
            "Commander, apparently somebody put a bounty on our head. Now the loot comes looking for us, and not the other way around!"%_t,
            "We found somebody locked in a compartment on a wreck. He said he was a member of the 'Family' and we would be richly rewarded if we took him back to them. And he was right!"%_t,
            "The 'Cavaliers' paid us to protect some casino from a bunch of bandits. It wasn't terribly exciting, but they paid well."%_t,
        },
        money = random():getInt(7500, 12500) * Balancing_GetSectorRichnessFactor(x, y),
        subsystems = {type = "randomSubsystems", min = 1, max = 3},
    }

    -- cargo and subsytems
    local adventure =
    {
        messages =
        {
            "I made a bet with another captain that our ship was better suited for flying through asteroid fields. This is what I pulled from his wreck."%_t,
            "We helped the 'Commune' free some workers in a mine. We would have kept out of that, but they did offer a huge reward."%_t,
            "Seventeen containers! We had to hack seventeen containers before we finally found something valuable!"%_t,
        },
        cargoBayFillRatio = 0.3,
        subsystems = {type = "randomSubsystems", min = 1, max = 3},
    }
    table.insert(adventures, adventure)

    return adventures
end

-- always the last yield that is sent (special loot depending on captain's class)
function ExpeditionCommand:generateLastAdventure()
    local adventure = {}
    local parent = getParentFaction()
    local entry = ShipDatabaseEntry(parent.index, self.shipName)
    if not valid(entry) then return end
    local captain = entry:getCaptain()

    if captain:hasClass(CaptainUtility.ClassType.Daredevil) then
        adventure =
        {
            messages =
            {
                "We took a shortcut and some pirates challenged us. Of course, we defeated them easily."%_t
            },
            turrets = {type = "attackTurrets", min = 3, max = 4}
        }

    elseif captain:hasClass(CaptainUtility.ClassType.Smuggler) then
        adventure =
        {
            messages =
            {
                "Somehow, some goods ended up in our cargo bay. Somebody at the trading post must have accidentally loaded them onto our ship instead of onto the one it was really meant for."%_t
            },
            cargoBayFillRatio = 0.5
        }

    elseif captain:hasClass(CaptainUtility.ClassType.Merchant) then
        adventure =
        {
            messages =
            {
                "We have been able to dust off a subsystem from the insolvency estate of a counterparty."%_t
            },
            subsystems = {type = "data/scripts/systems/tradingoverview.lua", min = 1, max = 1},
        }

    elseif captain:hasClass(CaptainUtility.ClassType.Miner) then
        adventure =
        {
            messages =
            {
                "We helped a stranded mining vessel and helped them repair their engines. They were really grateful and let us have some of their mining turrets."%_t
            },
            turrets = {type = "miningTurrets", min = 3, max = 4}
        }

    elseif captain:hasClass(CaptainUtility.ClassType.Scavenger) then
        adventure =
        {
            messages =
            {
                "We almost crashed into a wreck that was in hidden plain sight. At first we thought it might be stealth tech, but it just blended really well with the sector. We salvaged it anyways."%_t
            },
            turrets = {type = "salvagingTurrets", min = 3, max = 4}
        }

    elseif captain:hasClass(CaptainUtility.ClassType.Explorer) then
        adventure =
        {
            messages =
            {
                "We found subsystems in a strange anomaly!"%_t
            },
            subsystems = {type = "randomSubsystems", min = 1, max = 2},
        }

    else
        adventure =
        {
            messages =
            {
                "We have completed the expedition."%_t
            }
        }
    end

    return adventure
end

function ExpeditionCommand:calculateYieldRarity(yieldNumber) -- calculate rarity of items depending on how many yields the player has already received
    local number = yieldNumber or 1
    local rarity = 0

    if number == 1 then
        if random():test(0.5) then rarity = RarityType.Uncommon
        else
            if random():test(0.5) then rarity = RarityType.Common
            else rarity = RarityType.Rare end
        end
    elseif number == 2 then
        if random():test(0.5) then rarity = RarityType.Rare
        else
            if random():test(0.5) then rarity = RarityType.Uncommon
            else rarity = RarityType.Exceptional end
        end
    elseif number == 3 then
        if random():test(0.5) then rarity = RarityType.Exceptional
        else
            if random():test(0.5) then rarity = RarityType.Rare
            else rarity = RarityType.Exotic end
        end
    elseif number == 4 then
        if random():test(0.5) then rarity = RarityType.Exotic
        else
            if random():test(0.6) then rarity = RarityType.Exceptional
            else rarity = RarityType.Rare end
        end
    elseif number == 5 then
        if random():test(0.5) then rarity = RarityType.Exceptional
        else
            if random():test(0.5) then rarity = RarityType.Exotic
            else rarity = RarityType.Legendary end
        end
    end

    return rarity
end

-- after this function was called, self.data will be read to be saved to database
function ExpeditionCommand:onSecure()

end

-- this is called after the command was recreated and self.data was assigned
function ExpeditionCommand:onRestore()

end

function ExpeditionCommand:onAttacked(attackerFaction, x, y)

end

function ExpeditionCommand:getAreaSize(ownerIndex, shipName)
    return {x = 15, y = 15}
end

function ExpeditionCommand:getAreaBounds()
    return {lower = self.area.lower, upper = self.area.upper}
end

function ExpeditionCommand:isAreaFixed(ownerIndex, shipName)
    return false
end

function ExpeditionCommand:isShipRequiredInArea(ownerIndex, shipName)
    return true
end

function ExpeditionCommand:getIcon()
    return "data/textures/icons/expedition-command.png"
end

function ExpeditionCommand:getDescriptionText()
    local totalRuntime = self.config.duration * 60
    local timeRemaining = round((totalRuntime - self.data.runTime) / 60)
    local completed = round(self.data.runTime / totalRuntime * 100)

    return "The ship is on an expedition.\n\nTime remaining: ${timeRemaining} (${completed} % done)."%_T, {timeRemaining = createReadableShortTimeString(timeRemaining * 60), completed = completed}
end

function ExpeditionCommand:getStatusMessage()
    return "Exploring"%_t
end

function ExpeditionCommand:getRecallError()
end

-- returns whether the config sent by a client has errors
-- note: before this is called, there is already a preliminary check based on getConfigurableValues(), where values are clamped or default-set
-- note: this may be called on a temporary instance of the command. all values written to "self" may not persist
function ExpeditionCommand:getErrors(ownerIndex, shipName, area, config)
    local entry = ShipDatabaseEntry(ownerIndex, shipName)
    local freeCargoSpace = entry:getFreeCargoSpace()

    if freeCargoSpace == 0 then
       return "Not enough cargo space!"%_t, {}
    end

    if area.analysis.validArea == false then
        return "There is nothing to explore in this area, we are too deep in faction territory! We should try starting an expedition in a mostly uninhabited area."%_T, {}
    end
end

function ExpeditionCommand:getAreaSelectionTooltip(shipName, area, valid)
    return "Left-Click to select the expedition area"%_t
end

-- returns the configurable values for this command (if any).
-- variable naming should speak for itself, though you're free to do whatever you want in here.
-- config will only be used by the command itself and nothing else
-- this may be called on a temporary instance of the command. all values written to "self" may not persist
function ExpeditionCommand:getConfigurableValues(ownerIndex, shipName)
    local values = { }

    -- value names here must match with values returned in ui:buildConfig() below
    values.duration = {displayName = "Duration"%_t, from = 30, to = 120, default = 30}

    return values
end

-- returns the predictable values for this command (if any).
-- variable naming should speak for itself, though you're free to do whatever you want in here.
-- config will only be used by the command itself and nothing else
-- this may be called on a temporary instance of the command. all values written to "self" may not persist
function ExpeditionCommand:getPredictableValues()
    local values = { }

    values.attackChance = {displayName = SimulationUtility.AttackChanceLabelCaption}

    return values
end

-- calculate the predictions for the ship, area and config
-- gut feeling says that each config option change should always be reflected in the predictions if it impacts the behavior
-- this may be called on a temporary instance of the command. all values written to "self" may not persist
function ExpeditionCommand:calculatePrediction(ownerIndex, shipName, area, config)
    local results = self:getPredictableValues()

    local x = (area.lower.x + area.upper.x) / 2
    local y = (area.lower.y + area.upper.y) / 2

    results.maxMoney = round((12500 * Balancing_GetSectorRichnessFactor(x, y)) / 500) * 500
    results.maxMaterials = round((7000 * Balancing_GetSectorRichnessFactor(x, y, 10)) / 500) * 500

    results.attackChance.value, results.attackLocation = SimulationUtility.calculateAttackProbability(ownerIndex, shipName, area, config.escorts, config.duration/60)

    return results
end

local function getRegionLines(area, config)
    local result = {}
    local badArea = false

    local total = area.analysis.sectors - area.analysis.unreachable
    if total == 0 then
        table.insert(result, "There is nothing to explore in this area!"%_t)
        badArea = true
    end

    local unchartedSectors = #area.analysis.nonFactionSectors / #area.analysis.reachableCoordinates

    if unchartedSectors > 0.9 then
        table.insert(result, "This is a very good area to have adventures. It seems like most of this is uncharted territory."%_t)
        table.insert(result, "The area looks very exciting. I'm sure we'll be able to run into quite a lot of adventures."%_t)
    elseif unchartedSectors > 0.8 then
        table.insert(result, "There is a lot to explore in this area. I hope that we will be able to have quite some adventures."%_t)
        table.insert(result, "This area looks all right. I will definitely find some adventures here."%_t)
        table.insert(result, "I will definitely find adventures in this area. There is enough uncharted territory here."%_t)
    elseif unchartedSectors > 0.7 then
        table.insert(result, "\\c(dd5)This area seems not very well suited for exploring something new here. Maybe we should try a different area.\\c()"%_t)
        table.insert(result, "\\c(dd5)According to initial calculations, the area is not ideal, it might be difficult to find something exciting here.\\c()"%_t)
    elseif unchartedSectors > 0.66 then
        table.insert(result, "\\c(d93)This area is much too overrun. I will not find much here.\\c()"%_t)
        table.insert(result, "\\c(d93)This is a super boring area. I will not find many exciting adventures here.\\c()"%_t)
        table.insert(result, "\\c(d93)I will have virtually no adventures in this area. This area is much too populated.\\c()"%_t)
    else
        badArea = true
        table.insert(result, "There is nothing to explore in this area, we are too deep in faction territory! We should try starting an expedition in a mostly uninhabited area."%_t)
    end

    return result, badArea
end

function ExpeditionCommand:generateAssessmentFromPrediction(prediction, captain, ownerIndex, shipName, area, config)
    local attackChance = prediction.attackChance.value
    local pirateSectorRatio = SimulationUtility.calculatePirateAttackSectorRatio(area)

    local regionLines, badArea = getRegionLines(area, config)

    local entry = ShipDatabaseEntry(ownerIndex, shipName)
    local captain = entry:getCaptain()
    local cargo = entry:getCargo()
    local stolenOrIllegal, dangerousOrSuspicious = SimulationUtility.getSpecialCargoCategories(cargo)
    local cargobayLines = SimulationUtility.getIllegalCargoAssessmentLines(stolenOrIllegal, dangerousOrSuspicious, captain)

    local pirateLines = SimulationUtility.getPirateAssessmentLines(pirateSectorRatio)
    local attackLines = SimulationUtility.getAttackAssessmentLines(attackChance)
    local underRadar, returnLines = SimulationUtility.getDisappearanceAssessmentLines(attackChance)

    local rnd = Random(Seed(captain.name))

    if badArea == false then
        return {
            randomEntry(rnd, regionLines),
            randomEntry(rnd, pirateLines),
            randomEntry(rnd, attackLines),
            randomEntry(rnd, cargobayLines),
            randomEntry(rnd, underRadar),
            randomEntry(rnd, returnLines),
        }
    else
        return {randomEntry(rnd, regionLines)}
    end
end

-- this will be called on a temporary instance of the command. all values written to "self" will not persist
function ExpeditionCommand:buildUI(startPressedCallback, changeAreaPressedCallback, recallPressedCallback, configChangedCallback)
    local ui = {}

    ui.orderName = "Expedition"%_t
    ui.icon = ExpeditionCommand:getIcon()

    local size = vec2(600, 600)

    ui.window = GalaxyMap():createWindow(Rect(size))
    ui.window.caption = "Expedition"%_t

    ui.commonUI = SimulationUtility.buildCommandUI(ui.window, startPressedCallback, changeAreaPressedCallback, recallPressedCallback, configChangedCallback, {areaHeight = 130, configHeight = 50, changeAreaButton = true})

    -- configurable values
    local configValues = self:getConfigurableValues()

    local vsplitConfig = UIVerticalSplitter(ui.commonUI.configRect, 30, 10, 0.35)
    vsplitConfig:setPadding(40, 40, 0, 0)

    local vlist = UIVerticalLister(vsplitConfig.left, 10, 0)
    ui.window:createLabel(vlist:nextRect(25), configValues.duration.displayName .. ":", 15)

    local vlist = UIVerticalLister(vsplitConfig.right, 10, 0)
    ui.durationSlider = ui.window:createSlider(vlist:nextRect(25), 30, 120, 3, "min", configChangedCallback)

    -- yields & issues
    local predictable = self:getPredictableValues()

    local vsplitPrediction = UIVerticalSplitter(ui.commonUI.predictionRect, 10, 0, 0.5)
    local vlist = UIVerticalLister(vsplitPrediction.left, 10, 0)
    local label = ui.window:createLabel(vlist:nextRect(15), predictable.attackChance.displayName .. ":", 12)
    ui.window:createLabel(vlist:nextRect(15), "Adventures:"%_t, 12)
    label.tooltip = SimulationUtility.AttackChanceLabelTooltip
    vlist:nextRect(20)
    vlist:nextRect(20)
    ui.creditsIcon = ui.window:createPicture(vlist:nextRect(20), "data/textures/icons/money.png");
    ui.creditsIcon.width = 20
    ui.creditsIcon.isIcon = true
    ui.creditsIcon.tooltip = "Credits"%_t
    ui.resourcesIcon = ui.window:createPicture(vlist:nextRect(20), "data/textures/icons/rock.png");
    ui.resourcesIcon.width = 20
    ui.resourcesIcon.isIcon = true
    ui.resourcesIcon.tooltip = "Resources"%_t
    local iconsSplit = UIArbitraryVerticalSplitter(vlist:nextRect(20), 0, 0, 20, 25, 45, 50, 70)
    ui.turretIcon = ui.window:createPicture(iconsSplit:partition(0), "data/textures/icons/turret.png");
    ui.turretIcon.width = 20
    ui.turretIcon.isIcon = true
    ui.turretIcon.tooltip = "Turrets, subsystems or turret blueprints"%_t
    ui.subsystemsIcon = ui.window:createPicture(iconsSplit:partition(2), "data/textures/icons/circuitry.png");
    ui.subsystemsIcon.width = 20
    ui.subsystemsIcon.isIcon = true
    ui.subsystemsIcon.tooltip = "Turrets, subsystems or turret blueprints"%_t
    ui.blueprintIcon = ui.window:createPicture(iconsSplit:partition(4), "data/textures/icons/turret.png");
    ui.blueprintIcon.width = 20
    ui.blueprintIcon.isIcon = true
    ui.blueprintIcon.color = ColorRGB(1, 1, 1)
    ui.blueprintIcon.tooltip = "Turrets, subsystems or turret blueprints"%_t
    ui.backgroundFrame = ui.window:createFrame(iconsSplit:partition(4))
    ui.backgroundFrame.backgroundColor = ColorARGB(0.5, 0, 0, 1)
    ui.cargoIcon = ui.window:createPicture(vlist:nextRect(20), "data/textures/icons/crate.png");
    ui.cargoIcon.width = 20
    ui.cargoIcon.isIcon = true
    ui.cargoIcon.tooltip = "Goods"%_t
    ui.window:createLabel(vlist:nextRect(20), "", 12)

    local vlist = UIVerticalLister(vsplitPrediction.right, 10, 0)
    local vlist2 = UIVerticalLister(vsplitPrediction.left, 10, 0)
    vlist2:nextRect(15)
    vlist2:nextRect(15)
    vlist2:nextRect(15)
    ui.commonUI.attackChanceLabel = ui.window:createLabel(vlist:nextRect(15), "", 12)
    ui.adventureLabel = ui.window:createLabel(vlist:nextRect(15), "", 12)
    vlist:nextRect(15)
    vlist:nextRect(15)
    ui.window:createLabel(vlist2:nextRect(22), "Per adventure: "%_t, 12)
    ui.moneyLabel = ui.window:createLabel(vlist:nextRect(22), "", 12)
    ui.moneyLabel:setRightAligned()
    ui.materialsLabel = ui.window:createLabel(vlist:nextRect(22), "", 12)
    ui.materialsLabel:setRightAligned()
    ui.upgradeLabel = ui.window:createLabel(vlist:nextRect(22), "", 12)
    ui.upgradeLabel:setRightAligned()
    ui.cargoLabel = ui.window:createLabel(vlist:nextRect(22), "", 12)
    ui.cargoLabel:setRightAligned()

    local hsplitBottom = UIHorizontalSplitter(Rect(size), 10, 10, 0.5)
    hsplitBottom.bottomSize = 40
    local vsplit = UIVerticalMultiSplitter(hsplitBottom.bottom, 10, 0, 3)

    ui.clear = function(self, shipName)
        self.commonUI:clear(shipName)
    end

    -- used to fill values into the UI
    -- config == nil means fill with default values
    ui.refresh = function(self, ownerIndex, shipName, area, config)
        self.commonUI:refresh(ownerIndex, shipName, area, config)

        if not config then
            -- no config: fill UI with default values, then build config, then use it to calculate yields
            local values = ExpeditionCommand:getConfigurableValues(ownerIndex, shipName)

            -- use "setValueNoCallback" since we don't want to trigger "refreshPredictions()" while filling in default values
            self.durationSlider:setValueNoCallback(values.duration.default)

            config = self:buildConfig()
        end

        self:refreshPredictions(ownerIndex, shipName, area, config)
    end

    -- each config option change should always be reflected in the predictions if it impacts the behavior
    ui.refreshPredictions = function(self, ownerIndex, shipName, area, config)
        local prediction = ExpeditionCommand:calculatePrediction(ownerIndex, shipName, area, config)
        self:displayPrediction(prediction, config, ownerIndex)

        self.commonUI:refreshPredictions(ownerIndex, shipName, area, config, ExpeditionCommand, prediction)
    end

    ui.displayPrediction = function(self, prediction, config, ownerIndex)
        self.commonUI:setAttackChance(prediction.attackChance.value)

        self.adventureLabel.caption = math.max(1, round(self.durationSlider.value / 30) - 1) .. " - " .. round(self.durationSlider.value / 30) + 1

        self.moneyLabel.caption = string.format("¢0 - ¢${maxMoney}"%_t % {maxMoney = createMonetaryString(prediction.maxMoney)})
        self.materialsLabel.caption = "0 - " .. createMonetaryString(prediction.maxMaterials)
        self.upgradeLabel.caption = "0 - 4"
        self.cargoLabel.caption = "0% - 30%"
        self.cargoLabel.tooltip = "Cargobay usage"%_t
    end

    -- used to build a config table for the command, based on values configured in the UI
    -- each config option change should always be reflected in the predictions if it impacts the behavior
    ui.buildConfig = function(self)
        local config = {}

        config.duration = self.durationSlider.value
        config.escorts = self.commonUI.escortUI:buildConfig()

        return config
    end

    ui.setActive = function(self, active, description)
        self.commonUI:setActive(active, description)

        self.durationSlider.active = active
    end

    ui.displayConfig = function(self, config, ownerIndex)
        self.durationSlider:setValueNoCallback(config.duration)
    end

    return ui
end


return setmetatable({new = new}, {__call = function(_, ...) return new(...) end})
