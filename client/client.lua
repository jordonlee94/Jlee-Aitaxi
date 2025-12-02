local QBCore = exports['qb-core']:GetCoreObject()
local guiOpen = false
local activeRide = nil
local cooldowns = {} -- per-mode timestamp (ms)
local lastAny = 0

local function sLog(msg)
    if not Config.Debug then return end
    print(('[AI-TAXI DEBUG] [CLIENT] %s'):format(tostring(msg)))
end

local function notify(text)
    if QBCore and QBCore.Functions and QBCore.Functions.Notify then
        QBCore.Functions.Notify(text)
    else
        TriggerEvent('chat:addMessage', { args = { 'Taxi', text } })
    end
end



-- small helper: raycast forward from a vehicle
local function RaycastFromVehicle(vehicle, distance, height)
    distance = distance or 8.0
    height = height or 1.2
    local pos = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local start = pos + vector3(0.0, 0.0, height)
    local finish = start + forward * distance
    local ray = StartShapeTestRay(start.x, start.y, start.z, finish.x, finish.y, finish.z, -1, vehicle, 7)
    local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(ray)
    return hit == 1, entityHit, endCoords, surfaceNormal
end

-- compute a dodge point left/right around an obstacle
local function ComputeDodgePoint(vehicle, hitCoords, dodgeDistance)
    local forward = GetEntityForwardVector(vehicle)
    local right = vector3(-forward.y, forward.x, 0.0)
    local leftPoint = hitCoords - right * dodgeDistance
    local rightPoint = hitCoords + right * dodgeDistance

    local foundL, zl = GetGroundZFor_3dCoord(leftPoint.x, leftPoint.y, leftPoint.z + 5.0, 0)
    if foundL then leftPoint = vector3(leftPoint.x, leftPoint.y, zl) end
    local foundR, zr = GetGroundZFor_3dCoord(rightPoint.x, rightPoint.y, rightPoint.z + 5.0, 0)
    if foundR then rightPoint = vector3(rightPoint.x, rightPoint.y, zr) end

    -- choose side with clearer raycast
    local rayL = StartShapeTestRay(GetEntityCoords(vehicle).x, GetEntityCoords(vehicle).y, GetEntityCoords(vehicle).z + 1.0,
                                   leftPoint.x, leftPoint.y, leftPoint.z + 1.0, -1, vehicle, 7)
    local _, hitL = GetShapeTestResult(rayL)
    local rayR = StartShapeTestRay(GetEntityCoords(vehicle).x, GetEntityCoords(vehicle).y, GetEntityCoords(vehicle).z + 1.0,
                                   rightPoint.x, rightPoint.y, rightPoint.z + 1.0, -1, vehicle, 7)
    local _, hitR = GetShapeTestResult(rayR)

    if hitL == 0 then return leftPoint end
    if hitR == 0 then return rightPoint end

    local distL = #(GetEntityCoords(vehicle) - leftPoint)
    local distR = #(GetEntityCoords(vehicle) - rightPoint)
    return (distL > distR) and leftPoint or rightPoint
end

-- Clean up model loading
local function releaseModel(hash)
    if hash and HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
    end
end

-- Validate ride safety
local function isValidRide(ride)
    if not ride then return false end
    return DoesEntityExist(ride.vehicle) and DoesEntityExist(ride.driver) and DoesEntityExist(ride.player)
end

-- Initialize on resource start
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(100)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideUI' })
    lastAny = 0
    cooldowns = {}
    activeRide = nil
    sLog('Resource started - NUI initialized')
end)

-- Open command
RegisterCommand('aitaxi', function()
     if guiOpen then return end
     local now = GetGameTimer()
     local globalCooldown = (Config.Cooldowns and Config.Cooldowns.Global or 0) * 1000
     if lastAny > 0 and now < (lastAny + globalCooldown) then
         local left = math.ceil((lastAny + globalCooldown - now) / 1000)
         notify(('Taxi service busy. Try again in %s s'):format(left))
         return
     end
     if not SetNuiFocus then notify('NUI not ready'); return end
     SetNuiFocus(true, true)
     SendNUIMessage({ action = 'openUI', config = Config })
     guiOpen = true
     sLog('UI opened via /aitaxi')
 end, false)

RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideUI' })
    guiOpen = false
    sLog('UI closed')
    cb('ok')
end)

-- helper model loader (optimized for faster loading)
local function loadModel(hash, name)
     RequestModel(hash)
     local t0 = GetGameTimer()
     while not HasModelLoaded(hash) do
         Wait(10)  -- Reduced from 50ms for quicker polling
         if GetGameTimer() - t0 > 5000 then
             sLog('Model load timeout: ' .. tostring(name))
             releaseModel(hash)
             return false
         end
     end
     return true
 end

-- compute fare and eta helper with distance validation
local function computeFareAndETA(playerCoords, dest)
     local dist = #(playerCoords - dest) -- meters
     local km = dist / 1000.0
     local fare = math.floor((Config.Fare.BaseFare or 0) + (km * (Config.Fare.RatePerKm or 1)))
     local speed = Config.Fare.AverageSpeedKmH or 80.0
     local etaSeconds = math.floor((dist / 1000.0) / (speed/3600.0)) -- dist(km) / speed(km/h) => hours -> *3600 = seconds
     return fare, etaSeconds, math.floor(dist)
 end

-- validate destination is within reasonable range (prevent map edge exploits)
local function isValidDestination(playerCoords, dest)
     local dist = #(playerCoords - dest)
     local maxRange = 20000.0 -- max 20km for taxi service
     return dist > 0 and dist <= maxRange
 end

-- Extract destination from data (reusable helper)
local function getDestinationFromData(data)
     local dest = nil
     local presetName = nil
     if data.useWaypoint then
         local blip = GetFirstBlipInfoId(8)
         if blip ~= 0 then
             local x,y,z = table.unpack(Citizen.InvokeNative(0xFA7C7F0AADF25D09, blip, Citizen.ResultAsVector()))
             dest = vector3(x,y,z)
         else
             return nil, 'No waypoint'
         end
     elseif data.quickIndex then
         local idx = tonumber(data.quickIndex)
         if Config.PresetLocations[idx] then
             dest = Config.PresetLocations[idx].coords
             presetName = Config.PresetLocations[idx].name
         else
             return nil, 'Invalid preset'
         end
     else
         return nil, 'No destination'
     end
     return dest, nil, presetName
end

-- Preview endpoint: client receives preview requests from NUI (when selecting preset or waypoint)
RegisterNUICallback('preview', function(data, cb)
      local ped = PlayerPedId()
      if not ped or ped == 0 then cb({ success = false, reason = 'Invalid player' }) return end
      
      local playerCoords = GetEntityCoords(ped)
      local dest, err, presetName = getDestinationFromData(data)
      
      if not dest then cb({ success = false, reason = err or 'Invalid' }) return end
      if not isValidDestination(playerCoords, dest) then cb({ success=false, reason='Destination too far' }) return end
      
      local fare, eta, meters = computeFareAndETA(playerCoords, dest)
      cb({ success=true, fare=fare, eta=eta, meters=meters, preset = presetName })
      sLog(('Preview calculated fare=%s eta=%s m=%s'):format(tostring(fare), tostring(eta), tostring(meters)))
 end)

 -- Request Taxi: opens confirmation modal and then confirm triggers spawn
RegisterNUICallback('requestTaxi', function(data, cb)
     -- data: { mode, useWaypoint, quickIndex }
     -- open confirmation modal via NUI (client will wait for confirm/cancel)
     SendNUIMessage({ action = 'openConfirm', data = data })
     cb({ success=true })
end)

-- handle confirm from NUI (actually spawn taxi)
RegisterNUICallback('confirmRide', function(data, cb)
    -- data contains the same fields: mode, useWaypoint, quickIndex
    local now = GetGameTimer()
    -- per-mode cooldown
    local mode = data.mode or 'watch'
    local modeKey = (mode == 'skip') and 'Skip' or 'Watch'
    local modeCd = cooldowns[modeKey]
    if modeCd and now < modeCd then
        local left = math.ceil((modeCd - now)/1000)
        cb({ success=false, reason='Mode cooldown active', left=left })
        return
    end
    -- store lastAny and mode cooldown
    lastAny = now
    cooldowns[modeKey] = now + ((Config.Cooldowns and Config.Cooldowns[modeKey]) or 0)*1000
    -- forward to server-spawn logic by triggering local spawn handler
    TriggerEvent('qb-ai-taxi:client:spawnTaxiFromNui', data)
    cb({ success=true })
end)

-- spawn handler reused (accepts data from preview/request)
RegisterNetEvent('qb-ai-taxi:client:spawnTaxiFromNui', function(data)
      local ped = PlayerPedId()
      if not ped or ped == 0 then notify('Invalid player.'); return end
      
      local playerCoords = GetEntityCoords(ped)
      sLog('spawnTaxiFromNui called, assembling destination')
      
      local dest, err, presetName = getDestinationFromData(data)
      if not dest then notify(err or 'Invalid destination.'); return end
      if not isValidDestination(playerCoords, dest) then notify('Destination too far.'); return end

    sLog('Spawning taxi and driver...')
    local forward = GetEntityForwardVector(ped)
    local spawnPos = playerCoords + forward * (Config.SpawnDistance or 3.0)
    local vehHash = GetHashKey(Config.TaxiModel)
    local pedHash = GetHashKey(Config.DriverModel)

    if not loadModel(vehHash, Config.TaxiModel) then notify('Taxi model load failed'); return end
    if not loadModel(pedHash, Config.DriverModel) then notify('Driver model load failed'); return end

      local vehicle = CreateVehicle(vehHash, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, true, false)
      if not DoesEntityExist(vehicle) then
          notify('Vehicle creation failed.')
          releaseModel(vehHash)
          releaseModel(pedHash)
          return
      end
      
      SetVehicleOnGroundProperly(vehicle)
     SetEntityAsMissionEntity(vehicle, true, true)
     SetVehicleDirtLevel(vehicle, 0.0)
     SetVehicleDoorsLocked(vehicle, 1)
     SetEntityInvincible(vehicle, true)
     SetVehicleTyresCanBurst(vehicle, false)
     SetVehicleCanBeVisiblyDamaged(vehicle, false)

     local driver = CreatePedInsideVehicle(vehicle, 26, pedHash, -1, true, false)
     if not DoesEntityExist(driver) then
         sLog('Driver creation failed')
         if DoesEntityExist(vehicle) then DeleteVehicle(vehicle) end
         releaseModel(vehHash)
         releaseModel(pedHash)
         notify('Driver creation failed.')
         return
     end

    SetEntityAsMissionEntity(driver, true, true)
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedFleeAttributes(driver, 0, false)
    SetPedCanBeDraggedOut(driver, false)
    SetPedKeepTask(driver, true)
    SetPedDiesWhenInjured(driver, false)
    SetDriverAbility(driver, 1.0)
    SetDriverAggressiveness(driver, 0.7)
    SetEntityVisible(driver, true, 0)

    NetworkRegisterEntityAsNetworked(vehicle)
    NetworkRegisterEntityAsNetworked(driver)

    if GetPedInVehicleSeat(vehicle, -1) ~= driver then
        TaskWarpPedIntoVehicle(driver, vehicle, -1)
        Wait(400)
    end

    TaskVehicleDriveWander(driver, vehicle, 10.0, Config.DrivingStyle or 786603)
    Wait(800)
    local seat = Config.ForceSeat or -1
    if seat == -1 then seat = 0 end
    TaskWarpPedIntoVehicle(ped, vehicle, seat)
    Wait(800)

     -- ensure both seated quickly
     local ok = false
     for i=1,50 do
         if GetPedInVehicleSeat(vehicle, -1) == driver and GetPedInVehicleSeat(vehicle, 0) == ped then
             ok = true break
         end
         Wait(100)
     end
     if not ok then
         sLog('Driver or player not seated - aborting')
         if DoesEntityExist(driver) then DeleteEntity(driver) end
         if DoesEntityExist(vehicle) then DeleteVehicle(vehicle) end
         releaseModel(vehHash)
         releaseModel(pedHash)
         notify('Failed to start taxi.')
         return
     end
    -- handle skip mode (instant teleport instead of drive)
if data.mode == 'skip' then
    sLog('Skip mode activated - teleporting with cinematic fade')

    -- Compute fare right here
    local fare, eta, meters = computeFareAndETA(playerCoords, dest)
    local finalFare = math.floor(fare or 0)

    Wait(600)
    if Config.SoundEffects then
        PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1)
    end

    DoScreenFadeOut(1000)
    Wait(1200)

    -- teleport taxi + occupants
    SetEntityCoordsNoOffset(vehicle, dest.x, dest.y, dest.z + 0.3, false, false, false)
    SetEntityHeading(vehicle, GetEntityHeading(vehicle))

    if not IsPedInVehicle(driver, vehicle, false) then TaskWarpPedIntoVehicle(driver, vehicle, -1) end
    if not IsPedInVehicle(ped, vehicle, false) then TaskWarpPedIntoVehicle(ped, vehicle, 0) end

    Wait(300)
    DoScreenFadeIn(1000)
    notify(('Teleport complete — fare: $%s'):format(finalFare))

    if Config.SoundEffects and Config.PlayArrivalSound then
        PlaySoundFrontend(-1, "EVENT_MP_TRANSITION_COMPLETE", "GTAO_FM_Events_Soundset", 1)
    end

     -- Charge fare properly
     TriggerServerEvent('qb-ai-taxi:server:chargePlayer', finalFare, data.payment or 'bank')
    SendNUIMessage({ action='farePopup', fare = finalFare })

    Wait(2500)
    if DoesEntityExist(driver) then DeleteEntity(driver) end
    if DoesEntityExist(vehicle) then DeleteVehicle(vehicle) end
    activeRide = nil
    SendNUIMessage({ action='clearHUD' })
    return
end



    -- compute fare estimate (recompute as safety)
    local fare, eta, meters = computeFareAndETA(playerCoords, dest)
    SetDriveTaskCruiseSpeed(driver, Config.TaxiSpeed)
    SetDriveTaskMaxCruiseSpeed(driver, Config.TaxiSpeed)
    SetDriveTaskDrivingStyle(driver, Config.DrivingStyle or 786603)

    -- start driving (smart, smooth, ignores lights)
    local SMART_DRIVING_STYLE = Config.DrivingStyle or 786603
    -- initial longrange drive task
    TaskVehicleDriveToCoordLongrange(driver, vehicle, dest.x, dest.y, dest.z, Config.TaxiSpeed, SMART_DRIVING_STYLE, 5.0)

    -- register active ride (unchanged flow)
    activeRide = { driver = driver, vehicle = vehicle, dest = dest, fare = math.floor(fare), player = ped, start = GetGameTimer(), preset = presetName, stuckAttempts = 0, payment = data.payment or 'bank' }
    sLog('Active ride started. fare=' .. tostring(activeRide.fare))
    SendNUIMessage({ action='clearHUD' })
    notify(('Taxi en route. Estimated fare: $%s'):format(tostring(activeRide.fare)))
     guiOpen = false
     SetNuiFocus(false, false)

       -- smart driving thread: obstacle avoidance (adaptive, low-frequency checks)
       CreateThread(function()
           local rideRef = activeRide -- capture reference at thread start to prevent nil access
           if not rideRef then return end
           local vehicle = rideRef.vehicle
           local driver = rideRef.driver
           local dest = rideRef.dest
           local SMART_DRIVING_STYLE = Config.DrivingStyle or 786603
           local dodgeDist = 6.0

           while activeRide and rideRef == activeRide do
               if not isValidRide(activeRide) then break end

               local curPos = GetEntityCoords(vehicle)
               local distToDest = #(curPos - dest)

               -- adaptive check interval: fewer checks when far away
               local checkInterval = 1500
               if distToDest < 1500 then checkInterval = 1200 end
               if distToDest < 500 then checkInterval = 800 end
               if distToDest < 200 then checkInterval = 400 end

               Wait(checkInterval)

               -- only perform raycasts when reasonably close to obstacles/destination
               if distToDest <= 200 then
                   local rayDist = math.min(8.0, distToDest)
                   local hit, entityHit, hitCoords = RaycastFromVehicle(vehicle, rayDist, 1.2)
                   if hit and DoesEntityExist(entityHit) then
                       local vehPos = GetEntityCoords(vehicle)
                       local dist = #(hitCoords - vehPos)
                       if dist < rayDist then
                           local dodgePoint = ComputeDodgePoint(vehicle, hitCoords, dodgeDist)
                           -- perform a smooth short drive to dodge point, then resume to destination
                           if isValidRide(activeRide) then
                               TaskVehicleDriveToCoord(driver, vehicle, dodgePoint.x, dodgePoint.y, dodgePoint.z, math.max(10.0, Config.TaxiSpeed * 0.6), 0, GetEntityModel(vehicle), SMART_DRIVING_STYLE, 3.0)
                               Wait(900) -- minimal wait to allow task to start
                               if isValidRide(activeRide) then
                                   TaskVehicleDriveToCoordLongrange(driver, vehicle, dest.x, dest.y, dest.z, Config.TaxiSpeed, SMART_DRIVING_STYLE, 5.0)
                               end
                           end
                       end
                   end
               end
           end
       end)


      -- anti-stuck and monitor thread (keeps your original behavior intact)
      CreateThread(function()
          local lastPos = GetEntityCoords(vehicle)
          local stuckCounter = 0
          local startTime = GetGameTimer()
          local lastHudUpdate = 0
          local rideRef = activeRide -- capture reference at thread start
          local capturedFare = fare -- capture fare to prevent nil access
          
           while activeRide and rideRef == activeRide do
               -- use configured interval but increase slightly for lower CPU
               Wait(Config.AntiStuck.CheckInterval or 3000)
              if not isValidRide(activeRide) then
                  sLog('Vehicle or driver missing - teleporting if configured')
                  if Config.TeleportOnTimeout and activeRide then
                      TriggerEvent('qb-ai-taxi:teleportAndCleanup', activeRide.dest, activeRide.fare, activeRide.payment or 'bank')
                  end
                  activeRide = nil
                  return
              end

              local cur = GetEntityCoords(vehicle)
              local distToDest = #(cur - activeRide.dest)
              local moved = #(cur - lastPos)
              if moved < (Config.AntiStuck.SlowThreshold or 2.0) then
                  stuckCounter = stuckCounter + 1
              else
                  stuckCounter = 0
              end
              lastPos = cur

               -- update HUD (throttle updates to every 1.5 seconds for performance)
               local now = GetGameTimer()
               if now - lastHudUpdate > 1500 then
                   local remainingMeters = math.floor(distToDest)
                   local etaSeconds = math.floor((distToDest / (Config.TaxiSpeed/3.6)))
                   if activeRide then
                       SendNUIMessage({ action='updateHUD', eta = etaSeconds, distance = remainingMeters, fare = activeRide.fare })
                       lastHudUpdate = now
                   end
               end

              if Config.Debug then sLog(('Monitoring ride: dist=%s moved=%s stuck=%s'):format(tostring(math.floor(distToDest)), tostring(math.floor(moved)), tostring(stuckCounter))) end

              -- arrival radius
              if distToDest <= Config.ArrivalRadius then

                 sLog(('Destination reached within radius (%s m)'):format(tostring(distToDest)))
                 if not isValidRide(activeRide) then activeRide = nil return end
                 
                 -- arrival sequence: open door, unseat player, charge fare, fade, cleanup
                 if Config.EnableFadeTransition then DoScreenFadeOut(800); Wait(850) end
                 -- play arrival sound
                 if Config.SoundEffects and Config.PlayArrivalSound then PlaySoundFrontend(-1, "EVENT_MP_TRANSITION_COMPLETE", "GTAO_FM_Events_Soundset", 1) end
                 -- driver line (simple voice-free text notify)
                 local lines = { "We\\'re here.", "That\\'s your stop.", "Ride\\'s over, enjoy!" }
                 local pick = lines[math.random(#lines)]
                 notify(pick)
                 
                 if activeRide then
                     TaskLeaveVehicle(activeRide.player, activeRide.vehicle, 0)
                     TriggerServerEvent('qb-ai-taxi:server:chargePlayer', activeRide.fare, activeRide.payment)
                 end
                 
                  if Config.EnableFadeTransition then Wait(600); DoScreenFadeIn(800) end
                  -- fare popup
                  if activeRide then SendNUIMessage({ action='farePopup', fare = activeRide.fare }) end
                 -- cleanup delay
                 Wait(1200)
                 if DoesEntityExist(driver) then DeleteEntity(driver) end
                 if DoesEntityExist(vehicle) then DeleteVehicle(vehicle) end
                 activeRide = nil
                 SendNUIMessage({ action='clearHUD' })
                 return
             end

             -- stuck detection and reposition attempts
             if Config.AntiStuck.Enabled and stuckCounter > 2 and activeRide then
                 activeRide.stuckAttempts = (activeRide.stuckAttempts or 0) + 1
                 sLog(('Taxi stuck detected, attempt %s'):format(tostring(activeRide.stuckAttempts)))
                 -- try reposition forward without ejecting player
                 local heading = GetEntityHeading(vehicle) * (math.pi/180)
                 local nx = cur.x + math.cos(heading) * (Config.AntiStuck.RepositionDistance or 12.0)
                 local ny = cur.y + math.sin(heading) * (Config.AntiStuck.RepositionDistance or 12.0)
                 local found, gz = GetGroundZFor_3dCoord(nx, ny, cur.z + 2.0, 0)
                 if found then
                     -- ensure player stays inside: teleport vehicle and immediately warp occupants back in if necessary
                     SetEntityCoordsNoOffset(vehicle, nx, ny, gz + 0.5, false, false, false)
                     -- attempt to keep driver & player seated
                     if activeRide and DoesEntityExist(activeRide.driver) and not IsPedInVehicle(activeRide.driver, vehicle, false) then
                         TaskWarpPedIntoVehicle(activeRide.driver, vehicle, -1)
                     end
                     if activeRide and DoesEntityExist(activeRide.player) and not IsPedInVehicle(activeRide.player, vehicle, false) then
                         TaskWarpPedIntoVehicle(activeRide.player, vehicle, 0)
                     end
                     sLog('Repositioned vehicle forward to try recover from stuck (no ejection)')
                 else
                     sLog('Reposition attempt failed to find ground')
                 end
                 if activeRide and activeRide.stuckAttempts >= (Config.AntiStuck.MaxAttempts or 3) then
                     sLog('Max reposition attempts reached - teleporting player to destination')
                     if Config.TeleportOnTimeout then
                         TriggerEvent('qb-ai-taxi:teleportAndCleanup', activeRide.dest, math.floor(activeRide.fare * ((Config.Fare.TimeoutRefundPercent or 50)/100)), activeRide.payment or 'bank')
                     end
                     activeRide = nil
                     return
                 end
             end

             -- timeout check
             if (GetGameTimer() - startTime) > (Config.TimeoutSeconds * 1000) then
                 sLog('Taxi timeout -> teleporting player')
                 if Config.TeleportOnTimeout and activeRide then
                     TriggerEvent('qb-ai-taxi:teleportAndCleanup', activeRide.dest, math.floor(activeRide.fare * ((Config.Fare.TimeoutRefundPercent or 50)/100)), activeRide.payment or 'bank')
                 end
                 activeRide = nil
                 return
             end
         end
     end)
end)

-- teleport and cleanup handler
RegisterNetEvent('qb-ai-taxi:teleportAndCleanup', function(dest, fare, payment)
    payment = payment or 'bank'
    local ped = PlayerPedId()
    sLog('TeleportAndCleanup called, dest=' .. tostring(dest))
    if Config.EnableFadeTransition then
        if Config.SoundEffects and Config.PlayFadeSound then PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", 1) end
        DoScreenFadeOut(800); Wait(850)
    end
    local offset = Config.SafeSpawnOffset or 5.0
    local ok = false
    for i=0,6 do
        local angle = (i/6) * (2*math.pi)
        local tx = dest.x + math.cos(angle) * offset
        local ty = dest.y + math.sin(angle) * offset
        local found, z = GetGroundZFor_3dCoord(tx, ty, dest.z + 2.0, 0)
        if found then
            SetEntityCoordsNoOffset(PlayerPedId(), tx, ty, z + 0.5, false, false, false)
            ok = true break
        end
    end
    if not ok then SetEntityCoordsNoOffset(PlayerPedId(), dest.x, dest.y, dest.z + 1.0, false, false, false) end
    -- charge partial fare or full depending on design (here partial passed fare)
    TriggerServerEvent('qb-ai-taxi:server:chargePlayer', fare, payment)
    if activeRide and activeRide.driver and DoesEntityExist(activeRide.driver) then DeleteEntity(activeRide.driver) end
    if activeRide and activeRide.vehicle and DoesEntityExist(activeRide.vehicle) then DeleteVehicle(activeRide.vehicle) end
    activeRide = nil
    SendNUIMessage({ action='clearHUD' })
    if Config.EnableFadeTransition then Wait(500); DoScreenFadeIn(800) end
    notify('Taxi got lost — you have been teleported to the destination.')
end)

RegisterNetEvent('qb-ai-taxi:client:notify', function(text)
    notify(text)
end)

RegisterNetEvent('qb-ai-taxi:client:paymentFailed', function()
    if not activeRide then return end
    if activeRide.driver and DoesEntityExist(activeRide.driver) then
        DeleteEntity(activeRide.driver)
    end
    if activeRide.vehicle and DoesEntityExist(activeRide.vehicle) then
        DeleteVehicle(activeRide.vehicle)
    end
    activeRide = nil
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'hideUI' })
        
        -- Clean up active ride
        if activeRide then
            if activeRide.driver and DoesEntityExist(activeRide.driver) then
                DeleteEntity(activeRide.driver)
            end
            if activeRide.vehicle and DoesEntityExist(activeRide.vehicle) then
                DeleteVehicle(activeRide.vehicle)
            end
            activeRide = nil
        end
        
        sLog('Resource stopped - cleanup complete')
    end
end)
