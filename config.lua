Config = {}

-- Core & models
Config.TaxiModel = 'taxi'
Config.DriverModel = 'A_M_M_Indian_01'
Config.TaxiSpeed = 120.0  -- Increased for faster taxi service
Config.DrivingStyle = 2883621 -- Ignores traffic lights and drives aggressively through obstacles

-- Fare settings
Config.Fare = {
    BaseFare = 50,       -- base fare in $
    RatePerKm = 8.0,     -- $ per km
    TimeoutRefundPercent = 50, -- percent refunded on timeout
    AverageSpeedKmH = 80 -- used for ETA preview
}

-- Timeout & arrival
Config.TeleportOnTimeout = true
Config.TimeoutSeconds = 240 -- seconds before teleport
Config.ArrivalRadius = 25.0 -- meters arrival radius (default)
Config.SafeSpawnOffset = 5.0 -- safe teleport offset meters
Config.SpawnDistance = 3.0 -- spawn distance in front of player

-- Anti-stuck
Config.AntiStuck = {
    Enabled = true,
    CheckInterval = 2000, -- ms between checks (reduced from 5000 for faster detection)
    MaxAttempts = 3,
    SlowThreshold = 2.0, -- m movement threshold considered stuck
    RepositionDistance = 12.0 -- meters to attempt reposition forward
}

-- Cooldowns (seconds)
Config.Cooldowns = {
    Watch = 600,   -- 10 minutes
    Skip = 1200,   -- 20 minutes
    Global = 300,  -- 5 minutes between any uses
}

-- UI / HUD
Config.ShowETA = true
Config.ShowFarePopup = true
Config.WatchCooldown = Config.Cooldowns.Watch

-- Effects & sounds
Config.EnableFadeTransition = true
Config.PlayArrivalSound = true
Config.PlayFadeSound = true
Config.SoundEffects = true
Config.AnimatedPopups = true

-- Debug
Config.Debug = true

-- Preset locations (dynamic editable)
Config.PresetLocations = {
    { name = "Legion Square", coords = vector3(239.63, -781.33, 30.63) },
    { name = "Sandy Shores", coords = vector3(1862.34, 3687.56, 33.67) },
    { name = "Paleto Bay", coords = vector3(-208.34, 6218.13, 31.49) },
    { name = "PDM", coords = vector3(-1038.05, -1529.39, 4.98) },
}
