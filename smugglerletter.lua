package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"

SectorSpecifics = include ("sectorspecifics")
include ("stringutility")
include ("randomext")
include ("callable")

function initialize()
end

local mailText = [[
Hello,

It looks like you have been betrayed by Bottan and his smugglers, too, and I think we might have a common enemy now.
I'd like to work with you. Meet me at (${x}:${y}).

- A Friend
]]%_t

if onServer() then

    -- this is just to make sure that we have no problems in case the client crashes or something
    -- and for testing ...
    function getUpdateInterval()
        return 18
    end

    function updateServer()
        sendMail(mailText)
    end

else -- if not on server

    function getUpdateInterval()
        return 12
    end

    function updateClient()
        invokeServerFunction("sendMail", mailText)
    end

end

function sendMail(text)
    local player = Player()

    if player:hasScript("story/smugglerretaliation") then return end

    local specs = SectorSpecifics()
    local center = directionalDistance(280)
    local location = specs:findFreeSector(random(), center.x, center.y, 0, 5, Server().seed)

    local mail = Mail()
    mail.sender = "A Friend"%_t
    mail.header = "The Enemy of my Enemy is my Friend"%_t
    mail.id = "Story_Smuggler_Letter"
    mail.text = text % location

    player:addMail(mail)
    player:addScriptOnce("story/smugglerretaliation")
    player:invokeFunction("smugglerretaliation", "setLocation", location.x, location.y)

    terminate()
end
callable(nil, "sendMail")
