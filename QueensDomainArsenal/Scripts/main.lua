-- Combat prototype 0.2.2. Existing-gun modifier + independent sword-wave ability.
-- NOT new inventory weapons or replacement models. UE4SS 4.0.0 / UE4.27.
local GUN='/Game/Items/Weapons/GunBase_WeaponScript.GunBase_WeaponScript_C'
local WAVE='/Game/Items/Weapons/FlyingSwordTrue/HiddenSword_ArcProjectile.HiddenSword_ArcProjectile_C'
local storm=require('stormwave')
local config={fireDelay=0.075,waveDamage=50,waveSpeed=4000,waveLifetime=3,waveCooldown=0.7,
    waveWidthScale=3,waveHeightScale=1.6,waveHalfWidth=250,waveHalfHeight=90,
    waveSplashDamage=25,waveSplashRadius=250}
local gun, originalAuto, waveReady = nil, nil, true
local hooked,handlers={},{}
local function log(s) print('[QDArsenal] '..s..'\n') end
local function valid(o) return o and o:IsValid() end
local function player()
    for _,pc in ipairs(FindAllOf('PlayerController') or {}) do
        if valid(pc) and pc:IsLocalController() then
            local p=pc:K2_GetPawn()
            if valid(p) then return p end
        end
    end
end
local function blocked(p)
    return valid(p.CurrentGameMenu) or valid(p.CurrentShopMenu) or valid(p.CurrentSaveMenu)
        or p.WeaponsArePutAway or p.ActivelyResettingFromDeathPit
end
local function matches(ctx)
    if not valid(gun) then return false end
    local w=ctx:get()
    if not valid(w) or w:GetAddress()~=gun:GetAddress() then return false end
    local p=w.PlayerRef
    return valid(p) and valid(p.CurrentInHandWeapon)
        and p.CurrentInHandWeapon:GetAddress()==w:GetAddress() and not blocked(p)
end
local function attach(method,fn)
    handlers[method]=fn
    local path=GUN..':'..method
    local ok,err=pcall(RegisterHook,path,fn)
    hooked[method]=ok
    if ok then log('Hook ready: '..method)
    else log('Hook failed: '..method..': '..tostring(err)) end
end
attach('GetFireDelay',function(ctx)
    if matches(ctx) then return config.fireDelay end
end)
attach('GetCellConsumptionPerShot',function(ctx,secondary,consumption)
    if matches(ctx) then consumption:set(0.0) end
end)
attach('CanConsumeCharge',function(ctx,canConsume)
    if matches(ctx) then canConsume:set(true) end
end)
attach('TryConsumeCharge',function(ctx,delay,secondary,consumed)
    if matches(ctx) then consumed:set(true) end
end)
local function restore()
    if valid(gun) and originalAuto~=nil then gun.FullAuto=originalAuto end
    gun,originalAuto=nil,nil
end
local function toggleGun()
    if gun then restore(); log('Rapid-fire mode OFF'); return end
    for _,method in ipairs({'GetFireDelay','GetCellConsumptionPerShot','CanConsumeCharge','TryConsumeCharge'}) do
        if not hooked[method] then attach(method,handlers[method]) end
        if not hooked[method] then log('Cannot enable: missing hook '..method); return end
    end
    local p=player()
    if not p or blocked(p) then log('Load gameplay and close menus first'); return end
    local w=p.CurrentInHandWeapon
    local class=StaticFindObject(GUN)
    if not valid(w) or not valid(class) or not w:IsA(class) then
        log('Equip an existing gun first; current weapon is not GunBase'); return
    end
    if type(w.FullAuto)~='boolean' then log('FullAuto property is not a boolean'); return end
    originalAuto=w.FullAuto
    -- Set the property before enabling callbacks, so a failed assignment leaves mode off.
    w.FullAuto=true
    gun=w
    log('Rapid-fire mode ON: '..w:GetFullName()..'; delay='..config.fireDelay)
end
local function fireWave()
    if not waveReady then return end
    local p=player()
    if not p or blocked(p) then log('Load gameplay and close menus first'); return end
    local class=StaticFindObject(WAVE)
    if not valid(class) then log('Wave class is not loaded; no projectile spawned'); return end
    local camera=p.FirstPersonCamera
    if not valid(camera) then log('First-person camera unavailable'); return end
    local loc=camera:K2_GetComponentLocation()
    local rot=camera:K2_GetComponentRotation()
    local pitch,yaw=math.rad(rot.Pitch),math.rad(rot.Yaw)
    local dir={X=math.cos(pitch)*math.cos(yaw),Y=math.cos(pitch)*math.sin(yaw),Z=math.sin(pitch)}
    local transform={
        Rotation={X=math.cos(math.rad(rot.Roll)/2)*math.sin(pitch/2)*math.sin(yaw/2)-math.sin(math.rad(rot.Roll)/2)*math.cos(pitch/2)*math.cos(yaw/2),
                  Y=-math.cos(math.rad(rot.Roll)/2)*math.sin(pitch/2)*math.cos(yaw/2)-math.sin(math.rad(rot.Roll)/2)*math.cos(pitch/2)*math.sin(yaw/2),
                  Z=math.cos(math.rad(rot.Roll)/2)*math.cos(pitch/2)*math.sin(yaw/2)-math.sin(math.rad(rot.Roll)/2)*math.sin(pitch/2)*math.cos(yaw/2),
                  W=math.cos(math.rad(rot.Roll)/2)*math.cos(pitch/2)*math.cos(yaw/2)+math.sin(math.rad(rot.Roll)/2)*math.sin(pitch/2)*math.sin(yaw/2)},
        Translation={X=loc.X+dir.X*100,Y=loc.Y+dir.Y*100,Z=loc.Z+dir.Z*100},
        Scale3D={X=1,Y=1,Z=1}}
    local velocity={X=dir.X*config.waveSpeed,Y=dir.Y*config.waveSpeed,Z=dir.Z*config.waveSpeed}
    local gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not valid(gs) then log('GameplayStatics unavailable'); return end
    local projectile
    local function spawnBase()
        -- Set damage/velocity before BeginPlay; do not modify the shared class default.
        -- Enum 2 = AdjustIfPossibleButDontSpawnIfColliding (avoid spawning inside walls).
        projectile=gs:BeginDeferredActorSpawnFromClass(p,class,transform,2,p)
        if not valid(projectile) then error('Deferred spawn failed (possibly obstructed)') end
        projectile.Instigator=p
        projectile.Damage.DamageAmount=config.waveDamage
        projectile.StartingVelocity=velocity
        projectile.STartingVel=velocity
        gs:FinishSpawningActor(projectile,transform)
        if not valid(projectile) then error('Projectile invalid after BeginPlay') end
        local movement=projectile.ProjectileMovement
        if not valid(movement) then error('ProjectileMovement unavailable') end
        movement.Velocity=velocity
        movement.ProjectileGravityScale=0
        projectile:SetLifeSpan(config.waveLifetime)
    end
    local enhanced=false
    local ok,err=pcall(function()
        spawnBase()
        local success,message=pcall(storm.attach,projectile,p,rot,velocity,config)
        if success then enhanced=true;return end
        log('Storm setup error: '..tostring(message)..'; recreating basic wave')
        -- A partially modified projectile is not reusable: replace it with a fresh base wave.
        if valid(projectile) then projectile:K2_DestroyActor() end
        projectile=nil
        spawnBase()
    end)
    if not ok then
        if valid(projectile) then pcall(function() projectile:K2_DestroyActor() end) end
        log('Wave error: '..tostring(err)); return
    end
    waveReady=false
    ExecuteWithDelay(math.floor(config.waveCooldown*1000),function() waveReady=true end)
    if enhanced then log('Storm wave spawned; damage='..config.waveDamage)
    else log('Basic wave fallback spawned; storm features unavailable for this shot') end
end
local function onGameThread(fn)
    ExecuteInGameThread(function()
        local ok,err=pcall(fn)
        if not ok then log('Action error: '..tostring(err)) end
    end)
end
RegisterKeyBind(Key.F6,function() onGameThread(toggleGun) end)
RegisterKeyBind(Key.F7,function() onGameThread(fireWave) end)
-- Restore a temporary gun property across respawn/load. No persistent stats are edited.
local ok,err=pcall(function()
    RegisterHook('/Script/Engine.PlayerController:ClientRestart',function() restore() end)
end)
if not ok then log('Respawn cleanup hook unavailable: '..tostring(err)) end
log('Combat prototype 0.2.2 loaded. F6: current gun rapid-fire toggle. F7: wave. No new weapon items/models yet.')
