local DustController = {}
-- BallController (client)
local FloatEvent = game.ReplicatedStorage.Remotes:WaitForChild("FloatEvent")
local AskDustState = game.ReplicatedStorage.Remotes:WaitForChild("AskDustState")
local DustDragEvent = game.ReplicatedStorage.Remotes:WaitForChild("DustDragEvent")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local Mouse = Players.LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera
local Log = LocalPlayer.PlayerGui:WaitForChild("Interface"):WaitForChild("Log")
local DebugHelper = require(script.Parent.Parent.Utility.DebugHelper)
local dusts = {}
local dustPool = {}
local cachedPlayerPositions = {}

local draggingDustID = nil
local targetDust = nil
local accumulatedTime = 0
local logTime = 0

local SIMULATION_INTERVAL = 0.05 -- update logic every 0.05 sec
local WARP_AREA_SIZE = 100
local PICK_RADIUS = 10
local DUST_SIZE = Vector3.new(0.3, 0.3, 0.3)
local WOBBLE_INTENSITY = 0.5 -- how much wobble
local PLAYER_PUSH_RADIUS = 5 -- how far player pushes dust
local PLAYER_PUSH_FORCE = 10 -- how strong push


--Create Raycast
-- LocalScript
local rayModel = Instance.new("Model")
rayModel.Name = "HoverRay"
rayModel.Parent = workspace

local from = Instance.new("Part")
from.Anchored = true
from.CanCollide = false
from.Size = Vector3.new(0.1, 0.1, 0.1)
from.Transparency = 1
from.Name = "From"
from.Parent = rayModel

local to = Instance.new("Part")
to.Anchored = true
to.CanCollide = false
to.Size = Vector3.new(0.1, 0.1, 0.1)
to.Transparency = 1
to.Name = "To"
to.Parent = rayModel

local a1 = Instance.new("Attachment", from)
local a2 = Instance.new("Attachment", to)

local beam = Instance.new("Beam")
beam.Attachment0 = a1
beam.Attachment1 = a2
beam.FaceCamera = true
beam.Width0 = 0.1
beam.Width1 = 0.1
beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 0))
beam.Parent = from

rayModel:MoveTo(Vector3.new(0, -100, 0)) -- hide initially


local function getDustFromPool()
    if #dustPool > 0 then
        local dust = table.remove(dustPool)
        return dust
    else
        local dust = Instance.new("Part")
        dust.Shape = Enum.PartType.Ball
        dust.Size = DUST_SIZE
        dust.Anchored = true
        dust.CanCollide = false
        dust.CastShadow = false
        dust.Material = Enum.Material.Neon
        return dust
    end
end

local function wrapAxis(value)
    local range = WARP_AREA_SIZE * 2
    if value > WARP_AREA_SIZE then
        return value - range, true
    elseif value < -WARP_AREA_SIZE then
        return value + range, true
    else
        return value, false
    end
end

FloatEvent.OnClientEvent:Connect(function(command, data)
    if command == "Spawn" then
        for _, info in ipairs(data) do
            local randomColor = math.random(1, #info.Color)
            local dust = getDustFromPool()
            dust.Position = info.Position
            dust.Color = info.Color[randomColor] or Color3.fromRGB(255, 255, 255)
            dust.Parent = workspace.Dusts
            dusts[info.DustID] = {
                Part = dust,
                Position = info.Position,
                Direction = info.Direction.Unit,
                Speed = info.Speed or 2,
                TimeOffset = info.TimeOffset or 0,
                Rainbow = info.Rainbow or false,
                Seed = info.Seed or 12345, -- 🔥 Store seed
                Random = Random.new(info.Seed or 12345),
                GlowTimer = 0,
                GlowOffet = 0,
                GlowState = true,
                IsFleeing = false,
                FleeTimer = 0,
                ColorSequence = info.Color,
                Color = info.Color[randomColor] or Color3.fromRGB(255, 255, 255),
                CurrentColorIndex = randomColor,
                ColorTimer = 0,
                ColorBlendDuration = 2
            }
        end
    elseif command == "Destroy" then
        for _, dustID in ipairs(data) do
            local dustData = dusts[dustID]
            if dustData and dustData.Part then
                dustData.Part.Parent = nil
                table.insert(dustPool, dustData.Part)
            end
            dusts[dustID] = nil
        end
    elseif command == "Move" then
        for _, moveinfo in ipairs(data) do
            local dustData = dusts[moveinfo.DustID]
            if dustData then
                dustData.LastPosition = dustData.Part.Position
                dustData.TargetPosition = moveinfo.Position
                dustData.Timer = 0
            end
        end
    end
end)

local mouseUpdateTimer = 0

function DustController:Update(dt)
    accumulatedTime += dt
    mouseUpdateTimer += dt

    if draggingDustID and mouseUpdateTimer > 0.05 then -- send every 0.05 sec
        mouseUpdateTimer = 0
        logTime = 0
        local mousePos = UserInputService:GetMouseLocation()
        local ray = Camera:ScreenPointToRay(mousePos.X, mousePos.Y)
        local fixedDistance = PICK_RADIUS
        local mouseWorldPos = ray.Origin + ray.Direction * fixedDistance
        DustDragEvent:FireServer("UpdateDrag", draggingDustID, mouseWorldPos)
        targetDust = dusts[draggingDustID]
        Log.Text = "Entity ID: " .. draggingDustID .. "\n" .. DebugHelper:SafeJSONEncode(targetDust)
    end

    while accumulatedTime >= SIMULATION_INTERVAL do
        accumulatedTime -= SIMULATION_INTERVAL

        CachePlayerPositions()
        SimulateDusts(SIMULATION_INTERVAL)
    end

    local alpha = accumulatedTime / SIMULATION_INTERVAL
    RenderDusts(alpha)

    MouseHoverOverDust(dt)
end

-- Cache player root positions
function CachePlayerPositions()
    cachedPlayerPositions = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                cachedPlayerPositions[player] = rootPart.Position
            end
        end
    end
end

-- Simulate dust behavior (physics, fleeing, color logic)
function SimulateDusts(dt)
    for dustID, data in pairs(dusts) do
        if data.Part and data.Part.Parent then
            -- Save last position before moving
            data.LastPosition = data.Position

            if data.IsBeingDragged and data.DragTargetPosition then
                -- Drag movement
                data.Position = data.Position:Lerp(data.DragTargetPosition, math.clamp(dt * 10, 0, 1))
                data.IsFleeing = true
            else
                -- Gravity + drifting
                data.Position += data.Direction * data.Speed * dt
                data.Position += Vector3.new(0, -0.5 * dt, 0)

                -- Slow down if moving too fast
                local MAX_ALLOWED_SPEED = 5
                if data.Speed > MAX_ALLOWED_SPEED then
                    data.Speed = math.clamp(data.Speed - dt * 10, MAX_ALLOWED_SPEED, data.Speed)
                    data.Speed *= 0.98
                end

                -- Ground / Ceiling Bounce
                if data.Position.Y < 0.5 then
                    data.Direction = Vector3.new(data.Direction.X, math.abs(data.Direction.Y), data.Direction.Z)
                    data.Position = Vector3.new(data.Position.X, 0.5, data.Position.Z)
                elseif data.Position.Y > 15 then
                    data.Direction = Vector3.new(data.Direction.X, -math.abs(data.Direction.Y), data.Direction.Z)
                    data.Position = Vector3.new(data.Position.X, 15, data.Position.Z)
                end

                local x, xWarped = wrapAxis(data.Position.X)
                local z, zWarped = wrapAxis(data.Position.Z)

                local wasWarped = xWarped or zWarped

                data.Position = Vector3.new(x, data.Position.Y, z)

                if wasWarped then
                    -- Prevent bad lerp across world
                    data.LastPosition = data.Position
                end
            end

            -- Flee logic and push logic
            HandlePlayerPushAndFlee(dustID, data, dt)

            -- Glow and flee timers
            HandleGlowAndFleeTimers(data, dt)

            -- Color blending
            HandleColorBlending(data, dt)
        end
    end
end

-- Render visuals based on interpolation
function RenderDusts(alpha)
    for dustID, data in pairs(dusts) do
        if data.Part and data.Part.Parent then
            -- Wobble
            local t = tick() + data.TimeOffset
            local wobbleX = math.sin(t * 1.5) * WOBBLE_INTENSITY
            local wobbleY = math.cos(t * 2) * WOBBLE_INTENSITY * 0.5
            local wobbleZ = math.sin(t * 1.2) * WOBBLE_INTENSITY
            local wobble = Vector3.new(wobbleX, wobbleY, wobbleZ)

            -- Interpolated position
            local interpolatedPos = data.LastPosition:Lerp(data.Position, alpha)
            data.Part.Position = interpolatedPos + wobble

            -- Size and Transparency already updated in SimulateDusts (nothing extra needed)
            data.Part.Color = data.Color
        end
    end
end

-- Handle pushing and fleeing triggered by players
function HandlePlayerPushAndFlee(dustID, data, dt)
    for player, rootPos in pairs(cachedPlayerPositions) do
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        local speed = humanoid and humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed or 0
        local dist = (rootPos - data.Position).Magnitude
        if dist < PLAYER_PUSH_RADIUS and speed > 10 then
            local pushStrength = math.clamp(speed / 16, 0, PLAYER_PUSH_FORCE)
            local pushDir = (data.Position - rootPos).Unit

            local pushForce = pushDir * pushStrength * 5
            data.Direction = (data.Direction + pushForce).Unit
            data.Speed = math.clamp(data.Speed + pushStrength * 1.05, 0, 20)

            -- Start fleeing if not already
            if not data.IsFleeing then
                data.IsFleeing = true
                data.FleeTimer = 2
                data.Part.Transparency = 0

                -- Flee propagation to nearby dusts
                for otherID, otherData in pairs(dusts) do
                    if otherID ~= dustID and not otherData.IsFleeing then
                        local distance = (otherData.Position - data.Position).Magnitude
                        if distance < 8 then
                            otherData.IsFleeing = true
                            otherData.FleeTimer = 1.5 + otherData.Random:NextNumber(0, 0.5)
                            otherData.Part.Transparency = 0
                        end
                    end
                end
            end
        end
    end
end

-- Handle glow flickering and fleeing timers
function HandleGlowAndFleeTimers(data, dt)
    local t = tick()
    if data.IsFleeing then
        data.FleeTimer -= dt
        if data.FleeTimer <= 0 then
            data.IsFleeing = false
        end
        data.Part.Transparency = 0
        data.Part.Size = DUST_SIZE * 1.5
    else
        data.Part.Size = DUST_SIZE
        data.GlowTimer -= dt
        if data.GlowTimer <= 0 then
            data.GlowState = not data.GlowState
            local glowAlpha = (math.sin(t * 10) + 1) / 2
            data.Part.Transparency = 0.7 - glowAlpha * 0.7
            data.GlowTimer = data.Random:NextNumber(5, 10)
        end
    end
end

-- Handle color blending between color sequence
function HandleColorBlending(data, dt)
    if not data.Rainbow then
        data.ColorTimer += dt
        local sequence = data.ColorSequence
        if sequence and #sequence > 1 then
            local nextIndex = data.CurrentColorIndex + 1
            if nextIndex > #sequence then
                nextIndex = 1
            end

            local blendAlpha = math.clamp(data.ColorTimer / data.ColorBlendDuration, 0, 1)
            local fromColor = sequence[data.CurrentColorIndex]
            local toColor = sequence[nextIndex]
            data.Color = fromColor:Lerp(toColor, blendAlpha)

            if blendAlpha >= 1 then
                data.CurrentColorIndex = nextIndex
                data.ColorTimer = 0
                data.ColorBlendDuration = data.Random:NextNumber(2, 5)
            end
        end
    else
        local hue = tick() % 5 / 5
        data.Color = Color3.fromHSV(hue, 1, 1)
    end
end

AskDustState.OnClientEvent:Connect(function(command, data)
    if command == "RequestDustState" then
        local targetUserId = data
        local currentDusts = dusts
        AskDustState:FireServer("SendDustState", targetUserId, currentDusts)

    elseif command == "ReceiveDustState" then
        local dustDataList = data
        for _, info in ipairs(dustDataList) do
            local dust = getDustFromPool()
            dust.Position = info.Position
            dust.Color = info.Color or Color3.fromRGB(255,255,255)
            dust.Parent = workspace.Dusts

            dusts[info.DustID] = dustDataList[info.DustID]
        end
    end

end)

function MouseHoverOverDust(dt)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	logTime += dt

    local hoveredDust = nil
	local target = Mouse.Target

	if target and target:IsDescendantOf(workspace.Dusts) then
		for dustID, dustData in pairs(dusts) do
			if dustData.Part == target then
				if root then
					local dist = (root.Position - dustData.Position).Magnitude
					if dist <= PICK_RADIUS then
                        hoveredDust = dustData
                        Log.Text = "Entity ID: " .. dustID .. "\n" .. DebugHelper:SafeJSONEncode(hoveredDust)
                        logTime = 0 -- reset hover cooldown
                        break
                    end
				end
				break
			end
		end
	end

    -- If we hovered a dust, track it
	if hoveredDust then
		targetDust = hoveredDust
	end

	-- If tracking a dust (hovered or lingering), show ray
	if targetDust and logTime <= 3 then
        rayModel.Parent = workspace
		from.Position = root.Position + Vector3.new(0, 2, 0)
		to.Position = targetDust.Position + Vector3.new(0, 0, 0)
	else
		rayModel.Parent = nil
		Log.Text = ""
		targetDust = nil
	end
end


UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1  or input.UserInputType == Enum.UserInputType.Touch then
        -- Left click
        local target = Mouse.Target
        if not target and input.UserInputType == Enum.UserInputType.Touch then
            -- For Touch, you may need to Raycast manually based on screen touch position
            local touchPosition = input.Position
            local ray = workspace.CurrentCamera:ScreenPointToRay(touchPosition.X, touchPosition.Y)
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {workspace.Dusts}
            rayParams.FilterType = Enum.RaycastFilterType.Whitelist
            local result = workspace:Raycast(ray.Origin, ray.Direction * 100, rayParams)
            if result then
                target = result.Instance
            end
        end

        if target and target:IsDescendantOf(workspace.Dusts) then
            -- Find the DustID
            for dustID, dustData in pairs(dusts) do
                if dustData.Part == target then
                    local playerRoot = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if playerRoot then
                        local dist = (playerRoot.Position - dustData.Position).Magnitude
                        if dist <= PICK_RADIUS then -- limit picking range
                            draggingDustID = dustID
                            DustDragEvent:FireServer("StartDrag", dustID)
                        end
                    end
                    break
                end
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if draggingDustID then
            DustDragEvent:FireServer("StopDrag", draggingDustID)
            draggingDustID = nil
            Log.Text = " "
        end
    end
end)

DustDragEvent.OnClientEvent:Connect(function(command, dustID, extraData)
    if command == "StartDrag" then
        local dustData = dusts[dustID]
        local userId = extraData
        if dustData then
            dustData.IsBeingDragged = true
            dustData.DraggerUserId = userId
        end
    elseif command == "StopDrag" then
        local dustData = dusts[dustID]
        if dustData then
            dustData.IsBeingDragged = false
            dustData.DraggerUserId = nil
        end
    elseif command == "UpdateDrag" then
        local dustData = dusts[dustID]
        if dustData then
            dustData.DragTargetPosition = Vector3.new(extraData.X, math.clamp(extraData.Y, 1, 15), extraData.Z)
        end
    end
end)

return DustController