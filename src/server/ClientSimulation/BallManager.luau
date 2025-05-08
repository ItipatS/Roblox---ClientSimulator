local BallManager = {}
local FloatEvent = game.ReplicatedStorage.Remotes:WaitForChild("FloatEvent")


function BallManager:Spawn(ballDatas, playerOrList)
    if typeof(playerOrList) == "Instance" then
        FloatEvent:FireClient(playerOrList, "Spawn", ballDatas)
    else
        FloatEvent:FireAllClients("Spawn", ballDatas)
    end
end

function BallManager:Move(moveDatas, playerOrList)
    if typeof(playerOrList) == "Instance" then
        FloatEvent:FireClient(playerOrList, "Move", moveDatas)
    else
        FloatEvent:FireAllClients("Move", moveDatas)
    end
end

function BallManager:Destroy(ballIDs, playerOrList)
    if typeof(playerOrList) == "Instance" then
        FloatEvent:FireClient(playerOrList, "Destroy", ballIDs)
    else
        FloatEvent:FireAllClients("Destroy", ballIDs)
    end
end

return BallManager
