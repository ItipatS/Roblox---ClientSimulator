local VoxelDust = {}
-- Services
local Players = game:GetService("Players")
local BallManager = require(script.Parent.BallManager)
local FireFly = require(script.Parent.Firefly)
local AskDustState = game.ReplicatedStorage.Remotes.AskDustState
local DustDragEvent = game.ReplicatedStorage.Remotes.DustDragEvent
-- Settings
local DUST_SPEED = 2 -- studs per second (small drifting)
local MAX_DUST = 2000
local SPAWN_AREA_SIZE = 200 -- +/- 100 studs XZ
local CEILING_HEIGHT = 15 -- max height
-- Main Table
local draggingDusts = {} -- [DustID] = player
local activeDusts = {}
local pendingSpawnDusts = {} -- list of spawn data
local pendingDestroyDusts = {} -- list of dustID
local dustCounter = 0
local activeDustCount = 0
local MasterClient = nil

local swarmAgents = {}
for i = 1, 100 do
    table.insert(swarmAgents, {
        Position = Vector3.new(math.random(-50,50), math.random(5,20), math.random(-50,50)),
        Velocity = Vector3.new(math.random()-0.5, math.random()-0.5, math.random()-0.5).Unit * 10
    })
end
-- Random Helper
local function randomDrift()
    return Vector3.new(
        math.random() * 1 - .5,
        math.random() * 0.25,
        math.random() * 1 - .5
    ).Unit
end

-- Spawning Dust
function VoxelDust:SpawnDust(position)
    if activeDustCount >= MAX_DUST then return end

    dustCounter += 1
    activeDustCount += 1

    local drift = randomDrift()
    local timeoffset = math.random()
    local rarity = FireFly:chooseRarity()
    local color =  FireFly:chooseColorFromPool(rarity)
    local isRainbow = (rarity == "Legendary")
    local randomSeed = math.random(1, 99999999)

    activeDusts[dustCounter] = {
        DustID = dustCounter,
        Position = position,
        Direction = drift,
        Speed = DUST_SPEED,
        LastSentPosition = position,
        TimeOffset = timeoffset,
        Rarity = rarity,
        Color = color,
        Seed = randomSeed
    }

    table.insert(pendingSpawnDusts, {
        DustID = dustCounter,
        Position = position,
        Direction = drift,
        Speed = DUST_SPEED,
        TimeOffset = timeoffset,
        Color = color, -- only send color, not Rarity
        Rainbow = isRainbow,
        Seed = randomSeed
    })
end

function VoxelDust:DestroyDust(dustID)
    activeDustCount -= 1
    table.insert(pendingDestroyDusts, dustID)
end

function VoxelDust:DestroyPending()
    if #pendingDestroyDusts > 0 then
        BallManager:Destroy(pendingDestroyDusts)
        table.clear(pendingDestroyDusts)
    end
end

-- Initialize (spawn random dusts)
function VoxelDust:InitializeDustField()
    if activeDustCount >= MAX_DUST then return end
    for _ = 1, MAX_DUST do
        local randomPos = Vector3.new(
            math.random(-SPAWN_AREA_SIZE/2, SPAWN_AREA_SIZE/2),
            math.random(0, CEILING_HEIGHT),
            math.random(-SPAWN_AREA_SIZE/2, SPAWN_AREA_SIZE/2)
        )
        self:SpawnDust(randomPos)
    end
    if #pendingSpawnDusts > 0 then
        BallManager:Spawn(pendingSpawnDusts)
        table.clear(pendingSpawnDusts)
    end
end

Players.PlayerAdded:Connect(function(player)
    task.delay(1, function()
        if not MasterClient then
            MasterClient = player
            VoxelDust:InitializeDustField()
        else
            AskDustState:FireClient(MasterClient,"RequestDustState" ,player.UserId)
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local playerlist = Players:GetPlayers()
    if player == MasterClient then
        MasterClient = playerlist[math.random(1, #playerlist)] or nil
        -- Optional: reassign MasterClient to someone else if needed
    end
end)

AskDustState.OnServerEvent:Connect(function(masterPlayer, command, targetUserId, dustData)
    if command == "SendDustState" then
        local targetPlayer = Players:GetPlayerByUserId(targetUserId)
        if targetPlayer then
            AskDustState:FireClient(targetPlayer, "ReceiveDustState", dustData)
        end
    end
end)

DustDragEvent.OnServerEvent:Connect(function(player, command, dustID, mousePos)
    if command == "StartDrag" then
        -- Validate dust exists
        if activeDusts[dustID] then
            draggingDusts[dustID] = player
            -- Broadcast to all players
            DustDragEvent:FireAllClients("StartDrag", dustID, player.UserId)
        end

    elseif command == "StopDrag" then
        if draggingDusts[dustID] == player then
            draggingDusts[dustID] = nil
            DustDragEvent:FireAllClients("StopDrag", dustID)
        end
    elseif command == "UpdateDrag" then
        if draggingDusts[dustID] == player then
            -- Accept position update from rightful player
            DustDragEvent:FireAllClients("UpdateDrag", dustID, mousePos)
        end
    end
end)

return VoxelDust
