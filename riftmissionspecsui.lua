package.path = package.path .. ";data/scripts/?.lua"
package.path = package.path .. ";data/scripts/lib/?.lua"

local Constraints = include("dlc/rift/lib/constraints")
local Extractions = include("dlc/rift/lib/extractions")
local RiftBonuses = include("dlc/rift/lib/riftbonuses")
local SecondaryObjectives = include("dlc/rift/lib/secondaryobjectives")
local EnvironmentalEffectUT = include("dlc/rift/sector/effects/environmentaleffectutility")

include("utility")

local RiftMissionSpecsUI = {}

local function getDescriptionOfLine(bulletin, massFactor, teleportDescription)
    local translatedArguments = {}
    for k, v in pairs(bulletin.formatArguments or {}) do
        if atype(v) == "string" then
            translatedArguments[k] = GetLocalizedString(v)
        else
            translatedArguments[k] = v
        end
    end

    if not bulletin.description then
        return (bulletin.brief or "")%_t % translatedArguments
    end

    local text = ""
    if type(bulletin.description) == "table" then
        text = string.join(bulletin.description, "\n\n", function(i, str) return GetLocalizedString(str) end)
    else
        text = bulletin.description%_t
    end

    if massFactor > 1 then
        text = text .. "\n\n"

        if massFactor == 2 then
            text = text .. "We're overcharging the teleporter to send more mass into the rift. This won't go unnoticed, so you should be prepared for a stronger Xsotan presence."%_t
        else
            text = text .. "We're supercharging the teleporter to send even more mass into the rift. This won't go unnoticed, so you should be prepared for an even stronger Xsotan presence."%_t
        end
    end

    return text % translatedArguments
end

local function getThreatLevel(threatLevel)
    local threat = ThreatLevels[threatLevel]
    return threat.value .. " - " ..  threat.displayName%_t, threat.color
end

local function fill(self, bulletin)
    self:show()

    for _, category in pairs({self.environmentalEffects, self.constraints, self.expeditionDetails}) do
        for _, item in pairs(category) do
            item.picture:hide()
            item.label:hide()
        end
    end

    local hasMassConstraint = false
    local teleportDescription = teleportDescription
    for type, value in pairs(bulletin.arguments[1].constraints) do
        if type == Constraints.Type.MaxMass then
            hasMassConstraint = true
        end
    end
    self.slider.visible = hasMassConstraint

    if bulletin.arguments[1].massFactor and self.slider.visible then
        self.slider.active = false
        self.slider:setValueNoCallback(bulletin.arguments[1].massFactor)
    else
        self.slider.active = true
    end

    self:updateSliderCaption()

    local massFactor = self.slider.value
    if bulletin.arguments[1].massFactor then massFactor = bulletin.arguments[1].massFactor end

    -- only show the "supercharge" etc. text when the slider is visible
    if self.slider.visible then
        self.description.text = getDescriptionOfLine(bulletin, massFactor)
    else
        self.description.text = getDescriptionOfLine(bulletin, 1)
    end

    -- constraints
    if bulletin.arguments and bulletin.arguments[1].constraints then
        local index = 1
        for type, data in pairs(bulletin.arguments[1].constraints) do

            local constraint = Constraints.makeConstraint(type, data)
            local textColor = ColorRGB(0.87, 0.87, 0.87)
            if type == Constraints.Type.MaxMass then
                if self.slider.active and massFactor > 1 then
                    constraint = Constraints.makeConstraint(type, data * massFactor)
                    textColor = ColorRGB(0.4, 0.87, 0.87)
                end
            end

            local iconValue = constraint:getUIValue()
            local tooltipValue = constraint:getTooltipValue()

            local constraintIcon = self.constraints[index]
            constraintIcon.picture.picture = constraint.icon
            constraintIcon.picture.isIcon = true
            constraintIcon.picture:show()

            local tooltip
            if tooltipValue then
                tooltip = constraint.name%_t .. string.format(": %s"%_t, tooltipValue)
            else
                tooltip = constraint.name%_t
            end

            if constraint.description then
                -- not all constraints need extra explanation
                tooltip = tooltip .. "\n" .. constraint.description
            end

            if constraint.getAdditionalTooltipLine then
                local extraLine = constraint:getAdditionalTooltipLine()
                if extraLine then
                    tooltip = tooltip .. "\n\n" .. extraLine
                end
            end

            constraintIcon.picture.tooltip = tooltip

            if iconValue then
                constraintIcon.label.caption = iconValue
                constraintIcon.label.color = textColor
                constraintIcon.label:show()
            else
                constraintIcon.label.caption = ""
                constraintIcon.label:hide()
            end

            index = index + 1
            if index > 8 then
                eprint("Too many constraints to show in rift research UI!")
                break
            end
        end

        if index == 1 then
            -- fill in a blank sign
            local constraintIcon = self.constraints[1]
            constraintIcon.picture.picture = "data/textures/icons/minus.png"
            constraintIcon.picture.isIcon = true
            constraintIcon.picture:show()
            constraintIcon.picture.tooltip = nil
        end
    end

    -- environmental effects
    local index = 1
    if bulletin.arguments and bulletin.arguments[1].bonuses then
        for _, bonusType in pairs(bulletin.arguments[1].bonuses) do
            local bonus = RiftBonuses[bonusType]
            local icon = self.environmentalEffects[index]
            icon.picture.picture = bonus.icon
            icon.picture.isIcon = true
            icon.picture.color = ColorRGB(1, 1, 0.4)
            icon.picture:show()

            icon.label:hide()

            icon.picture.tooltip = bonus.name .. "\n\n" .. bonus.description

            index = index + 1
        end
    end

    if massFactor > 1 then
        local icon = self.environmentalEffects[index]
        icon.picture.picture = "data/textures/icons/xsotan.png"
        icon.picture.isIcon = true
        icon.picture.color = ColorRGB(0.88, 0.5, 0.13)
        icon.picture:show()

        icon.label.caption = string.format("+%s", toRomanLiterals(massFactor - 1))
        icon.label.color = ColorRGB(0.88, 0.15, 0.15)
        icon.label:show()

        icon.picture.tooltip = "Xsotan Strength +${n}"%_t % {n = massFactor - 1}
            .. "\n\n"
            .. "Overcharging the teleporter will create subspace waves that won't go unnoticed by the Xsotan swarm."%_t

        index = index + 1
    end

    if bulletin.arguments and bulletin.arguments[1].environmentalEffects then
        local sorted = {}
        for effect, strength in pairs(bulletin.arguments[1].environmentalEffects) do
            local priority = EnvironmentalEffectUT.data[effect].sortPriority
            table.insert(sorted, {type = effect, strength = strength, priority = priority})
        end

        table.sort(sorted, function(a, b) return a.priority < b.priority end)

        for _, effect in pairs(sorted) do

            -- skip environmental effects that do not affect player
            if EnvironmentalEffectUT.data[effect.type].hidden then goto continue end

            local color = ColorHSV(lerp(effect.strength, 1, 3, 60, 0), 0.8, 1)

            local icon = self.environmentalEffects[index]
            icon.picture.picture = EnvironmentalEffectUT.data[effect.type].icon
            icon.picture.isIcon = true
            icon.picture.color = EnvironmentalEffectUT.data[effect.type].color
            icon.picture:show()

            local displayStrength = EnvironmentalEffectUT.getDisplayedIntensity(effect.type, effect.strength)
            icon.label.caption = EnvironmentalEffectUT.getDisplayedLevel(effect.type, displayStrength)
            icon.label.color = color
            icon.label:show()

            local x, y = Sector():getCoordinates()
            local args = EnvironmentalEffectUT.getFormatArguments(effect.type, effect.strength, x, y)
            local tooltip = EnvironmentalEffectUT.data[effect.type].name%_t .. string.format(" - Level: %d"%_t, displayStrength) .. "\n"
            tooltip = tooltip .. EnvironmentalEffectUT.data[effect.type].description%_t % args
            icon.picture.tooltip = tooltip

            index = index + 1
            if index > 8 then
                eprint("Too many environmental effects to show in rift research UI!")
                break
            end

            ::continue::
        end
    end

    -- expedition details
    local index = 1

    -- rift depth
    if bulletin.riftDepth then
        local riftDepthIcon = self.expeditionDetails[index]
        index = index + 1

        riftDepthIcon.picture.picture = "data/textures/icons/wormhole.png"
        riftDepthIcon.picture.isIcon = true
        riftDepthIcon.picture.color = ColorRGB(0.8, 0.8, 0.8)
        riftDepthIcon.picture:show()

        riftDepthIcon.label.caption = bulletin.riftDepth
        riftDepthIcon.label:show()

        local tooltip = "Rift Depth: The deeper into the rift, the more Xsotan you will encounter."%_t
        riftDepthIcon.picture.tooltip = tooltip
    end

    -- extraction
    if bulletin.arguments and bulletin.arguments[1].extraction then
        local extractionIcon = self.expeditionDetails[index]
        index = index + 1

        local extraction = Extractions.makeExtraction(bulletin.arguments[1].extraction.type, bulletin.arguments[1].extraction.data)
        extractionIcon.picture.picture = extraction.icon
        extractionIcon.picture.isIcon = true
        extractionIcon.picture.color = ColorRGB(0.8, 0.8, 0.8)
        extractionIcon.picture:show()

        extractionIcon.label.caption = ""
        extractionIcon.label:hide()

        local tooltip = "Your way to leave the rift:"%_t .. "\n" .. extraction.description
        extractionIcon.picture.tooltip = tooltip
    end

    -- secondary objective
    if bulletin.arguments and bulletin.arguments[1].secondary and not bulletin.hideSecondaryObjective then
        local icon = self.expeditionDetails[index]
        index = index + 1

        local secondary = SecondaryObjectives[bulletin.arguments[1].secondary]
        icon.picture.picture = secondary.icon
        icon.picture.isIcon = true
        icon.picture.color = bulletin.arguments[1].secondaryColor or ColorRGB(0.8, 0.8, 0.8)
        icon.picture:show()
        icon.label:hide()

        icon.picture.tooltip = "Secondary Objective: "%_t .. secondary.name .. "\n\n" .. secondary.description
    end
end

local function fillLine(self, bulletin)
    self.missionIcon.picture = bulletin.icon or "data/textures/icons/basic-mission-marker.png"
    self.missionIcon.color = bulletin.iconColor or ColorRGB(0.85, 0.85, 0.85)
    self.brief.caption = bulletin.brief%_t % (bulletin.formatArguments or {})
    self.brief.color = bulletin.iconColor or ColorRGB(0.85, 0.85, 0.85)
    self.riftDepthLabel.caption = bulletin.riftDepth

    local threatLevelText, threatLevelColor = getThreatLevel(bulletin.threatLevel)
    threatLevelColor = Color(threatLevelColor)
    threatLevelColor.a = 0.7

    self.threatLevelLabel.caption = threatLevelText
    self.threatLevelLabel.outline = true
    local left = self.threatLevelFrame.lower.x
    local right = self.threatLevelFrame.upper.x
    local x = lerp(bulletin.threatLevel, ThreatLevel.VeryLow - 1, ThreatLevel.Impossible, left, right)
    self.threatLevelRect.upper = vec2(x, self.threatLevelRect.upper.y)
    self.threatLevelRect.color = threatLevelColor

    if bulletin.arguments and bulletin.arguments[1].bonuses and bulletin.arguments[1].bonuses[1] then
        local bonus = RiftBonuses[bulletin.arguments[1].bonuses[1]]
        self.bonusIcon:show()
        self.bonusIcon.picture = bonus.icon
        self.bonusIcon.tooltip = bonus.name
        self.bonusIcon.color = ColorRGB(1, 1, 0.4)
    else
        self.bonusIcon:hide()
    end

    if bulletin.storyBulletin then
        self.bonusIcon:show()
        self.bonusIcon.picture = "data/textures/icons/science.png"
        self.bonusIcon.tooltip = nil
        self.bonusIcon.color = bulletin.iconColor or ColorRGB(0.9, 0.9, 0.9)
    end

    for _, icon in pairs(self.rewardIcons) do
        icon:hide()
    end

    local j = 1
    if bulletin.rewardSpecs and bulletin.arguments[1].givesReward then
        local tooltip = ""
        local rarityLeft = Rarity(bulletin.rewardSpecs.l[1])
        local rarityLeft2 = Rarity(bulletin.rewardSpecs.l[2]) or rarityLeft
        local rarityRight = Rarity(bulletin.rewardSpecs.r[1])
        local rarityRight2 = Rarity(bulletin.rewardSpecs.r[2]) or rarityRight

        local left = plural_t("Subsystem (${rarity})", "${i} Subsystems (${rarity}, ${rarity2})", #bulletin.rewardSpecs.l) % {rarity = rarityLeft.name, rarity2 = rarityLeft2.name}
        local right = plural_t("Subsystem (${rarity})", "${i} Subsystems (${rarity}, ${rarity2})", #bulletin.rewardSpecs.r) % {rarity = rarityRight.name, rarity2 = rarityRight2.name}

        tooltip = tooltip .. "Choice between\n ${a}\n- OR -\n ${b}"%_t % {a = left, b = right}

        if bulletin.rewardSpecs.turret then
            local rarity = Rarity(bulletin.rewardSpecs.l[1] - 1)
            tooltip = tooltip .. "\n\n" .. "PLUS:\n Turret (${rarity})"%_t % {rarity = rarity.name}
        end

        local rect = copy(self.rewardIconRect)
        rect.lower = rect.lower + self.container.lower
        rect.upper = rect.upper + self.container.lower
        local hlist = UIHorizontalLister(rect, 3, -2)

        for k, rarityType in pairs(bulletin.rewardSpecs.l) do
            if k == #bulletin.rewardSpecs.l then hlist.padding = -3 end

            local icon = self.rewardIcons[j]; j = j + 1
            icon.picture = "data/textures/icons/circuitry-small.png"
            icon.color = Rarity(rarityType).color
            icon.tooltip = tooltip
            local rect = hlist:nextQuadraticRect(); rect.size = vec2(32)
            icon.rect = rect
            icon:show()
        end

        hlist.padding = -3
        local separator = self.rewardIcons[5]
        separator.picture = "data/textures/icons/separator.png"
        separator.color = ColorRGB(1, 1, 1)
        separator.rect = hlist:nextQuadraticRect()
        separator:show()

        for k, rarityType in pairs(bulletin.rewardSpecs.r) do
            hlist.padding = 3
            if k == #bulletin.rewardSpecs.r then hlist.padding = 15 end

            local icon = self.rewardIcons[j]; j = j + 1
            icon.picture = "data/textures/icons/circuitry-small.png"
            icon.color = Rarity(rarityType).color
            icon.tooltip = tooltip
            local rect = hlist:nextQuadraticRect(); rect.size = vec2(32)
            icon.rect = rect
            icon:show()
        end

        if bulletin.rewardSpecs.turret then
            local rarity = Rarity(bulletin.rewardSpecs.l[1] - 1)
            local icon = self.rewardIcons[6]
            icon.picture = "data/textures/icons/turret-small.png"
            icon.color = rarity.color
            icon.tooltip = tooltip
            local rect = hlist:nextQuadraticRect(); rect.size = vec2(32)
            icon.rect = rect
            icon:show()
        end
    end

end

function RiftMissionSpecsUI.buildLine(container, rect)
    local line = {container = container}

    -- hand picked positions so that we can center labels under respective heading
    local avsplit = UIArbitraryVerticalSplitter(rect, 15, 5, 28, 360, 410, rect.width - 300, rect.width - 160)

    line.frame = container:createFrame(rect)

    local iconRect = avsplit:partition(0)
    iconRect.size = vec2(32)

    local selectedColor = ColorRGB(0.5, 0.5, 0.5)
    local cornerIconRect = Rect(rect.topRight - vec2(10, 0), rect.topRight + vec2(0, 10))
    line.cornerIcon = container:createPicture(cornerIconRect, "data/textures/ui/corner-topright.png")
    line.cornerIcon.color = selectedColor
    line.cornerIcon.flipped = true
    line.topLine = container:createLine(rect.topLeft - vec2(0, 1), rect.topRight - vec2(0, 1))
    line.topLine.color = selectedColor
    line.bottomLine = container:createLine(rect.bottomLeft + vec2(0, 1), rect.bottomRight + vec2(0, 1))
    line.bottomLine.color = selectedColor

    line.cornerIcon:hide()
    line.topLine:hide()
    line.bottomLine:hide()

    line.missionIcon = container:createPicture(iconRect, "")
    line.missionIcon.isIcon = true
    line.missionIcon.color = ColorRGB(0.85, 0.85, 0.85)

    local briefRect = avsplit:partition(1)

    line.brief = container:createLabel(briefRect.lower, "", 14);
    line.brief.width = 350 -- this is where threat level partition starts => cut text off here
    line.brief.shortenText = true

    local hlist = UIHorizontalLister(avsplit:partition(2), 0, -6)

    local bonusRect = hlist:nextQuadraticRect()
    line.bonusIcon = container:createPicture(bonusRect, "");
    line.bonusIcon.isIcon = true
    line.bonusIcon:hide()

    local threatRect = avsplit:partition(3); threatRect.upper = threatRect.upper + vec2(30, 0)
    line.threatLevelLabel = container:createLabel(threatRect, "", 14)
    line.threatLevelLabel:setLeftAligned()

    threatRect.lower = threatRect.lower - vec2(10, 0)
    line.threatLevelFrame = container:createFrame(threatRect)
    line.threatLevelRect = container:createRect(threatRect, ColorARGB(0.5, 1, 1, 0.1))
    line.riftDepthLabel = container:createLabel(avsplit:partition(4), "", 14)
    line.riftDepthLabel:setCenterAligned()

    -- rewards
    line.rewardIconRect = avsplit:partition(5)
    local hlist = UIHorizontalLister(line.rewardIconRect, 5, -2)
    line.rewardIcons = {}

    -- upgrades
    for i = 1, 5 do
        local rect = hlist:nextQuadraticRect(); rect.size = vec2(32)
        local icon = container:createPicture(rect, "")
        icon.isIcon = true
        icon:hide()

        table.insert(line.rewardIcons, icon)
    end

    -- turrets
    local rect = hlist:nextQuadraticRect(); rect.size = vec2(32)
    local icon = container:createPicture(rect, "")
    icon.isIcon = true
    icon:hide()
    table.insert(line.rewardIcons, icon)

    line.hide = function(self)
        self.missionIcon:hide()
        self.brief:hide()
        self.threatLevelLabel:hide()
        self.threatLevelFrame:hide()
        self.threatLevelRect:hide()
        self.riftDepthLabel:hide()

        for _, icon in pairs(self.rewardIcons) do
            icon:hide()
        end
    end

    line.show = function(self)
        self.frame:show()
        self.missionIcon:show()
        self.brief:show()
        self.threatLevelLabel:show()
        self.threatLevelFrame:show()
        self.threatLevelRect:show()
        self.riftDepthLabel:show()

        for _, icon in pairs(self.rewardIcons) do
            icon:show()
        end
    end

    line.setAcceptedMission = function(self, selected)
        self.cornerIcon.visible = selected
        self.topLine.visible = selected
        self.bottomLine.visible = selected
    end

    line.fill = fillLine

    return line
end

function RiftMissionSpecsUI.build(container, rect, massSliderChangeCallback)
    local ui = {}

    container:createLine(rect.topLeft, rect.topRight)

    local vsplitDescription = UIVerticalSplitter(rect, 10, 0, 0.6)

    -- free-form textfield to be filled by prosa description
    ui.description = container:createTextField(vsplitDescription.left, "")
    ui.description.fontSize = 14

    -- divider line between description and mission specifics
    ui.dividerLine = container:createLine(vec2(vsplitDescription.right.lower.x - 5, vsplitDescription.right.lower.y + 15),  vec2(vsplitDescription.right.lower.x - 5, vsplitDescription.right.upper.y - 25))
    ui.dividerLine:hide()

    -- specifics - these vary from mission to mission => we can't pin them down here
    local hsplit = UIHorizontalSplitter(vsplitDescription.right, 10, 10, 0.5)
    hsplit.bottomSize = 40

    ui.labels = {}
    local lister = UIVerticalLister(hsplit.top, 7, 10)

    -- constraints
    local vsplitConstraints = UIVerticalSplitter(lister:nextRect(20), 10, 0, 0.4)

    local heading = container:createLabel(vsplitConstraints.left, "TELEPORT:"%_t, 15)
    heading:setLeftAligned()
    table.insert(ui.labels, heading)

    ui.slider = container:createSlider(vsplitConstraints.right, 1, 3, 2, "", massSliderChangeCallback or "")
    ui.slider.showValue = false
    ui.slider.description = "Normal Mass"%_t

    local constraints = {}
    local heading = container:createLabel(lister:nextRect(20), "CONSTRAINTS:"%_t, 15)
    table.insert(ui.labels, heading)

    local hlister = UIHorizontalLister(lister:nextRect(30), 10, 0, 4)

    for i = 1, 8 do
        local constraintsRect = hlister:nextQuadraticRect(); constraintsRect.size = vec2(32)
        local icon = container:createPicture(constraintsRect, "")
        icon.isIcon = true
        icon.color = ColorRGB(0.8, 0.8, 0.8)
        icon:hide()

        local valueLabel = container:createLabel(constraintsRect, "", 12)
        valueLabel:setBottomRightAligned()
        valueLabel.color = ColorRGB(1, 1, 1)
        valueLabel.bold = true
        valueLabel.outline = true
        valueLabel.tooltip = tooltip
        valueLabel:hide()

        table.insert(constraints, {picture = icon, label = valueLabel})
    end

    ui.constraints = constraints
    lister:nextRect(0) -- empty line

    -- environmental effects
    local environmentalEffects = {}
    table.insert(ui.labels, container:createLabel(lister:nextRect(20), "EXPECTED ENVIRONMENT:"%_t, 15))

    local hlister = UIHorizontalLister(lister:nextRect(30), 10, 0, 4)

    for i = 1, 8 do
        local environmentalEffectRect = hlister:nextQuadraticRect(); environmentalEffectRect.size = vec2(32)
        local icon = container:createPicture(environmentalEffectRect, "")
        icon.isIcon = true
        icon:hide()

        local intensityLabel = container:createLabel(environmentalEffectRect, "", 12)
        intensityLabel:setBottomRightAligned()
        intensityLabel.bold = true
        intensityLabel.outline = true
        intensityLabel:hide()

        table.insert(environmentalEffects, {picture = icon, label = intensityLabel})
    end

    ui.environmentalEffects = environmentalEffects
    lister:nextRect(0) -- empty line

    -- expedition details
    local expeditionDetails = {}
    table.insert(ui.labels, container:createLabel(lister:nextRect(20), "EXPEDITION DETAILS:"%_t, 15))

    local hlister = UIHorizontalLister(lister:nextRect(30), 10, 0, 4)

    for i = 1, 8 do
        local rect = hlister:nextQuadraticRect(); rect.size = vec2(32)
        local icon = container:createPicture(rect, "")
        icon.isIcon = true
        icon.color = ColorRGB(0.8, 0.8, 0.8)
        icon:hide()

        local valueLabel = container:createLabel(rect, "", 12)
        valueLabel:setBottomRightAligned()
        valueLabel.bold = true
        valueLabel.outline = true
        valueLabel:hide()

        table.insert(expeditionDetails, {picture = icon, label = valueLabel})
    end

    ui.expeditionDetails = expeditionDetails

    ui.hide = function(self)
        self.slider:hide()
        self.description:hide()
        self.dividerLine:hide()

        for _, category in pairs({self.environmentalEffects, self.constraints, self.expeditionDetails}) do
            for _, item in pairs(category) do
                item.picture:hide()
                item.label:hide()
            end
        end

        for _, label in pairs(self.labels) do
            label:hide()
        end
    end

    ui.show = function(self)
        self.slider:show()
        self.description:show()
        self.dividerLine:show()

        for _, category in pairs({self.environmentalEffects, self.constraints, self.expeditionDetails}) do
            for _, item in pairs(category) do
                item.picture:show()
                item.label:show()
            end
        end

        for _, label in pairs(self.labels) do
            label:show()
        end
    end

    ui.updateSliderCaption = function(self)
        local slider = self.slider
        if slider.value == 1 then
            slider.caption = ""
            slider.description = "Normal Mass"%_t
        elseif slider.value == 2 then
            slider.caption = "Teleporter Overcharge"%_t
            slider.description = "+100% Mass"%_t
        else
            slider.caption = "Teleporter Supercharge"%_t
            slider.description = "+200% Mass"%_t
        end
    end

    ui.fill = fill

    ui.acceptRect = hsplit.bottom

    return ui
end

return RiftMissionSpecsUI
