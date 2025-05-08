--init.client
local RunService = game:GetService("RunService")
local DustController = require(script.Simulations.DustController)

RunService.RenderStepped:Connect(function(dt)
    DustController:Update(dt)
end)
