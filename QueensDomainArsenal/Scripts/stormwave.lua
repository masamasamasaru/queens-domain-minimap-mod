-- Storm wave 0.2.2. Own swept collision/damage so enemy impact cannot destroy the wave.
local M={}
local waves,pending={},false
local warned={}
local effects
local function log(s) print('[QDArsenal] '..s..'\n') end
local function valid(o) return o and o:IsValid() end
local function warn(key,s) if not warned[key] then warned[key]=true;log(s) end end
local function copy(v) return {X=v.X,Y=v.Y,Z=v.Z} end
local function obj(v)
    if not v then return end
    local ok,value=pcall(function() return v:get() end)
    if ok then return value end
    return v
end
local function effectType(asset)
    if not valid(asset) then return end
    local n=StaticFindObject('/Script/Niagara.NiagaraSystem')
    if valid(n) and asset:IsA(n) then return 'niagara' end
    local p=StaticFindObject('/Script/Engine.ParticleSystem')
    if valid(p) and asset:IsA(p) then return 'particle' end
end
local function resolveEffects()
    if effects then return effects end
    effects={}
    local function fromDefault(path,field)
        local ok,result=pcall(function()
            local c=StaticFindObject(path)
            if not valid(c) then return end
            local o=c:GetCDO()[field]
            if effectType(o) then return o end
            if valid(o) then
                for _,k in ipairs({'Asset','Template'}) do
                    local success,a=pcall(function() return o[k] end)
                    if success and effectType(a) then return a end
                end
            end
        end)
        if ok then return result end
    end
    effects.lightning=fromDefault('/Game/Items/Weapons/ElecGun/ElecGun_Projectile.ElecGun_Projectile_C','Trail')
    effects.explosion=fromDefault('/Game/Items/Weapons/RocketLauncher/RocketLauncher_Projectile.RocketLauncher_Projectile_C','ImpactFX')
    if not effects.lightning or not effects.explosion then
        -- Once only. Prefer the exact weapon templates; fall back to loaded game FX.
        ForEachUObject(function(o)
            if not valid(o) then return end
            local name=o:GetFullName():lower()
            if not name:find('/game/',1,true) then return end
            local electric=name:find('lightning',1,true) or (name:find('elec',1,true)
                and (name:find('trail',1,true) or name:find('beam',1,true) or name:find('loop',1,true)))
            local explosive=name:find('explos',1,true) or (name:find('rocket',1,true)
                and (name:find('impact',1,true) or name:find('burst',1,true) or name:find('hit',1,true)))
            if ((not effects.lightning and electric) or (not effects.explosion and explosive)) and effectType(o) then
                if not effects.lightning and electric then effects.lightning=o end
                if not effects.explosion and explosive then effects.explosion=o end
            end
        end)
    end
    for _,key in ipairs({'lightning','explosion'}) do
        if effects[key] then log('Storm FX '..key..': '..effects[key]:GetFullName())
        else warn(key,'Storm FX unavailable: '..key..' (collision and damage still enabled)') end
    end
    return effects
end
local function spawnFX(asset,s,position,attached)
    if not asset then return end
    local ok,err=pcall(function()
        local kind=effectType(asset)
        local zero={X=0,Y=0,Z=0}
        local rot={Pitch=0,Yaw=0,Roll=0}
        local fx
        if kind=='niagara' then
            local lib=StaticFindObject('/Script/Niagara.Default__NiagaraFunctionLibrary')
            if attached then
                fx=lib:SpawnSystemAttached(asset,s.actor.RootComponent,FName('None'),zero,rot,0,true,true,0,true)
            else
                fx=lib:SpawnSystemAtLocation(s.owner,asset,position,rot,{X=1.5,Y=1.5,Z=1.5},true,true,0,true)
            end
        elseif kind=='particle' then
            if attached then
                fx=s.gs:SpawnEmitterAttached(asset,s.actor.RootComponent,FName('None'),zero,rot,{X=1,Y=1,Z=1},0,true,0,true)
            else fx=s.gs:SpawnEmitterAtLocation(s.owner,asset,position,rot,{X=1.5,Y=1.5,Z=1.5},true,0,true) end
        end
        if not valid(fx) then error('FX component was not created') end
        if attached then s.lightning=fx end
    end)
    if not ok then warn('fx:'..tostring(attached),'Storm FX error: '..tostring(err)) end
end
local function destroy(s)
    if s.done then return end
    s.done=true
    log('Storm wave ended: traces='..s.traceCount..'; contacts='..s.contactCount..'; damage calls='..s.damageCount..'; accepted='..s.acceptedCount)
    if valid(s.lightning) then pcall(function() s.lightning:Deactivate();s.lightning:K2_DestroyComponent(s.actor) end) end
    if valid(s.actor) then pcall(function() s.actor:K2_DestroyActor() end) end
end
local function targetFor(s,hit)
    local actor=obj(hit.Actor)
    local component=obj(hit.Component)
    for _,t in ipairs({actor or false,component or false}) do
        if t and valid(t) and t:GetAddress()~=s.owner:GetAddress() and t:GetAddress()~=s.actor:GetAddress()
            and s.sys:DoesImplementInterface(t,s.damageInterface) then return t,actor end
    end
end
local function apply(s,target,hit,amount)
    local old=s.actor.Damage.DamageAmount
    s.actor.Damage.DamageAmount=amount
    local result={}
    local ok,success=pcall(function()
        return target:TryApplyDamage(hit,s.actor.Damage,s.owner,result,hit.ImpactPoint,true)
    end)
    s.actor.Damage.DamageAmount=old
    if not ok then error('TryApplyDamage: '..tostring(success)) end
    s.damageCount=s.damageCount+1
    if success==true then s.acceptedCount=s.acceptedCount+1 end
    return success==true
end
local color={R=0,G=0,B=0,A=0}
local function trace(s,a,b,radius)
    local hits={}
    local ignore={s.owner,s.actor}
    if radius then
        s.sys:SphereTraceMultiForObjects(s.owner,a,b,radius,s.queries,false,ignore,0,hits,true,color,color,0)
    else
        s.sys:BoxTraceMultiForObjects(s.owner,a,b,s.half,s.rotation,s.queries,false,ignore,0,hits,true,color,color,0)
    end
    -- UE4SS 4.0.0 returns each OutHits element as LocalUnrealParam, not FHitResult.
    -- Unwrap BEFORE sorting, reading Actor/Component, or passing it to a damage call.
    local resolved={}
    for _,raw in ipairs(hits) do
        local h=obj(raw)
        if not h or type(h.Time)~='number' then error('Unexpected trace hit format after get()') end
        resolved[#resolved+1]=h
    end
    s.traceCount=s.traceCount+1
    s.contactCount=s.contactCount+#resolved
    return resolved
end
local function explode(s,hit,directKey)
    spawnFX(s.fx.explosion,s,copy(hit.ImpactPoint),false)
    if s.config.waveSplashDamage<=0 then return end
    for _,h in ipairs(trace(s,copy(hit.ImpactPoint),copy(hit.ImpactPoint),s.config.waveSplashRadius)) do
        local t,actor=targetFor(s,h)
        if t then
            local key=valid(actor) and actor:GetAddress() or t:GetAddress()
            if key~=directKey and not s.direct[key] and not s.splash[key] then
                local obstruction={}
                local wall=s.sys:LineTraceSingleForObjects(s.owner,copy(hit.ImpactPoint),copy(h.ImpactPoint),{0},false,{s.owner,s.actor},0,obstruction,true,color,color,0)
                if not wall then
                s.splash[key]=true
                -- Splash does not cause another explosion. At most once per target per wave.
                apply(s,t,h,s.config.waveSplashDamage)
                end
            end
        end
    end
end
local function step(s)
    if not valid(s.owner) or not valid(s.actor) then return false end
    local now=s.gs:GetTimeSeconds(s.owner)
    if now-s.created>=s.config.waveLifetime then return false end
    local dt=now-s.lastTime
    if dt<=0 then return true end
    s.lastTime=now
    local nextPos={X=s.pos.X+s.velocity.X*dt,Y=s.pos.Y+s.velocity.Y*dt,Z=s.pos.Z+s.velocity.Z*dt}
    local hits=trace(s,s.pos,nextPos)
    table.sort(hits,function(a,b) return a.Time<b.Time end)
    for _,h in ipairs(hits) do
        local target,actor=targetFor(s,h)
        if target then
            local key=valid(actor) and actor:GetAddress() or target:GetAddress()
            if not s.direct[key] then
                s.direct[key]=true
                local accepted=apply(s,target,h,s.config.waveDamage)
                explode(s,h,key)
                log('Storm direct hit: '..target:GetFullName()..'; damage accepted='..tostring(accepted))
            end
            -- Continue through enemies. Never call the original impact/destruction event.
        elseif h.bBlockingHit then
            spawnFX(s.fx.explosion,s,copy(h.ImpactPoint),false)
            return false
        end
    end
    s.actor:K2_SetActorLocation(nextPos,false,{},true)
    s.pos=nextPos
    return true
end
local schedule
local function tick()
    pending=false
    for i=#waves,1,-1 do
        local s=waves[i]
        local ok,keep=pcall(step,s)
        if not ok then log('Storm update error: '..tostring(keep)) end
        if not ok or not keep then destroy(s);table.remove(waves,i) end
    end
    if #waves>0 then schedule() end
end
schedule=function()
    if pending then return end
    pending=true
    ExecuteWithDelay(16,function() ExecuteInGameThread(tick) end)
end
function M.attach(actor,owner,rotation,velocity,config)
    local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
    local gs=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    local damageInterface=StaticFindObject('/Script/FBAttributes.FB_DamageableInterface')
    if not valid(sys) or not valid(gs) or not valid(damageInterface) then error('Storm libraries/interface unavailable') end
    -- Disable built-in movement, collision and Blueprint damage timers. Own traces handle hits.
    actor:SetActorTickEnabled(false)
    actor:SetActorEnableCollision(false)
    actor.ProjectileMovement:SetComponentTickEnabled(false)
    actor.ProjectileMovement:StopMovementImmediately()
    for _,name in ipairs({'TickRate','TickLast','Damage Trace','UpdateCollision'}) do sys:K2_ClearTimer(actor,name) end
    actor:SetActorScale3D({X=1,Y=config.waveWidthScale,Z=config.waveHeightScale})
    local queries,seen={},{}
    local function add(q) if type(q)=='number' and q>=0 and q<32 and not seen[q] then seen[q]=true;queries[#queries+1]=q end end
    -- Use the game's attack object channels plus world geometry for wall occlusion.
    local channels=owner.AttackObjectChannel
    if channels then for i=1,#channels do add(obj(channels[i])) end end
    -- EObjectTypeQuery enumerators are ZERO-based: WorldStatic=0, WorldDynamic=1, Pawn=2.
    add(0);add(1);add(2)
    warn('queries','Storm trace object types (zero-based): '..table.concat(queries,','))
    local now=gs:GetTimeSeconds(owner)
    local fxOk,fx=pcall(resolveEffects)
    if not fxOk then warn('fxlookup','Storm FX lookup error: '..tostring(fx));fx={} end
    local s={actor=actor,owner=owner,rotation=rotation,velocity=velocity,config=config,
        sys=sys,gs=gs,damageInterface=damageInterface,queries=queries,
        pos=copy(actor:K2_GetActorLocation()),created=now,lastTime=now,
        half={X=25,Y=config.waveHalfWidth,Z=config.waveHalfHeight},direct={},splash={},fx=fx,traceCount=0,contactCount=0,damageCount=0,acceptedCount=0}
    spawnFX(s.fx.lightning,s,s.pos,true)
    waves[#waves+1]=s
    schedule()
    log('Storm wave active: width='..(config.waveHalfWidth*2)..'; enemy piercing ON; wall stop ON')
end
return M
