
package.path = package.path .. ";data/scripts/lib/?.lua"
include ("utility")
include ("faction")
include ("defaultscripts")
include ("randomext")
include ("galaxy")
include ("randomext")
include ("goods")
include ("tooltipmaker")
include ("faction")
include ("player")
include ("stringutility")
include ("merchantutility")
include ("callable")
local SellableInventoryItem = include ("sellableinventoryitem")
local Dialog = include("dialogutility")
local SectorTurretGenerator = include ("sectorturretgenerator")
include("weapontype")
include("weapontypeutility")
local TurretIngredients = include("turretingredients")
local StatChanges = TurretIngredients.StatChanges

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace TurretFactory
TurretFactory = {}
TurretFactory.interactionThreshold = 30000
TurretFactory.creationTax = 0.2

local ConfigurationMode =
{
    InventoryTurret = 1,
    FactoryTurret = 2,
}

local configuredIngredients
local configurationMode
local manufacturingPrice = 0
local data = {}

-- Menu items
local window

local buildTurretsTab = nil
local lines = {}

local selectedBlueprintSelection = nil
local inventoryBlueprintSelection = nil

local makeBlueprintsTab = nil
local turretSelection = nil
local inputSelection = nil
local resultSelection = nil
local makeBlueprintButton = nil
local blueprintPriceLabel = nil
local rerollButton = nil
local blueprintTypeCombo = nil

function TurretFactory.initialize()
    local station = Entity()

    if station.title == "" then
        station.title = "Turret Factory"%_t
    end

    station:registerCallback("onSectorChanged", "onSectorChanged")

    if onServer() then
        TurretFactory.initializeSeed()
    end

    if onClient() then
        TurretFactory.sync()

        if EntityIcon().icon == "" then
            EntityIcon().icon = "data/textures/icons/pixel/turret.png"
            InteractionText().text = Dialog.generateStationInteractionText(station, random())
        end
    end
end

function TurretFactory.onSectorChanged()
    TurretFactory.coords = nil
end

function TurretFactory.interactionPossible(playerIndex, option)
    return CheckFactionInteraction(playerIndex, TurretFactory.interactionThreshold)
end

function TurretFactory.initUI()
    local res = getResolution()
    local size = vec2(780, 580)

    local menu = ScriptUI()
    window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))

    window.caption = "Turret Factory"%_t
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Build Turrets /*window title*/"%_t, 15);

    local tabbedWindow = window:createTabbedWindow(Rect(vec2(10, 10), size - 10))
    buildTurretsTab = tabbedWindow:createTab("", "data/textures/icons/turret-build-mode.png", "Build customized turrets from parts"%_t)
    TurretFactory.initBuildTurretsUI(buildTurretsTab)

    makeBlueprintsTab = tabbedWindow:createTab("", "data/textures/icons/turret-blueprint.png", "Create new blueprints from turrets"%_t)
    TurretFactory.initMakeBlueprintsUI(makeBlueprintsTab)
end

function TurretFactory.initMakeBlueprintsUI(tab)
    tab.onSelectedFunction = "refreshMakeBlueprintsUI"

    local size = tab.size

    local hsplit = UIHorizontalSplitter(Rect(vec2(0, 0), size), 10, 0, 0.3)

    tab:createFrame(hsplit.top);

    turretSelection = tab:createInventorySelection(hsplit.bottom, 12)
    turretSelection.dragFromEnabled = 1
    turretSelection.onClickedFunction = "onTurretInventoryClicked"

    local vsplit = UIVerticalMultiSplitter(hsplit.top, 10, 0, 2)
    vsplit.marginLeft = 150
    vsplit.marginRight = 150

    local rect = vsplit.left
    rect.size = vec2(75, 75)

    inputSelection = tab:createSelection(rect, 1)
    inputSelection.dropIntoEnabled = 1
    inputSelection.entriesSelectable = 0
    inputSelection.dragFromEnabled = 0
    inputSelection.entriesHighlightable = 0
    inputSelection.onReceivedFunction = "onBlueprintInputReceived"

    local rect = vsplit.right
    rect.size = vec2(75, 75)

    resultSelection = tab:createSelection(rect, 1)
    resultSelection.entriesSelectable = 0
    resultSelection.dropIntoEnabled = 0
    resultSelection.dragFromEnabled = 0
    resultSelection.entriesHighlightable = 0


    local rect = vsplit:partition(1)
    rect.size = vec2(50, 50)

    makeBlueprintButton = tab:createButton(rect, "", "onMakeBlueprintPressed")
    makeBlueprintButton.icon = "data/textures/icons/production.png"
    makeBlueprintButton.tooltip = "Convert turret into blueprint (destroys turret)"%_t
    makeBlueprintButton.active = false

    rect.height = 30
    rect.position = rect.position + vec2(0, 50)
    rect.width = 400

    blueprintPriceLabel = tab:createLabel(rect, "", 14)
    blueprintPriceLabel:setCenterAligned()

end

function TurretFactory.onMakeBlueprintPressed(itemIndex)

    if onClient() then
        local item = inputSelection:getItem(ivec2(0, 0))
        if not item then return end

        invokeServerFunction("onMakeBlueprintPressed", item.index)
        return
    end

    local buyer, ship, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendItems)
    if not buyer then return end

    local inventory = buyer:getInventory()
    local turret = inventory:find(itemIndex)
    if turret.itemType ~= InventoryItemType.Turret then
        return
    end

    if turret.averageTech > TurretFactory.getTechLevel() then
        TurretFactory.sendError(player, "Tech level of this factory (%s) is not high enough for this turret."%_t, TurretFactory.getTechLevel())
        return
    end

    if turret.ancient then
        TurretFactory.sendError(player, "This turret can't be turned into a blueprint."%_T)
        return 0
    end

    local price = TurretFactory.getCreateBlueprintPrice(turret)
    local canPay, msg, args = buyer:canPay(price)
    if not canPay then
        TurretFactory.sendError(player, msg, unpack(args))
        return
    end

    local station = Entity()
    local errors = {}
    errors[EntityType.Station] = "You must be docked to the station to create blueprints."%_T
    errors[EntityType.Ship] = "You must be closer to the ship to create blueprints."%_T
    if not CheckPlayerDocked(player, station, errors) then
        return
    end

    local turret = inventory:take(itemIndex)
    if not turret then return end

    buyer:pay(price)
    inventory:addOrDrop(TurretTemplate(turret))

    invokeClientFunction(player, "refreshMakeBlueprintsUI")
end
callable(TurretFactory, "onMakeBlueprintPressed")

function TurretFactory.getCreateBlueprintPrice(turret)
    local item = SellableInventoryItem(turret)
    return 1000 + math.ceil(item.price * 0.3 / 1000) * 1000
end

function TurretFactory.getRerollPrice()
    local x, y = Sector():getCoordinates()
    local level = Balancing_GetTechLevel(x, y)
    level = math.min(50, level)

    local price = 1008 -- lands us at exactly 1mio for level 50

    for i = 2, level do
        price = price * 1.15
    end

    price = price + 50000 -- lands us at exactly 1mio for level 50

    return math.max(1000, round(price / 1000) * 1000)
end

function TurretFactory.onBlueprintInputReceived(selectionIndex, fkx, fky, item, fromIndex, toIndex, tkx, tky)
    TurretFactory.placeBlueprintIngredient(item)
end

function TurretFactory.onTurretInventoryClicked(selectionIndex, kx, ky, item, button)
    TurretFactory.placeBlueprintIngredient(item)
end

function TurretFactory.placeBlueprintIngredient(item)
    item.amount = 1
    makeBlueprintButton.active = false

    inputSelection:clear()
    inputSelection:add(item)

    resultSelection:clear()
    blueprintPriceLabel.caption = ""

    if item.item.itemType == InventoryItemType.Turret then
        local resultItem = InventorySelectionItem()
        resultItem.item = TurretTemplate(item.item)

        resultSelection:add(resultItem)

        makeBlueprintButton.active = true
        blueprintPriceLabel.caption = "¢${money}"%_t % {money = createMonetaryString(TurretFactory.getCreateBlueprintPrice(item.item))}
    end
end

function TurretFactory.initBuildTurretsUI(tab)

    tab.onSelectedFunction = "refreshBuildTurretsUI"
    tab.onShowFunction = "refreshBuildTurretsUI"

    local size = tab.size

    local vsplit = UIVerticalSplitter(Rect(vec2(0, 0), size), 10, 0, 0.4)

    local left = vsplit.left
    local right = vsplit.right

    tab:createFrame(right);

    --- LEFT SIDE
    local hsplit = UIHorizontalSplitter(left, 10, 0, 0.25)
    tab:createFrame(hsplit.top);

    local rect = hsplit.top
    rect.size = vec2(75)
    selectedBlueprintSelection = tab:createSelection(rect, 1)
    selectedBlueprintSelection.dropIntoEnabled = 1
    selectedBlueprintSelection.entriesSelectable = 0
    selectedBlueprintSelection.onReceivedFunction = "onBlueprintReceived"

    local hsplit2 = UIHorizontalSplitter(hsplit.bottom, 10, 0, 0.5)
    hsplit2.topSize = 25

    local comboSplit = UIVerticalSplitter(hsplit2.top, 5, 0, 0.5)
    comboSplit:setRightQuadratic()

    blueprintTypeCombo = tab:createComboBox(comboSplit.left, "onBlueprintTypeSelected")
    blueprintTypeCombo:addEntry("Factory Blueprints"%_t)
    blueprintTypeCombo:addEntry("Inventory Blueprints"%_t)

    rerollButton = tab:createButton(comboSplit.right, "", "onRerollPressed")
    rerollButton.icon = "data/textures/icons/refresh.png"

    inventoryBlueprintSelection = tab:createInventorySelection(hsplit2.bottom, 5)
    inventoryBlueprintSelection.dragFromEnabled = 1
    inventoryBlueprintSelection.onClickedFunction = "onBlueprintSelectionClicked"
    inventoryBlueprintSelection:hide()

    predefinedBlueprintSelection = tab:createInventorySelection(hsplit2.bottom, 5)
    predefinedBlueprintSelection.dragFromEnabled = 1
    predefinedBlueprintSelection.onClickedFunction = "onBlueprintSelectionClicked"

    --- RIGHT SIDE
    local lister = UIVerticalLister(right, 10, 10)

    local vsplit = UIArbitraryVerticalSplitter(lister:placeCenter(vec2(lister.inner.width, 30)), 10, 5, 320, 370)

    tab:createLabel(vsplit:partition(0).lower, "Parts"%_t, 14)
    tab:createLabel(vsplit:partition(1).lower, "Req"%_t, 14)
    tab:createLabel(vsplit:partition(2).lower, "You"%_t, 14)

    for i = 1, 15 do
        local rect = lister:placeCenter(vec2(lister.inner.width, 30))
        local vsplit = UIArbitraryVerticalSplitter(rect, 10, 7, 20, 250, 280, 310, 320, 370)

        local frame = tab:createFrame(rect)

        local i = 0

        local iconRect = vsplit:partition(i); iconRect.size = vec2(iconRect.size.x + 10)

        local icon = tab:createPicture(iconRect, ""); i = i + 1
        local materialLabel = tab:createLabel(vsplit:partition(i).lower, "", 14); i = i + 1
        local plus = tab:createButton(vsplit:partition(i), "+", "onPlus"); i = i + 1
        local minus = tab:createButton(vsplit:partition(i), "-", "onMinus"); i = i + 2
        local requiredLabel = tab:createLabel(vsplit:partition(i).lower, "", 14); i = i + 1
        local youLabel = tab:createLabel(vsplit:partition(i).lower, "", 14); i = i + 1

        icon.isIcon = 1
        minus.textSize = 12
        plus.textSize = 12

        local hide = function(self)
            self.icon:hide()
            self.frame:hide()
            self.material:hide()
            self.plus:hide()
            self.minus:hide()
            self.required:hide()
            self.you:hide()
        end

        local show = function(self)
            self.icon:show()
            self.frame:show()
            self.material:show()
            self.plus:show()
            self.minus:show()
            self.required:show()
            self.you:show()
        end

        local line =  {frame = frame, icon = icon, plus = plus, minus = minus, material = materialLabel, required = requiredLabel, you = youLabel, hide = hide, show = show}
        line:hide()

        table.insert(lines, line)
    end


    local organizer = UIOrganizer(right)
    local rect = organizer:getBottomRect(Rect(vec2(right.width, 60)))

    local splitter= UIVerticalSplitter(rect, 10, 10, 0.9)
    buildButton = tab:createButton(splitter.left, "Build /*Turret Factory Button*/"%_t, "onBuildTurretPressed")
    saveButton = tab:createButton(splitter.right, "", "onTrackIngredientsButtonPressed")
    saveButton.icon = "data/textures/icons/checklist.png"
    saveButton.tooltip = "Track ingredients in mission log"%_t

    priceLabel = tab:createLabel(vec2(right.lower.x, right.upper.y) + vec2(12, -75), "Manufacturing Price: Too Much"%_t, 16)

    TurretFactory.onBlueprintTypeSelected(blueprintTypeCombo, 0)
end

function TurretFactory.initializationFinished()
    -- use the initilizationFinished() function on the client since in initialize() we may not be able to access Sector scripts on the client
    if onClient() then
        local ok, r = Sector():invokeFunction("radiochatter", "addSpecificLines", Entity().id.string,
        {
            "Don't fancy the standard? We build turrets individually according to your specs."%_t,
            "Only turrets built by ethically trained AIs."%_t,
            "Get your turrets directly from the manufacturer!"%_t,
            "No refunds!"%_t,
            "Gunners not included."%_t,
            "Creation of turrets at your own discretion."%_t,
            "We won't take any responsibility for any damages arising from building or destroying turrets, accidental ammunition explosion or plasma implosions."%_t,
        })
    end
end

function TurretFactory.placeBlueprint(item, mode)
    item.amount = 1

    selectedBlueprintSelection:clear()
    selectedBlueprintSelection:add(item)

    configurationMode = mode

    TurretFactory.onBlueprintSelected()
end

function TurretFactory.onBlueprintReceived(selectionIndex, fkx, fky, item, fromIndex, toIndex, tkx, tky)
    local mode = ConfigurationMode.InventoryTurret
    if fromIndex == predefinedBlueprintSelection.selection.index then
        mode = ConfigurationMode.FactoryTurret
    end

    TurretFactory.placeBlueprint(item, mode)
end

function TurretFactory.onBlueprintSelectionClicked(selectionIndex, kx, ky, item, button)
    local mode = ConfigurationMode.InventoryTurret
    if selectionIndex == predefinedBlueprintSelection.selection.index then
        mode = ConfigurationMode.FactoryTurret
    end

    TurretFactory.placeBlueprint(item, mode)
end

function TurretFactory.onBlueprintTypeSelected(combo, selectedIndex)
    predefinedBlueprintSelection.visible = (selectedIndex == 0)
    inventoryBlueprintSelection.visible = (selectedIndex == 1)

    local factionIndex = Faction().index
    rerollButton.active = (selectedIndex == 0) and (factionIndex == Player().index or factionIndex == Player().allianceIndex)

    TurretFactory.refreshRerollButtonTooltip()
end

function TurretFactory.renderUI()
    if buildTurretsTab.isActiveTab then
        local turret

        if configurationMode == ConfigurationMode.InventoryTurret then
            turret = TurretFactory.getUIBlueprint()
        else
            local weaponType = TurretFactory.getUIWeaponType()
            local rarity = TurretFactory.getUIRarity()
            local material = TurretFactory.getMaterial()
            local ingredients = TurretFactory.getUIIngredients()

            turret = TurretFactory.makeTurret(weaponType, rarity, material, ingredients)
        end

        local tooltipType = 1
        if ClientSettings().detailedTurretTooltips then tooltipType = 2 end

        local renderer = TooltipRenderer(makeTurretTooltip(turret, nil, tooltipType))
        renderer:draw(vec2(window.upper.x, window.lower.y) + vec2(20, 10))
    end
end

function TurretFactory.refreshMakeBlueprintsUI()
    local buyer = Galaxy():getPlayerCraftFaction()
    turretSelection:fill(buyer.index, InventoryItemType.Turret)

    blueprintPriceLabel.caption = ""

    inputSelection:clear()
    resultSelection:clear()

    inputSelection:addEmpty()
    resultSelection:addEmpty()
end

function TurretFactory.refreshBuildTurretsUI()
    local buyer = Galaxy():getPlayerCraftFaction()
    inventoryBlueprintSelection:fill(buyer.index, InventoryItemType.TurretTemplate)

    local rarities = {Rarity(RarityType.Common), Rarity(RarityType.Uncommon), Rarity(RarityType.Rare)}
    if buyer:getRelations(Faction().index) >= 80000 then
        table.insert(rarities, Rarity(RarityType.Exceptional))
    end

    local random = Random(Seed(data.seed or ""))

    local first = nil
    predefinedBlueprintSelection:clear()
    for _, weaponType in pairs(TurretFactory.getPossibleWeaponTypes()) do
        for _, rarity in pairs(rarities) do
            local item = InventorySelectionItem()
            item.item = TurretFactory.makeTurretBase(weaponType, rarity, TurretFactory.getMaterial())
            predefinedBlueprintSelection:add(item)

            if not first then first = item end
        end

        if random:test(0.2) then
            local item = InventorySelectionItem()
            item.item = TurretFactory.makeTurretBase(weaponType, Rarity(RarityType.Exotic), TurretFactory.getMaterial())
            predefinedBlueprintSelection:add(item)
        end
    end

    TurretFactory.refreshRerollButtonTooltip()

    selectedBlueprintSelection:clear()
    selectedBlueprintSelection:addEmpty()

    TurretFactory.placeBlueprint(first, ConfigurationMode.FactoryTurret)
end

function TurretFactory.refreshIngredientsUI()
    local ingredients = TurretFactory.getUIIngredients()
    local rarity = TurretFactory.getUIRarity()

    for i, line in pairs(lines) do
        line:hide()
    end

    local ship = Entity(Player().craftIndex)
    if not ship then return end

    for i, ingredient in pairs(ingredients) do
        local line = lines[i]
        line:show()

        local good = goods[ingredient.name]:good()

        local needed = ingredient.amount
        local have = ship:getCargoAmount(good)

        line.icon.picture = good.icon
        line.material.caption = good:displayName(needed)
        line.required.caption = needed
        line.you.caption = have

        line.plus.visible = (configurationMode == ConfigurationMode.FactoryTurret) and (ingredient.amount < ingredient.maximum)
        line.minus.visible = (configurationMode == ConfigurationMode.FactoryTurret) and (ingredient.amount > ingredient.minimum)

        if have < needed then
            line.you.color = ColorRGB(1, 0, 0)
        else
            line.you.color = ColorRGB(1, 1, 1)
        end
    end

    priceLabel.caption = "Manufacturing Cost: ¢${money}"%_t % {money = createMonetaryString(manufacturingPrice)}
end

function TurretFactory.refreshRerollButtonTooltip()
    rerollButton.tooltip = nil
    if rerollButton.active then
        rerollButton.tooltip = "Reinitialize Turret Composition AI: ¢${price}"%_t % {price = createMonetaryString(TurretFactory.getRerollPrice())}
    end
end

function TurretFactory.onPlus(button)
    local ingredients = TurretFactory.getUIIngredients()

    local ingredient
    for i, line in pairs(lines) do
        if button.index == line.plus.index then
            ingredient = ingredients[i]
        end
    end

    ingredient.amount = math.min(ingredient.maximum, ingredient.amount + 1)

    TurretFactory.refreshIngredientsUI()
end

function TurretFactory.onMinus(button)
    local ingredients = TurretFactory.getUIIngredients()

    local ingredient
    for i, line in pairs(lines) do
        if button.index == line.minus.index then
            ingredient = ingredients[i]
        end
    end

    ingredient.amount = math.max(ingredient.minimum, ingredient.amount - 1)

    TurretFactory.refreshIngredientsUI()

end

function TurretFactory.onBlueprintSelected()
    local buyer = Galaxy():getPlayerCraftFaction()

    if configurationMode == ConfigurationMode.InventoryTurret then
        configuredIngredients, manufacturingPrice = TurretFactory.getDuplicatedTurretIngredientsAndTax(TurretFactory.getUIBlueprint(), buyer)
    else
        configuredIngredients, manufacturingPrice = TurretFactory.getNewTurretIngredientsAndTax(TurretFactory.getUIWeaponType(), TurretFactory.getUIRarity(), TurretFactory.getMaterial(), buyer)
    end

    TurretFactory.refreshIngredientsUI()
end

function TurretFactory.onRerollPressed()
    invokeServerFunction("rerollSeed")
end

function TurretFactory.onBuildTurretPressed(button)
    if configurationMode == ConfigurationMode.InventoryTurret then
        local item = selectedBlueprintSelection:getItem(ivec2(0, 0))
        invokeServerFunction("buildTurretDuplicate", item.index)
    else
        invokeServerFunction("buildNewTurret", TurretFactory.getUIWeaponType(), TurretFactory.getUIRarity(), TurretFactory.getUIIngredients())
    end
end

function TurretFactory.onTrackIngredientsButtonPressed(button)
    local item = selectedBlueprintSelection:getItem(ivec2(0, 0))
    local weaponPrefix = item.item.weaponPrefix
    invokeServerFunction("trackIngredientsAsMission", weaponPrefix, TurretFactory.getUIRarity(), TurretFactory.getUIIngredients())
end

function TurretFactory.trackIngredientsAsMission(weaponPrefix, rarity, ingedients)
    local scriptIndex = Player(callingPlayer):addScript("data/scripts/player/missions/turretbuilding.lua")
    Player(callingPlayer):invokeFunction(scriptIndex, "getMission", weaponPrefix, rarity, ingedients)
end
callable(TurretFactory, "trackIngredientsAsMission")

function TurretFactory.onShowWindow()
    window.caption = "Tech ${level} - Turret Factory"%_t % {level = TurretFactory.getTechLevel()}

    if buildTurretsTab.isActiveTab then
        TurretFactory.onBlueprintTypeSelected(blueprintTypeCombo, blueprintTypeCombo.selectedIndex)
        TurretFactory.refreshBuildTurretsUI()
    else
        TurretFactory.refreshMakeBlueprintsUI()
    end
end

function TurretFactory.getUIBlueprint()
    local item = selectedBlueprintSelection:getItem(ivec2(0, 0))

    if item and item.item and item.item.itemType == InventoryItemType.TurretTemplate then
        return item.item
    end
end

function TurretFactory.getUIWeaponType()
    local item = selectedBlueprintSelection:getItem(ivec2(0, 0))

    if item and item.item and item.item.itemType == InventoryItemType.TurretTemplate then
        return WeaponTypes.getTypeOfItem(item.item) or WeaponType.ChainGun
    end

    return WeaponType.ChainGun
end

function TurretFactory.getUIRarity()
    local item = selectedBlueprintSelection:getItem(ivec2(0, 0))

    if item and item.item and item.item.itemType == InventoryItemType.TurretTemplate then
        return item.item.rarity
    end

    return Rarity()
end

function TurretFactory.getUIIngredients()
    return configuredIngredients
end

function TurretFactory.getPossibleWeaponTypes()
    -- remove weapons that aren't dropped in these regions
    local weaponTypes = {}
    local probabilities = Balancing_GetWeaponProbability(data.x, data.y)
    for type, probability in pairs(probabilities) do

        for _, t in pairs(WeaponType) do
            if t == type then
                weaponTypes[t] = t
            end
        end
    end

    return weaponTypes
end

function TurretFactory.getBaseIngredients(weaponType)
    return table.deepcopy(TurretIngredients[weaponType] or TurretIngredients[WeaponType.ChainGun])
end

function TurretFactory.getTechLevel()
    local tech = Balancing_GetTechLevel(data.x, data.y)

    -- tech level for turret factory is at max 50 on purpose
    -- this allows for tech level 51 and 52 turrets only being available as loot
    -- => more hype for boss loot!
    return math.min(tech, 50)
end

function TurretFactory.getMaterial()
    local material

    local materialProbabilities = Balancing_GetTechnologyMaterialProbability(data.x, data.y)

    local highest = 0.0
    for i, probability in pairs(materialProbabilities) do
        if probability > highest then
            highest = probability
            material = Material(i)
        end
    end

    return material
end

function TurretFactory.getNewTurretIngredientsAndTax(weaponType, rarity, material, buyer)
    local turret = TurretFactory.makeTurretBase(weaponType, rarity, material)
    local ingredients, goodsPrice = TurretFactory.calculateTurretIngredients(turret)

    local maxed = table.deepcopy(ingredients)
    for _, ingredient in pairs(maxed) do
        ingredient.amount = ingredient.maximum
    end

    local turret = TurretFactory.makeTurret(weaponType, rarity, material, maxed)
    local itemPrice = ArmedObjectPrice(turret)

    -- remaining price is the difference between the goods price sum and the actual turret sum
    local price = math.max(itemPrice * 0.15, itemPrice - goodsPrice)
    price = math.ceil(price / 1000) * 1000

    local tax = round(price * TurretFactory.creationTax)

    if Faction().index == buyer.index then
        -- simply remove tax from price for easier use
        price = price - tax
        tax = 0
    end

    return ingredients, price, tax
end

function TurretFactory.getDuplicatedTurretIngredientsAndTax(turret, buyer)

    local ingredients, goodsPrice = TurretFactory.calculateTurretIngredients(turret)
    local item = SellableInventoryItem(turret)

    -- remaining price is the difference between the goods price sum and the actual turret sum
    local price = math.max(item.price * 0.15, item.price - goodsPrice)
    price = math.ceil(price / 1000) * 1000

    local tax = round(price * TurretFactory.creationTax)

    if Faction().index == buyer.index then
        -- simply remove tax from price for easier use
        price = price - tax
        tax = 0
    end

    return ingredients, price, tax
end

function TurretFactory.calculateTurretIngredients(turret)

    local item = SellableInventoryItem(turret)
    item.price = item.price * 0.65

    local weaponType = WeaponTypes.getTypeOfItem(turret)
    local ingredients = TurretFactory.getBaseIngredients(weaponType)

    local rarity = turret.rarity

    -- scale required goods with rarity
    for _, ingredient in pairs(ingredients) do
        ingredient.amount = ingredient.amount * math.ceil(1.0 + rarity.value * (ingredient.rarityFactor or 1.0))
    end

    -- calculate the worth of the required goods
    local goodsPrice = 0
    for _, ingredient in pairs(ingredients) do
        goodsPrice = goodsPrice + goods[ingredient.name].price * ingredient.amount
    end

    if item.price < goodsPrice then

        -- turret is cheaper than the goods required to build it
        -- scale down goods
        local factor = item.price / goodsPrice

        for _, ingredient in pairs(ingredients) do
            ingredient.amount = math.max(ingredient.minimum or 0, math.floor(ingredient.amount * factor))
        end

        -- recalculate the worth
        local oldPrice = goodsPrice
        goodsPrice = 0
        for _, ingredient in pairs(ingredients) do
            goodsPrice = goodsPrice + goods[ingredient.name].price * ingredient.amount
        end

        -- scale ingredients back up. now, ingredients with minimum 0 won't be taken into account
        -- those are usually very expensive ingredients that might cause all ingredients to be scaled down to 0 or 1
        for _, ingredient in pairs(ingredients) do
            ingredient.amount = math.max(ingredient.minimum or 0, math.floor(ingredient.amount * oldPrice / goodsPrice))
        end

        goodsPrice = 0
        for _, ingredient in pairs(ingredients) do
            goodsPrice = goodsPrice + goods[ingredient.name].price * ingredient.amount
        end

        -- and, finally, scale back down if necessary
        if item.price < goodsPrice then
            for _, ingredient in pairs(ingredients) do
                ingredient.amount = math.max(ingredient.minimum or 0, math.floor(ingredient.amount * factor))
            end

            -- recalculate the worth
            goodsPrice = 0
            for _, ingredient in pairs(ingredients) do
                goodsPrice = goodsPrice + goods[ingredient.name].price * ingredient.amount
            end
        end
    end

    -- adjust the maximum additional investable goods
    -- get the difference of stats
    for i, ingredient in pairs(ingredients) do

        local object
        local stat

        if ingredient.weaponStat then
            object = turret:getWeapons()
            stat = ingredient.weaponStat
        end

        if ingredient.turretStat then
            object = turret
            stat = ingredient.turretStat
        end

        if object and stat then

            local changeType = ingredient.changeType or StatChanges.Percentage

            local difference
            if changeType == StatChanges.Percentage then
                difference = object[stat]
            elseif changeType == StatChanges.Flat then
                difference = ingredient.investFactor
                ingredient.investFactor = 1.0
            end

            -- print ("changeType: " .. changeType)
            -- print ("stat: " .. stat)
            -- print ("difference: " .. difference)

            local sign = 0
            if difference > 0 then sign = 1
            elseif difference < 0 then sign = -1 end

            local statDelta = math.max(math.abs(difference) / ingredient.investable, 0.01)

            local investable = math.floor(math.abs(difference) / statDelta)
            investable = math.min(investable, ingredient.investable)

            local s = 0
            if type(object[stat]) == "boolean" then
                if object[stat] then
                    s = 1
                else
                    s = 0
                end
            else
                s = math.abs(object[stat])
            end

            local removable = math.floor(s / statDelta)
            removable = math.min(removable, math.floor(ingredient.amount * 0.5))

            ingredient.default = ingredient.amount
            ingredient.minimum = ingredient.amount - removable
            ingredient.maximum = ingredient.amount + investable
            ingredient.statDelta = statDelta * (ingredient.investFactor or 1.0) * sign


            -- print ("delta: " .. ingredient.statDelta)
            -- print ("removable: " .. removable)
            -- print ("investable: " .. investable)
            -- print ("minimum: " .. ingredient.minimum)
            -- print ("maximum: " .. ingredient.maximum)
        else
            ingredient.default = ingredient.amount
            ingredient.minimum = ingredient.amount
            ingredient.maximum = ingredient.amount
            ingredient.statDelta = 0
        end

        if ingredient.amount == 0 and ingredient.investable == 0 then
            ingredients[i] = nil
        end
    end

    --
    local finalIngredients = {}
    for i, ingredient in pairs(ingredients) do
        table.insert(finalIngredients, ingredient)
    end

    return finalIngredients, goodsPrice
end

function TurretFactory.makeTurretBase(weaponType, rarity, material)
    local generator = SectorTurretGenerator(data.seed or "")
    generator.maxVariations = data.maxVariations

    local turret = generator:generate(data.x or 450, data.y or 0, 0, rarity, weaponType, material)
    return turret
end

function TurretFactory.makeTurret(weaponType, rarity, material, ingredients)

    local turret = TurretFactory.makeTurretBase(weaponType, rarity, material)
    local weapons = {turret:getWeapons()}

    turret:clearWeapons()

    for _, weapon in pairs(weapons) do
        -- modify weapons
        for _, ingredient in pairs(ingredients) do
            if ingredient.weaponStat then
                -- add one stat for each additional ingredient
                local additions = math.max(ingredient.minimum - ingredient.default, math.min(ingredient.maximum - ingredient.default, ingredient.amount - ingredient.default))

                local value = weapon[ingredient.weaponStat]
                if type(value) == "boolean" then
                    if value then
                        value = 1
                    else
                        value = 0
                    end
                end

                value = value + ingredient.statDelta * additions
                weapon[ingredient.weaponStat] = value
            end
        end

        turret:addWeapon(weapon)
    end

    for _, ingredient in pairs(ingredients) do
        if ingredient.turretStat then
            -- add one stat for each additional ingredient
            local additions = math.max(ingredient.minimum - ingredient.default, math.min(ingredient.maximum - ingredient.default, ingredient.amount - ingredient.default))

            local value = turret[ingredient.turretStat]
            if type(value) == "boolean" then
                if value then
                    value = 1
                else
                    value = 0
                end
            end

            value = value + ingredient.statDelta * additions
            turret[ingredient.turretStat] = value
        end
    end

    return turret;
end

function TurretFactory.buildTurretDuplicate(inventoryIndex)
    if not CheckFactionInteraction(callingPlayer, TurretFactory.interactionThreshold) then return end

    local buyer, ship, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources)
    if not buyer then return end
    if not inventoryIndex then return end

    local turret = buyer:getInventory():find(inventoryIndex)
    if not turret or turret.itemType ~= InventoryItemType.TurretTemplate then
        TurretFactory.sendError(player, "Turret blueprint not found."%_t)
        return
    end

    if turret.rarity.value >= RarityType.Exceptional then
        local faction = Faction()
        if faction and buyer:getRelations(faction.index) < 80000 then
            TurretFactory.sendError(player, "You need at least 'Excellent' relations to build 'Exceptional' or better turrets."%_t)
            return
        end
    end

    -- can the weapon be built here?
    if turret.averageTech > TurretFactory.getTechLevel() then
        TurretFactory.sendError(player, "Tech level of this factory (%s) is not high enough for this turret."%_t, TurretFactory.getTechLevel())
        return
    end

    -- don't take ingredients from clients blindly, they might want to cheat
    local ingredients, price, tax = TurretFactory.getDuplicatedTurretIngredientsAndTax(turret, buyer)

    -- make sure all required goods are there
    local missing
    for i, ingredient in pairs(ingredients) do
        local good = goods[ingredient.name]:good()
        local amount = ship:getCargoAmount(good)

        if not amount or amount < ingredient.amount then
            missing = goods[ingredient.name]:good()
            break;
        end
    end

    if missing then
        TurretFactory.sendError(player, "You need more %1%."%_t, missing:pluralForm(10))
        return
    end

    local canPay, msg, args = buyer:canPay(price)
    if not canPay then
        TurretFactory.sendError(player, msg, unpack(args))
        return
    end

    local station = Entity()

    local errors = {}
    errors[EntityType.Station] = "You must be docked to the station to build turrets."%_T
    errors[EntityType.Ship] = "You must be closer to the ship to build turrets."%_T
    if not CheckPlayerDocked(player, station, errors) then
        return
    end

    local inventoryTurret = InventoryTurret(turret)
    local inventory = buyer:getInventory()
    if not inventory:hasSlot(inventoryTurret) then
        player:sendChatMessage(Entity(), ChatMessageType.Error, "Your inventory is full (%1%/%2%)."%_T, inventory.occupiedSlots, inventory.maxSlots)
        return
    end

    -- pay
    receiveTransactionTax(station, tax)

    buyer:pay("Paid %1% Credits to build a turret."%_T, price)

    for i, ingredient in pairs(ingredients) do
        local g = goods[ingredient.name]:good()
        ship:removeCargo(g, ingredient.amount)
    end

    inventory:addOrDrop(inventoryTurret)

    invokeClientFunction(player, "refreshIngredientsUI")
end
callable(TurretFactory, "buildTurretDuplicate")


function TurretFactory.buildNewTurret(weaponType, rarity, clientIngredients)
    if not CheckFactionInteraction(callingPlayer, TurretFactory.interactionThreshold) then return end

    if anynils(weaponType, rarity, clientIngredients) then return end
    if not is_type(rarity, "Rarity") then return end
    if not (rarity.value >= RarityType.Common and rarity.value <= RarityType.Exotic) then return end

    local buyer, ship, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources)
    if not buyer then return end

    if rarity.value >= RarityType.Exceptional then
        local faction = Faction()
        if faction and buyer:getRelations(faction.index) < 80000 then
            TurretFactory.sendError(player, "You need at least 'Excellent' relations to build 'Exceptional' or better turrets."%_t)
            return
        end
    end

    local material = TurretFactory.getMaterial()
    local station = Entity()

    -- can the weapon be built in this sector?
    local weaponProbabilities = Balancing_GetWeaponProbability(data.x, data.y)
    if not weaponProbabilities[weaponType] then
        TurretFactory.sendError(player, "This turret cannot be built here."%_t)
        return
    end

    -- don't take ingredients from clients blindly, they might want to cheat
    local ingredients, price, taxAmount = TurretFactory.getNewTurretIngredientsAndTax(weaponType, rarity, material, buyer)

    for i, ingredient in pairs(ingredients) do
        local other = clientIngredients[i]
        if other and other.amount then
            ingredient.amount = other.amount
        end

        if ingredient.minimum and ingredient.amount < ingredient.minimum then return end
        if ingredient.maximum and ingredient.amount > ingredient.maximum then return end
    end

    -- make sure all required goods are there
    local missing
    for i, ingredient in pairs(ingredients) do
        local good = goods[ingredient.name]:good()
        local amount = ship:getCargoAmount(good)

        if not amount or amount < ingredient.amount then
            missing = goods[ingredient.name]:good()
            break;
        end
    end

    if missing then
        TurretFactory.sendError(player, "You need more %1%."%_t, missing:pluralForm(10))
        return
    end

    local canPay, msg, args = buyer:canPay(price)
    if not canPay then
        TurretFactory.sendError(player, msg, unpack(args))
        return
    end

    local errors = {}
    errors[EntityType.Station] = "You must be docked to the station to build turrets."%_T
    errors[EntityType.Ship] = "You must be closer to the ship to build turrets."%_T
    if not CheckPlayerDocked(player, station, errors) then
        return
    end

    local turret = TurretFactory.makeTurret(weaponType, rarity, material, ingredients)
    local inventory = buyer:getInventory()
    if not inventory:hasSlot(turret) then
        player:sendChatMessage(Entity(), ChatMessageType.Error, "Your inventory is full (%1%/%2%)."%_T, inventory.occupiedSlots, inventory.maxSlots)
        return
    end

    -- pay
    receiveTransactionTax(station, taxAmount)

    buyer:pay("Paid %1% Credits to build a turret."%_T, price)

    for i, ingredient in pairs(ingredients) do
        local g = goods[ingredient.name]:good()
        ship:removeCargo(g, ingredient.amount)
    end

    inventory:addOrDrop(InventoryTurret(turret))

    invokeClientFunction(player, "refreshIngredientsUI")
end
callable(TurretFactory, "buildNewTurret")

function TurretFactory.rerollSeed()
    if not CheckFactionInteraction(callingPlayer, TurretFactory.interactionThreshold) then return end

    local buyer, ship, player = getInteractingFaction(callingPlayer, AlliancePrivilege.SpendResources, AlliancePrivilege.ManageStations)
    if not buyer then return end

    local price = TurretFactory.getRerollPrice()
    local canPay, msg, args = buyer:canPay(price)
    if not canPay then
        TurretFactory.sendError(player, msg, unpack(args))
        return
    end

    local faction = Faction()
    if faction.index ~= player.index and faction.index ~= player.allianceIndex then
        TurretFactory.sendError(player, "You can only do that if you own the station."%_T)
        return
    end

    -- pay
    buyer:pay("Paid %1% Credits to reinitialize turret composition AI."%_T, price)

    TurretFactory.initializeSeed()
    data.maxVariations = math.huge -- we don't want any seed collisions like with loot, since that would make a reroll potentially do nothing

    TurretFactory.sync()
end
callable(TurretFactory, "rerollSeed")

function TurretFactory.initializeSeed()
    local uuid = Uuid();
    uuid:toRandom()
    data.seed = uuid.string

    local x, y = Sector():getCoordinates()
    data.x, data.y = x, y
end

function TurretFactory.sync(dataIn)
    if onServer() then
        if callingPlayer then
            invokeClientFunction(Player(callingPlayer), "sync", data)
        else
            broadcastInvokeClientFunction("sync", data)
        end
    else
        if dataIn then
            data = dataIn
            if window then
                TurretFactory.onShowWindow()
            end
        else
            invokeServerFunction("sync")
        end
    end
end
callable(TurretFactory, "sync")

function TurretFactory.secure()
    return data
end

function TurretFactory.restore(values)
    data = values
end

function TurretFactory.buildTurretTest(weaponType, rarity)
    local material = TurretFactory.getMaterial()
    local ingredients = TurretFactory.getNewTurretIngredientsAndTax(weaponType, rarity, material, Faction(Player(callingPlayer).craft.factionIndex))
    TurretFactory.buildNewTurret(weaponType, rarity, ingredients)
end

function TurretFactory.getTurretPriceTest(weaponType, rarity)
    local material = TurretFactory.getMaterial()
    local _, price, _ = TurretFactory.getNewTurretIngredientsAndTax(weaponType, rarity, material, Faction(Player(callingPlayer).craft.factionIndex))
    return price
end

function TurretFactory.getTurretTaxTest(weaponType, rarity)
    local material = TurretFactory.getMaterial()
    local _, _, taxAmount = TurretFactory.getNewTurretIngredientsAndTax(weaponType, rarity, material, Faction(Player(callingPlayer).craft.factionIndex))
    return taxAmount
end


function TurretFactory.sendError(player, msg, ...)
    local station = Entity()
    player:sendChatMessage(station, 1, msg, ...)
end

