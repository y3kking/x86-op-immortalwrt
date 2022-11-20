package.path = package.path .. ";data/scripts/lib/?.lua;data/scripts/entity/merchants/?.lua"
package.path = package.path .. ";data/scripts/lib/?.lua;"

include("randomext")
local Dialog = include("dialogutility")

local ConsumerGoods = include ("consumergoods")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace TurretFactorySupplier
TurretFactorySupplier = include ("seller")

TurretFactorySupplier.customSellPriceFactor = 3.25
TurretFactorySupplier.sellerName = "Turret Factory Supplier"%_t
TurretFactorySupplier.soldGoods = ConsumerGoods.TurretFactory()

local oldInitialize = TurretFactorySupplier.initialize
function TurretFactorySupplier.initialize(...)

    if not _restoring then
        local station = Entity()
    end

    if onClient() then
        local station = Entity()

        if EntityIcon().icon == "" then
            EntityIcon().icon = "data/textures/icons/pixel/trade.png"
            InteractionText(station.index).text = Dialog.generateStationInteractionText(station, random())
        end
    end


    oldInitialize(...)
end

function TurretFactorySupplier.initializationFinished()
    -- use the initilizationFinished() function on the client since in initialize() we may not be able to access Sector scripts on the client
    if onClient() then
        local ok, r = Sector():invokeFunction("radiochatter", "addSpecificLines", Entity().id.string,
        {
            "Get the parts, build the turrets!"%_t,
            "No more travelling across the galaxy for those parts! Get them right here!"%_t,
            "The best prices for the best turrets parts!"%_t,
            "Help us stay in business! Build turrets!"%_t,
        })
    end
end
