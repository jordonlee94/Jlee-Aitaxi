local QBCore = exports['qb-core']:GetCoreObject()
local playerCooldowns = {}

local function sLog(msg)
    print(('[AI-TAXI DEBUG] [SERVER] %s'):format(tostring(msg)))
end

-- Validate payment method
local function isValidPaymentMethod(method)
     return method == 'bank' or method == 'cash'
 end

-- Get player's money for validation
local function getPlayerMoney(src, method)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return nil end
    if method == 'bank' then
        return Player.PlayerData.money.bank
    elseif method == 'cash' then
        return Player.PlayerData.money.cash
    end
    return nil
end

-- Charge player for fare (with validation)
RegisterNetEvent('qb-ai-taxi:server:chargePlayer', function(amount, method)
     local src = source
     local Player = QBCore.Functions.GetPlayer(src)
     if not Player then
         sLog('Player not found for source: ' .. tostring(src))
         return
     end

     local fare = tonumber(amount) or 0
     method = method or 'bank'

     -- Validate payment method
     if not isValidPaymentMethod(method) then
         TriggerClientEvent('qb-ai-taxi:client:notify', src, 'Taxi: Invalid payment method')
         TriggerClientEvent('qb-ai-taxi:client:paymentFailed', src)
         sLog('Invalid payment method: ' .. tostring(method))
         return
     end

     -- Validate fare is reasonable (prevent abuse)
     if fare < 0 or fare > 10000 then
         TriggerClientEvent('qb-ai-taxi:client:notify', src, 'Taxi: Invalid fare amount')
         TriggerClientEvent('qb-ai-taxi:client:paymentFailed', src)
         sLog('Invalid fare: ' .. tostring(fare))
         return
     end

     -- Check if player has sufficient funds before charging
     local playerMoney = getPlayerMoney(src, method)
     if not playerMoney or playerMoney < fare then
         TriggerClientEvent('qb-ai-taxi:client:notify', src, 'Taxi: Insufficient funds')
         TriggerClientEvent('qb-ai-taxi:client:paymentFailed', src)
         sLog('Insufficient funds for player: ' .. tostring(src) .. ' needed: ' .. tostring(fare) .. ' has: ' .. tostring(playerMoney or 0))
         return
     end

     local success = pcall(function()
         QBCore.Functions.RemoveMoney(src, method, fare)
     end)

     if success then
         TriggerClientEvent('qb-ai-taxi:client:notify', src, ('Taxi: $%s paid via %s'):format(fare, method))
         sLog('Charged player ' .. tostring(src) .. ' fare: $' .. tostring(fare) .. ' method: ' .. method)
     else
         TriggerClientEvent('qb-ai-taxi:client:notify', src, 'Taxi: Payment failed')
         TriggerClientEvent('qb-ai-taxi:client:paymentFailed', src)
         sLog('Payment failed for player: ' .. tostring(src) .. ' fare: $' .. tostring(fare))
     end
 end)

-- Reset on resource start
AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end
    playerCooldowns = {}
end)

-- Clean up player data on disconnect
AddEventHandler('playerDropped', function()
    local src = source
    playerCooldowns[src] = nil
end)
