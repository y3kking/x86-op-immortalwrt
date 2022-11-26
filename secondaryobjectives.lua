package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"

local SectorGenerator = include("SectorGenerator")
local AsteroidPlanGenerator = include("asteroidplangenerator")
local RiftObjects = include("dlc/rift/lib/riftobjects")
local Xsotan = include("story/xsotan")

include("utility")
include("stringutility")
include("randomext")

local SecondaryObjectives = {}

-- The existing UUIDs should NOT be changed
-- the order of the objectives in the table doesn't matter, feel free to sort/organize
-- UUIDs were generated using https://www.uuidgenerator.net/ (Version 4 UUID)
SecondaryObjectives.Type =
{
    ScanFormations = "7008f90c-9030-4b63-a6ba-d1af09dcc13c",
    CollectCrystals = "804f3f34-eb94-4090-965b-662b87689417",
    CollectAncientArtifacts = "3c90f861-2fba-4da6-a0b1-c3fddba9b710",
    CollectXsotanSamples = "78184a83-c7db-4386-9018-ceae40b63f9e",
}

SecondaryObjectives.NonStory = table.deepcopy(SecondaryObjectives.Type)

function SecondaryObjectives.getLocations(specs, numLocations)
    local locations = {}

    -- case: only 1 landmark, 0 paths
    if #specs.paths == 0 then
        for i = 1, numLocations do
            table.insert(locations, specs.landmarks[1].location + random():getDirection() * random():getFloat(500, 1000))
        end

        return locations
    end

    while #locations < numLocations do
        local landmarksDone = {}
        for _, path in pairs(specs.paths) do
            -- add a location on the path
            local location = lerp(random():getFloat(0.2, 0.8), 0, 1, path.a.location, path.b.location)
            table.insert(locations, location + random():getDirection() * random():getFloat(200, 800))

            -- add a location at the landmarks of the path
            if not landmarksDone[path.a] then
                table.insert(locations, path.a.location + random():getDirection() * random():getFloat(500, 1000))
            end

            if not landmarksDone[path.b] then
                table.insert(locations, path.b.location + random():getDirection() * random():getFloat(500, 1000))
            end

            -- remember which landmarks we had already to avoid them being overrepresented
            landmarksDone[path.a] = true
            landmarksDone[path.b] = true
        end
    end

    -- since we're always adding to all paths and all landmarks, we'll overshoot the number of locations in most cases
    local tooMany = #locations - numLocations
    for i = 1, tooMany do
        table.remove(locations)
    end

    return locations
end

function SecondaryObjectives.createScannableFormation(position)
    local generator = AsteroidPlanGenerator()
    generator.Stone = BlockType.BlankHull
    generator.StoneEdge = BlockType.EdgeHull
    generator.StoneCorner = BlockType.CornerHull
    generator.StoneOuterCorner = BlockType.OuterCornerHull
    generator.StoneInnerCorner = BlockType.InnerCornerHull
    generator.StoneTwistedCorner1 = BlockType.TwistedCorner1
    generator.StoneTwistedCorner2 = BlockType.TwistedCorner2
    generator.StoneFlatCorner = BlockType.FlatCornerHull
    generator.RichStone = BlockType.BlankHull
    generator.RichStoneEdge = BlockType.EdgeHull
    generator.RichStoneCorner = BlockType.CornerHull
    generator.RichStoneInnerCorner = BlockType.InnerCornerHull
    generator.RichStoneOuterCorner = BlockType.OuterCornerHull
    generator.RichStoneTwistedCorner1 = BlockType.TwistedCorner1
    generator.RichStoneTwistedCorner2 = BlockType.TwistedCorner2
    generator.RichStoneFlatCorner = BlockType.FlatCornerHull
    generator.SuperRichStone = BlockType.BlankHull
    generator.SuperRichStoneEdge = BlockType.EdgeHull
    generator.SuperRichStoneCorner = BlockType.CornerHull
    generator.SuperRichStoneInnerCorner = BlockType.InnerCornerHull
    generator.SuperRichStoneOuterCorner = BlockType.OuterCornerHull
    generator.SuperRichStoneTwistedCorner1 = BlockType.TwistedCorner1
    generator.SuperRichStoneTwistedCorner2 = BlockType.TwistedCorner2
    generator.SuperRichStoneFlatCorner = BlockType.FlatCornerHull

    local material = Material(MaterialType.Titanium)
    local generationFunctions = {
        function() return generator:makeTitaniumAsteroidPlan(10, material, {}) end,
        function() return generator:makeTriniumAsteroidPlan(10, material, {}) end,
        function() return generator:makeXanionAsteroidPlan(10, material, {}) end,
        function() return generator:makeOgoniteAsteroidPlan(10, material, {}) end,
        function() return generator:makeAvorionAsteroidPlan(10, material, {}) end,
        function() return generator:makeCuboidAsteroidPlan(10, material) end,
        function() return generator:makeMonolithAsteroidPlan(10, material) end,
    }
    local plan = randomEntry(generationFunctions)()
    plan:setColor(ColorRGB(0.25, 0.25, 0.25))

    local desc = RiftObjects.makeSimpleRiftObjectDescriptor(position)
    desc:setMovePlan(plan)
    desc.title = "Metal Formation"%_T
    desc:setValue("secondary_objective_scannable", true)
    desc:setValue("valuable_object", RarityType.Rare) -- give players with an object detector an advantage

    local object = Sector():createEntity(desc)
    local droppedData = 1
    object:addScript("internal/dlc/rift/entity/riftobjects/scannableobject.lua", droppedData)

    return object
end

function SecondaryObjectives.updateDescription(bulletPoints)
    -- send it to all players
    for _, player in pairs({Sector():getPlayers()}) do
        player:invokeFunction("riftmission.lua", "setSecondaryObjectiveDescription", bulletPoints)
    end
end

SecondaryObjectives[SecondaryObjectives.Type.ScanFormations] = {
    icon = "data/textures/icons/secondary-scan-formations.png",
    name = "Strange Metal Formations"%_t,
    description = "Strange metal formations were found in the rifts. These must be investigated."%_t,

    -- creates an instance that can be used to track the progress of the secondary objective
    makeInstance = function(self, namespaceIn)
        return {
            namespace = namespaceIn or _G,
            scanned = 0,
            toScan = 4,
            preGeneration = function(self, specs) end,
            postGeneration = function(self, specs)
                local numLocations = random():getInt(6, 7)
                local locations = SecondaryObjectives.getLocations(specs, numLocations)

                for _, location in pairs(locations) do
                    local position = MatrixLookUpPosition(random():getDirection(), random():getDirection(), location)
                    local object = SecondaryObjectives.createScannableFormation(position)
                    object:setValue("highlight_color", Rarity(RarityType.Rare).color.html)
                end

                -- listen for callback from scannableobject.lua
                self.namespace["ScanFormationsObjective_onFormationScanned"] = function(id)
                    local entity = Entity(id)
                    if entity:getValue("secondary_objective_scannable") then
                        self.scanned = self.scanned + 1
                    end
                end

                Sector():registerCallback("onObjectScanCompleted", "ScanFormationsObjective_onFormationScanned")
            end,
            update = function(self, timeStep)
                local fulfilled = self.scanned >= self.toScan

                local bulletPoints = {}
                bulletPoints[1] = {
                    text = "(optional) Strange Metal Formations scanned\n${count}/${total}"%_T,
                    arguments = {count = math.min(self.scanned, self.toScan), total = self.toScan},
                    bulletPoint = true,
                    fulfilled = fulfilled,
                    visible = true
                }

                SecondaryObjectives.updateDescription(bulletPoints)

                if fulfilled and not self.rewarded then
                    self.rewarded = true

                    local relations = nil
                    local riftResearchData = 15

                    -- assign it to all players
                    for _, player in pairs({Sector():getPlayers()}) do
                        player:invokeFunction("riftmission.lua", "setSecondaryObjectiveReward", relations, riftResearchData)
                    end
                end
            end,
        }
    end
}


function SecondaryObjectives.createCrystallineAsteroid(position)
    local generator = AsteroidPlanGenerator()
    generator.Stone = BlockType.Glass
    generator.StoneEdge = BlockType.GlassEdge
    generator.StoneCorner = BlockType.GlassCorner
    generator.StoneOuterCorner = BlockType.GlassOuterCorner
    generator.StoneInnerCorner = BlockType.GlassInnerCorner
    generator.StoneTwistedCorner1 = BlockType.GlassTwistedCorner1
    generator.StoneTwistedCorner2 = BlockType.GlassTwistedCorner2
    generator.StoneFlatCorner = BlockType.GlassFlatCorner
    generator.RichStone = BlockType.Glass
    generator.RichStoneEdge = BlockType.GlassEdge
    generator.RichStoneCorner = BlockType.GlassCorner
    generator.RichStoneInnerCorner = BlockType.GlassInnerCorner
    generator.RichStoneOuterCorner = BlockType.GlassOuterCorner
    generator.RichStoneTwistedCorner1 = BlockType.GlassTwistedCorner1
    generator.RichStoneTwistedCorner2 = BlockType.GlassTwistedCorner2
    generator.RichStoneFlatCorner = BlockType.GlassFlatCorner
    generator.SuperRichStone = BlockType.Glass
    generator.SuperRichStoneEdge = BlockType.GlassEdge
    generator.SuperRichStoneCorner = BlockType.GlassCorner
    generator.SuperRichStoneInnerCorner = BlockType.GlassInnerCorner
    generator.SuperRichStoneOuterCorner = BlockType.GlassOuterCorner
    generator.SuperRichStoneTwistedCorner1 = BlockType.GlassTwistedCorner1
    generator.SuperRichStoneTwistedCorner2 = BlockType.GlassTwistedCorner2
    generator.SuperRichStoneFlatCorner = BlockType.GlassFlatCorner

    local material = Material(MaterialType.Titanium)
    local generationFunctions = {
        function() return generator:makeTitaniumAsteroidPlan(10, material, {}) end,
        function() return generator:makeTriniumAsteroidPlan(10, material, {}) end,
        function() return generator:makeXanionAsteroidPlan(10, material, {}) end,
        function() return generator:makeOgoniteAsteroidPlan(10, material, {}) end,
        function() return generator:makeAvorionAsteroidPlan(10, material, {}) end,
    }
    local plan = randomEntry(generationFunctions)()
    plan:setColor(ColorRGB(0.4, 0.9, 0.9))

    local desc = RiftObjects.makeSimpleRiftObjectDescriptor(position)
    desc.type = EntityType.Asteroid
    desc:setMovePlan(plan)
    desc.title = "Crystal Formation"%_T
    desc:setValue("secondary_objective_crystal_asteroid", true)
    desc:setValue("valuable_object", RarityType.Rare) -- give players with an object detector an advantage

    local good = TradingGood("Rift Crystal"%_T, plural_t("Rift Crystal", "Rift Crystals", 1), "Rift Crystal which can be used for laser research. The scientists at the Rift Research Center will be interested in it."%_t, "data/textures/icons/crystal.png", 10, 0.1)
    good.mesh = "data/meshes/trading-goods/crystal.obj"
    good.tags = {rift_mission_item = true, secondary_objective_rift_crystal = true, mission_relevant = true}

    local object = Sector():createEntity(desc)
    object:addScript("utility/droptradinggoods.lua", good)
    object:addScript("internal/dlc/rift/entity/crystalasteroidsparkle.lua")

    return object
end

SecondaryObjectives[SecondaryObjectives.Type.CollectCrystals] = {
    icon = "data/textures/icons/secondary-collect-crystals.png",
    name = "Rift Crystals"%_t,
    description = "Scientists need these special Rift Crystals for laser research. They can be found in distinctive crystal formations."%_t,

    -- creates an instance that can be used to track the progress of the secondary objective
    makeInstance = function(self, namespaceIn)
        return {
            namespace = namespaceIn or _G,

            collected = 0,
            toCollect = 200,
            preGeneration = function(self, specs) end,
            postGeneration = function(self, specs)
                local numLocations = random():getInt(10, 12)
                local locations = SecondaryObjectives.getLocations(specs, numLocations)

                for _, location in pairs(locations) do
                    local position = MatrixLookUpPosition(random():getDirection(), random():getDirection(), location)
                    local asteroid = SecondaryObjectives.createCrystallineAsteroid(position)
                    asteroid:setValue("highlight_color", "6dd")
                end

                -- listen for cargo change callback
                self.namespace["CollectCrystalsObjective_onCargoChanged"] = function(id, delta, good)
                    if not good.tags.secondary_objective_rift_crystal then return end

                    self.collected = self.collected + delta
                end

                Sector():registerCallback("onCargoChanged", "CollectCrystalsObjective_onCargoChanged")

            end,
            update = function(self, timeStep)
                local fulfilled = self.collected >= self.toCollect

                local bulletPoints = {}
                bulletPoints[1] = {
                    text = "(optional) Collect Rift Crystals\n${count}/${total}"%_T,
                    arguments = {count = math.max(0, math.min(self.collected, self.toCollect)), total = self.toCollect},
                    bulletPoint = true,
                    fulfilled = fulfilled,
                    visible = true
                }

                SecondaryObjectives.updateDescription(bulletPoints)

                if fulfilled and not self.rewarded then
                    self.rewarded = true

                    local relations = 2000
                    local riftResearchData = 10

                    -- assign it to all players
                    for _, player in pairs({Sector():getPlayers()}) do
                        player:invokeFunction("riftmission.lua", "setSecondaryObjectiveReward", relations, riftResearchData)
                    end
                end
            end,
        }
    end
}

SecondaryObjectives[SecondaryObjectives.Type.CollectAncientArtifacts] = {
    icon = "data/textures/icons/secondary-collect-holos.png",
    name = "Ancient Artifacts"%_t,
    description = "A collector is interested in the culture of people from 200 years ago and would like some original objects. You can find them in old wreckages."%_t,

    -- creates an instance that can be used to track the progress of the secondary objective
    makeInstance = function(self, namespaceIn)
        return {
            namespace = namespaceIn or _G,

            collected = 0,
            toCollect = 50,

            preGeneration = function(self, specs) end,
            postGeneration = function(self, specs)
                -- find all wreckages that could hold the desired cargo
                local wreckages = {Sector():getEntitiesByType(EntityType.Wreckage)}
                local cargoWreckages = {}
                for _, wreckage in pairs(wreckages) do
                    if wreckage.freeCargoSpace > 2 then
                        table.insert(cargoWreckages, wreckage)
                    end
                end

                -- spawn additional ones if there aren't enough
                if #cargoWreckages < 5 then
                    local x, y = Sector():getCoordinates()
                    local faction = Galaxy():getNearestFaction(x, y)

                    local numLocations = random():getInt(6, 8)
                    local locations = SecondaryObjectives.getLocations(specs, numLocations)

                    local generator = SectorGenerator(x, y)

                    for _, location in pairs(locations) do
                        local position = MatrixLookUpPosition(random():getDirection(), random():getDirection(), location)
                        local wreckage = generator:createUnstrippedWreckage(faction, nil, 0, position)
                        if wreckage.freeCargoSpace > 2 then
                            table.insert(cargoWreckages, wreckage)
                        end
                    end
                end

                -- x8 because only 25% of goods in an object are dropped and we don't want to force players to search all wreckages
                local numToDistribute = self.toCollect * 4 * 2

                local goods = {}
                table.insert(goods, TradingGood("Ancient Pop Culture Holo"%_T, plural_t("Ancient Pop Culture Holo", "Ancient Pop Culture Holos", 1), "A Pop Culture Holo which was popular several hundred years ago. At best interesting for collectors."%_t, "data/textures/icons/ancient-holo.png", 10, 0.1))
                table.insert(goods, TradingGood("Ancient Food"%_T, plural_t("Ancient Food", "Ancient Food", 1), "Food from several hundred years ago. Better don't eat that."%_T, "data/textures/icons/ancient-holo.png", 10, 0.1))
                table.insert(goods, TradingGood("Ancient Tech Fragment"%_T, plural_t("Ancient Tech Fragment", "Ancient Tech Fragments", 1), "Completely outdated technology from several hundreds of years ago. At best interesting for collectors."%_t, "data/textures/icons/ancient-holo.png", 10, 0.1))

                for _, good in pairs(goods) do
                    good.mesh = "data/meshes/trading-goods/crate-02.obj"
                    good.tags = {rift_mission_item = true, secondary_objective_ancient_artifact = true, mission_relevant = true}
                end

                local cargoHold = 0
                local numPerWreckage = math.max(20, math.ceil(numToDistribute / #cargoWreckages))
                for _, wreckage in pairs(cargoWreckages) do
                    cargoHold = cargoHold + wreckage.freeCargoSpace
                    wreckage:addCargo(randomEntry(goods), numPerWreckage)
                    wreckage:setValue("valuable_object", RarityType.Rare) -- give players with an object detector an advantage
                    wreckage:setValue("highlight_color", Rarity(RarityType.Rare).color.html)
                end

                -- listen for cargo change callback
                self.namespace["CollectAncientArtifacts_onCargoChanged"] = function(id, delta, good)
                    if not good.tags.secondary_objective_ancient_artifact then return end

                    local entity = Entity(id)
                    if valid(entity) and entity.playerOrAllianceOwned then
                        self.collected = self.collected + delta
                    end
                end

                Sector():registerCallback("onCargoChanged", "CollectAncientArtifacts_onCargoChanged")
            end,
            update = function(self, timeStep)
                local fulfilled = self.collected >= self.toCollect

                local bulletPoints = {}
                bulletPoints[1] = {
                    text = "(optional) Collect Ancient Artifacts\n${count}/${total}"%_T,
                    arguments = {count = math.max(0, math.min(self.collected, self.toCollect)), total = self.toCollect},
                    bulletPoint = true,
                    fulfilled = fulfilled,
                    visible = true
                }

                SecondaryObjectives.updateDescription(bulletPoints)

                if fulfilled and not self.rewarded then
                    self.rewarded = true

                    local relations = 5000
                    local riftResearchData = nil

                    -- assign it to all players
                    for _, player in pairs({Sector():getPlayers()}) do
                        player:invokeFunction("riftmission.lua", "setSecondaryObjectiveReward", relations, riftResearchData)
                    end
                end
            end,
        }
    end
}

function SecondaryObjectives.createXsotanSampleBreeder(position)
    local sector = Sector()
    local probabilities = Balancing_GetTechnologyMaterialProbability(sector:getCoordinates())
    local material = Material(getValueFromDistribution(probabilities))

    local generator = AsteroidPlanGenerator()
    generator:setToRiftStone()

    local size = random():getFloat(4, 5)
    local generationFunctions = {
        function() return generator:makeTitaniumAsteroidPlan(size, material, {}) end,
        function() return generator:makeTriniumAsteroidPlan(size, material, {}) end,
        function() return generator:makeXanionAsteroidPlan(size, material, {}) end,
        function() return generator:makeOgoniteAsteroidPlan(size, material, {}) end,
        function() return generator:makeAvorionAsteroidPlan(size, material, {}) end,
        function() return generator:makeCuboidAsteroidPlan(size, material) end,
        function() return generator:makeMonolithAsteroidPlan(size, material) end,
    }
    local plan = randomEntry(generationFunctions)()

    local infectionLevel = 3
    local addition = Xsotan.makeInfectAddition(vec3(size * 2.0, size * 0.5, size * 2.0), material, infectionLevel)
    plan:addPlan(plan.rootIndex, addition, 0)

    local desc = RiftObjects.makeRiftObjectDescriptor(position)
    desc:setMovePlan(plan)
    desc.title = "Unusual Xsotan Breeder"%_t
    desc.factionIndex = Xsotan.getFaction().index
    desc:setValue("secondary_objective_xsotan_breeder", true)
    desc:setValue("valuable_object", RarityType.Rare) -- give players with an object detector an advantage

    local good = TradingGood("Xsotan Sample"%_T, plural_t("Xsotan Sample", "Xsotan Samples", 1), "A sample from an unusual Xsotan breeder from within a rift. Several military instances are interested in researching those to find ways to fight the Xsotan."%_T, "data/textures/icons/xsotan-sample.png", 10, 0.1)
    good.mesh = "ore_" .. Rarity(RarityType.Legendary).color.html
    good.tags = {rift_mission_item = true, secondary_objective_xsotan_sample = true, mission_relevant = true}

    desc:setValue("inconspicuous_indicator", true)
    desc:setValue("xsotan_no_despawn", true)
    desc:setValue("is_xsotan", true)
    desc:addScriptOnce("ai/patrol.lua")
    desc:addScriptOnce("utility/aiundockable.lua")
    desc:addScriptOnce("internal/dlc/rift/entity/xsotansamplebreeder.lua")

    local asteroid = sector:createEntity(desc)
    asteroid:addScript("utility/droptradinggoods.lua", good, false, true) -- no drop on block destruction, but drop on normal destruction

    local hangar = Hangar(asteroid)
    for i = 1, 10 do
        hangar:addSquad(i)
    end

    return asteroid
end

SecondaryObjectives[SecondaryObjectives.Type.CollectXsotanSamples] = {
    icon = "data/textures/icons/secondary-collect-xsotan-samples.png",
    name = "Xsotan Samples"%_t,
    description = "The military wants to know more about the Xsotan and needs probes from certain Xsotan breeding sites from the rifts."%_t,

    -- creates an instance that can be used to track the progress of the secondary objective
    makeInstance = function(self, namespaceIn)
        return {
            namespace = namespaceIn or _G,

            collected = 0,
            toCollect = 5,

            preGeneration = function(self, specs) end,
            postGeneration = function(self, specs)
                local numLocations = random():getInt(7, 8) + 1 -- explicit +1 because we remove the first one
                local locations = SecondaryObjectives.getLocations(specs, numLocations)

                -- don't spawn these at the start, unless there is no location but the start (in tests or special cases)
                -- they might attack the player immediately and we'd like to avoid that
                locations[1] = nil

                for _, location in pairs(locations) do
                    local position = MatrixLookUpPosition(random():getDirection(), random():getDirection(), location)
                    local object = SecondaryObjectives.createXsotanSampleBreeder(position)
                    object:setValue("highlight_color", "99ff3030")
                end

                -- listen for cargo change callback
                self.namespace["CollectXsotanSamples_onCargoChanged"] = function(id, delta, good)
                    if not good.tags.secondary_objective_xsotan_sample then return end

                    self.collected = self.collected + delta
                end

                Sector():registerCallback("onCargoChanged", "CollectXsotanSamples_onCargoChanged")
            end,
            update = function(self, timeStep)
                local fulfilled = self.collected >= self.toCollect

                local bulletPoints = {}
                bulletPoints[1] = {
                    text = "(optional) Collect Xsotan Samples\n${count}/${total}"%_T,
                    arguments = {count = math.max(0, math.min(self.collected, self.toCollect)), total = self.toCollect},
                    bulletPoint = true,
                    fulfilled = fulfilled,
                    visible = true
                }

                SecondaryObjectives.updateDescription(bulletPoints)

                if fulfilled and not self.rewarded then
                    self.rewarded = true

                    local relations = 3500
                    local riftResearchData = 7

                    -- assign it to all players
                    for _, player in pairs({Sector():getPlayers()}) do
                        player:invokeFunction("riftmission.lua", "setSecondaryObjectiveReward", relations, riftResearchData)
                    end
                end
            end,
        }
    end
}

local StoryMission1Objective = include ("internal/dlc/rift/story/riftstorymission1-rescue-secondary.lua")
StoryMission1Objective.insertIntoSecondaryObjectives(SecondaryObjectives)

local StoryMission2CombatObjective = include ("internal/dlc/rift/story/riftstorymission2-combat-secondary.lua")
StoryMission2CombatObjective.insertIntoSecondaryObjectives(SecondaryObjectives)

local StoryMission3Objective = include ("internal/dlc/rift/story/riftstorymission3-scout-secondary.lua")
StoryMission3Objective.insertIntoSecondaryObjectives(SecondaryObjectives)

local StoryMission4SalvageObjective = include ("internal/dlc/rift/player/story/riftstorymission4-salvage-secondary.lua")
StoryMission4SalvageObjective.insertIntoSecondaryObjectives(SecondaryObjectives)

local StoryMission5Objective = include ("internal/dlc/rift/story/riftstorymission5-mine-secondary.lua")
StoryMission5Objective.insertIntoSecondaryObjectives(SecondaryObjectives)


function SecondaryObjectives.getRandomObjectiveType()
    local all = {}
    for name, id in pairs(SecondaryObjectives.NonStory) do
        table.insert(all, id)
    end

    return randomEntry(all)
end

return SecondaryObjectives
