-- Спам Remote_Event с зафиксированным buffer-пейлоадом (skill activation, weaponType=Sword)
-- Частота: раз в 0.005 сек

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvent = ReplicatedStorage:WaitForChild("Remote_Event")

local args = {
    buffer.fromstring("\147\022\204\140\145\137\162tp\199\002\147\203@\142\177\030\192\000\000\000\203@K\254\028\000\000\000\000\203\192iL\153@\000\000\000\172activationId\020\168actionId\169\233\149\191\229\137\145/C1\162we\195\172skillUseType\166manual\168position\199\002\147\203@\142\130\v\224\000\000\000\203@LC\231\000\000\000\000\203\192k&Z \000\000\000\166facing\199\002\147\203?\236c\129\192\000\000\000\000\203?\221\137\001\224\000\000\000\170weaponType\165Sword\174basisDirection\199\002\147\203?\215\163l\224\000\000\000\000\203?\237\188\191`\000\000\000")
}

while true do
    RemoteEvent:FireServer(unpack(args))
    task.wait(0.005)
end
