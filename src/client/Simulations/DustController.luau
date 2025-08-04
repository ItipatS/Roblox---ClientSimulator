--[[

DustController
--------------
Client-side controller that manages the visual and interactive behavior of "Dust" particles in a Roblox experience.

Responsibilities:
- Receiving and managing dust entity data via RemoteEvents.
- Simulating movement, glow, color blending, and fleeing behavior.
- Handling drag interaction via mouse/touch input.
- Interpolating and rendering dust positions with visual effects.
- Synchronizing state with server and other clients.

--]]

local DustController = {}

--// Remote events for networked communication
local FloatEvent = game.ReplicatedStorage:WaitForChild("FloatEvent")
local AskDustState = game.ReplicatedStorage:WaitForChild("AskDustState")
local DustDragEvent = game.ReplicatedStorage:WaitForChild("DustDragEvent")

--// Services and references
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera
local Log:TextLabel = LocalPlayer.PlayerGui:WaitForChild("Interface"):WaitForChild("Log")
local DebugHelper = require(script.Parent.Parent.Utility.DebugHelper)

--// Dust state
local dusts = {}         -- [DustID] = data table
local dustPool = {}      -- reused part objects
local cachedPlayerPositions = {}

--// Drag state
local draggingDustID = nil
local targetDust = nil

--// Timers
local accumulatedTime = 0
local mouseUpdateTimer = 0
local logTime = 0

--// Constants
local SIMULATION_INTERVAL = 0.05
local WARP_AREA_SIZE = 100
local PICK_RADIUS = 10
local DUST_SIZE = Vector3.new(0.3, 0.3, 0.3)
local WOBBLE_INTENSITY = 0.5
local PLAYER_PUSH_RADIUS = 5
local PLAYER_PUSH_FORCE = 10

--// Beam for hover line
local rayModel = Instance.new("Model", workspace)
rayModel.Name = "HoverRay"
rayModel:MoveTo(Vector3.new(0, -100, 0)) -- initially hidden

local from = Instance.new("Part", rayModel)
from.Name = "From"
from.Anchored = true
from.CanCollide = false
from.Size = Vector3.new(0.1, 0.1, 0.1)
from.Transparency = 1

local to = Instance.new("Part", rayModel)
to.Name = "To"
to.Anchored = true
to.CanCollide = false
to.Size = Vector3.new(0.1, 0.1, 0.1)
to.Transparency = 1

local a1 = Instance.new("Attachment", from)
local a2 = Instance.new("Attachment", to)

local beam = Instance.new("Beam", from)
beam.Attachment0 = a1
beam.Attachment1 = a2
beam.FaceCamera = true
beam.Width0 = 0.1
beam.Width1 = 0.1
beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 0))

--Log Config
Log.RichText = true
Log.TextScaled = true
--------------------------------------------------------------------------------
-- Dust Pooling
--------------------------------------------------------------------------------

local function getDustFromPool(): Part
    if #dustPool > 0 then
        return table.remove(dustPool)
    end

    local dust = Instance.new("Part")
    dust.Shape = Enum.PartType.Ball
    dust.Size = DUST_SIZE
    dust.Anchored = true
    dust.CanCollide = false
    dust.CastShadow = false
    dust.Material = Enum.Material.Neon
    return dust
end

--------------------------------------------------------------------------------
-- Wrap Function
--------------------------------------------------------------------------------

local function wrapAxis(value: number): (number, boolean)
    local range = WARP_AREA_SIZE * 2
    if value > WARP_AREA_SIZE then
        return value - range, true
    elseif value < -WARP_AREA_SIZE then
        return value + range, true
    end
    return value, false
end

--------------------------------------------------------------------------------
-- Remote Handling
--------------------------------------------------------------------------------

FloatEvent.OnClientEvent:Connect(function(command, data)
    if command == "Spawn" then
        for _, info in ipairs(data) do
            local colorIndex = math.random(1, #info.Color)
            local dust = getDustFromPool()
            dust.Position = info.Position
            dust.Color = info.Color[colorIndex] or Color3.new(1, 1, 1)
            dust.Parent = workspace.Dusts

            dusts[info.DustID] = {
                Part = dust,
                Position = info.Position,
                Direction = info.Direction.Unit,
                Speed = info.Speed or 2,
                TimeOffset = info.TimeOffset or 0,
                Rainbow = info.Rainbow or false,
                Seed = info.Seed or 12345,
                Random = Random.new(info.Seed or 12345),
                GlowTimer = 0,
                GlowState = true,
                IsFleeing = false,
                FleeTimer = 0,
                ColorSequence = info.Color,
                Color = info.Color[colorIndex],
                CurrentColorIndex = colorIndex,
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

DustDragEvent.OnClientEvent:Connect(function(command, dustID, extraData)
    local dust = dusts[dustID]
    if not dust then return end

    if command == "StartDrag" then
        dust.IsBeingDragged = true
        dust.DraggerUserId = extraData
    elseif command == "StopDrag" then
        dust.IsBeingDragged = false
        dust.DraggerUserId = nil
    elseif command == "UpdateDrag" then
        dust.DragTargetPosition = Vector3.new(extraData.X, math.clamp(extraData.Y, 1, 15), extraData.Z)
    end
end)

AskDustState.OnClientEvent:Connect(function(command, data)
    if command == "RequestDustState" then
        AskDustState:FireServer("SendDustState", data, dusts)
    elseif command == "ReceiveDustState" then
        for _, info in ipairs(data) do
            local dust = getDustFromPool()
            dust.Position = info.Position
            dust.Color = info.Color or Color3.new(1, 1, 1)
            dust.Parent = workspace.Dusts
            dusts[info.DustID] = data[info.DustID]
        end
    end
end)

--------------------------------------------------------------------------------
-- Main Update Loop
--------------------------------------------------------------------------------

function DustController:Update(dt)
    accumulatedTime += dt
    mouseUpdateTimer += dt

    if draggingDustID and mouseUpdateTimer > 0.05 then
        mouseUpdateTimer = 0
        local mousePos = UserInputService:GetMouseLocation()
        local ray = Camera:ScreenPointToRay(mousePos.X, mousePos.Y)
        local mouseWorldPos = ray.Origin + ray.Direction * PICK_RADIUS
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

--------------------------------------------------------------------------------
-- Input Events
--------------------------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local target = Mouse.Target
        if not target and input.UserInputType == Enum.UserInputType.Touch then
            -- Touch: Raycast manually
            local ray = Camera:ScreenPointToRay(input.Position.X, input.Position.Y)
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {workspace.Dusts}
            rayParams.FilterType = Enum.RaycastFilterType.Whitelist
            local result = workspace:Raycast(ray.Origin, ray.Direction * 100, rayParams)
            target = result and result.Instance
        end

        if target and target:IsDescendantOf(workspace.Dusts) then
            for dustID, dustData in pairs(dusts) do
                if dustData.Part == target then
                    local playerRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if playerRoot and (playerRoot.Position - dustData.Position).Magnitude <= PICK_RADIUS then
                        draggingDustID = dustID
                        DustDragEvent:FireServer("StartDrag", dustID)
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

--------------------------------------------------------------------------------
-- Internal Logic (Simulation + Rendering)
--------------------------------------------------------------------------------

-- Simulates physics, movement, fleeing, and glow for all dusts
function SimulateDusts(dt)
    for dustID, data in pairs(dusts) do
        if data.Part and data.Part.Parent then
            -- Save previous position for interpolation
            data.LastPosition = data.Position

            if data.IsBeingDragged and data.DragTargetPosition then
                -- Smoothly interpolate toward drag position
                data.Position = data.Position:Lerp(data.DragTargetPosition, math.clamp(dt * 10, 0, 1))
                data.IsFleeing = true
            else
                -- Default movement with gravity
                data.Position += data.Direction * data.Speed * dt
                data.Position += Vector3.new(0, -0.5 * dt, 0) -- simulate gravity

                -- Apply soft speed cap
                local MAX_ALLOWED_SPEED = 5
                if data.Speed > MAX_ALLOWED_SPEED then
                    data.Speed = math.clamp(data.Speed - dt * 10, MAX_ALLOWED_SPEED, data.Speed)
                    data.Speed *= 0.98
                end

                -- Vertical bounce between ground and ceiling
                if data.Position.Y < 0.5 then
                    data.Direction = Vector3.new(data.Direction.X, math.abs(data.Direction.Y), data.Direction.Z)
                    data.Position = Vector3.new(data.Position.X, 0.5, data.Position.Z)
                elseif data.Position.Y > 15 then
                    data.Direction = Vector3.new(data.Direction.X, -math.abs(data.Direction.Y), data.Direction.Z)
                    data.Position = Vector3.new(data.Position.X, 15, data.Position.Z)
                end

                -- Warp edges around the playable field
                local x, xWarped = wrapAxis(data.Position.X)
                local z, zWarped = wrapAxis(data.Position.Z)
                data.Position = Vector3.new(x, data.Position.Y, z)

                if xWarped or zWarped then
                    -- Prevent weird interpolation across map wrap
                    data.LastPosition = data.Position
                end
            end

            -- Push and flee from players
            HandlePlayerPushAndFlee(dustID, data, dt)

            -- Update visual timers and glow states
            HandleGlowAndFleeTimers(data, dt)

            -- Blend color sequence or rainbow mode
            HandleColorBlending(data, dt)
        end
    end
end

-- Interpolates dust positions and renders wobble, color, and size
function RenderDusts(alpha)
    for _, data in pairs(dusts) do
        if data.Part and data.Part.Parent then
            -- Apply procedural wobble
            local t = tick() + data.TimeOffset
            local wobble = Vector3.new(
                math.sin(t * 1.5),
                math.cos(t * 2) * 0.5,
                math.sin(t * 1.2)
            ) * WOBBLE_INTENSITY

            -- Interpolate between last and current positions
            local interpolatedPos = data.LastPosition:Lerp(data.Position, alpha)
            data.Part.Position = interpolatedPos + wobble

            -- Update color (from Simulate step)
            data.Part.Color = data.Color
        end
    end
end

-- Caches all player root positions for efficient distance checks
function CachePlayerPositions()
    cachedPlayerPositions = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            local root = character:FindFirstChild("HumanoidRootPart")
            if root then
                cachedPlayerPositions[player] = root.Position
            end
        end
    end
end

-- Handles player proximity to dust, pushing and initiating "flee" behavior
function HandlePlayerPushAndFlee(dustID, data, dt)
    for player, rootPos in pairs(cachedPlayerPositions) do
        local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        local speed = humanoid and humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed or 0
        local dist = (rootPos - data.Position).Magnitude

        if dist < PLAYER_PUSH_RADIUS and speed > 10 then
            local pushStrength = math.clamp(speed / 16, 0, PLAYER_PUSH_FORCE)
            local pushDir = (data.Position - rootPos).Unit
            local pushForce = pushDir * pushStrength * 5

            -- Blend direction and speed
            data.Direction = (data.Direction + pushForce).Unit
            data.Speed = math.clamp(data.Speed + pushStrength * 1.05, 0, 20)

            -- Trigger flee mode and nearby reactions
            if not data.IsFleeing then
                data.IsFleeing = true
                data.FleeTimer = 2
                data.Part.Transparency = 0

                for otherID, otherData in pairs(dusts) do
                    if otherID ~= dustID and not otherData.IsFleeing then
                        local d = (otherData.Position - data.Position).Magnitude
                        if d < 8 then
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

-- Flicker glow and scale size during flee/idle state
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

-- Blend between sequential colors or rainbow mode
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
        -- Rainbow: cycle hue smoothly
        local hue = tick() % 5 / 5
        data.Color = Color3.fromHSV(hue, 1, 1)
    end
end

-- Draws a beam from player to the hovered dust (with UI log info)
function MouseHoverOverDust(dt)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    logTime += dt
    local hoveredDust = nil
    local target = Mouse.Target

    if target and target:IsDescendantOf(workspace.Dusts) then
        for dustID, dustData in pairs(dusts) do
            if dustData.Part == target then
                local dist = (root.Position - dustData.Position).Magnitude
                if dist <= PICK_RADIUS then
                    hoveredDust = dustData
                    Log.Text = "Entity ID: " .. dustID .. "\n" .. DebugHelper:SafeJSONEncode(hoveredDust)
                    logTime = 0
                    break
                end
            end
        end
    end

    -- Track hovered dust for 3 seconds
    if hoveredDust then
        targetDust = hoveredDust
    end

    if targetDust and logTime <= 3 then
        rayModel.Parent = workspace
        from.Position = root.Position + Vector3.new(0, 2, 0)
        to.Position = targetDust.Position
    else
        rayModel.Parent = nil
        Log.Text = ""
        targetDust = nil
    end
end

return DustController

