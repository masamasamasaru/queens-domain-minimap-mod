from pathlib import Path
from lupa import LuaRuntime
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
logs={}; timers={};clock=0;onGameThread=true;traces=0;damages={};fxCreated=0
print=function(s) logs[#logs+1]=s end
ExecuteWithDelay=function(ms,fn) timers[#timers+1]=fn end
ExecuteInGameThread=function(fn) onGameThread=true;fn();onGameThread=false end
FName=function(s) return s end
local function base(t) t.IsValid=function() return true end;return t end
local particleType=base({}); local niagaraType=base({})
local lightning=base({IsA=function(self,c) return c==niagaraType end, GetFullName=function() return 'NiagaraSystem /Game/ElecGun/Trail' end})
local explosion=base({IsA=function(self,c) return c==particleType end, GetFullName=function() return 'ParticleSystem /Game/Rocket/Explosion' end})
local fx=base({Deactivate=function() end,K2_DestroyComponent=function() end})
local function enemy(id)
 return base({GetAddress=function() return id end,GetFullName=function() return 'Enemy '..id end,
 damageable=true,TryApplyDamage=function(self,hit,damage,owner,out,pos,isValid)
  assert(onGameThread); damages[id]=(damages[id] or 0)+damage.DamageAmount;return true end})
end
a=enemy(10); b=enemy(20); c=enemy(30); wall=base({GetAddress=function() return 40 end})
local function hit(t,time)
 return {Actor={get=function() return t end},Time=time,ImpactPoint={X=time*100,Y=0,Z=0},bBlockingHit=true}
end
hits={hit(a,0.1),hit(a,0.15),hit(b,0.3)}
splashHits={hit(a,0.1),hit(c,0.2),hit(c,0.3)}
sys=base({
 DoesImplementInterface=function(self,t) return t.damageable==true end,
 BoxTraceMultiForObjects=function(self,owner,from,to,half,rot,queries,complex,ignore,debug,out)
  assert(onGameThread); assert(half.Y==250 and half.Z==90); traces=traces+1
  local mask={};for _,q in ipairs(queries) do mask[q]=true end
  assert(mask[0] and mask[1] and mask[2] and mask[3] and mask[7])
  for i,h in ipairs(hits) do out[i]={get=function() return h end} end
 end,
 SphereTraceMultiForObjects=function(self,owner,from,to,radius,queries,complex,ignore,debug,out)
  assert(radius==250);for i,h in ipairs(splashHits) do out[i]={get=function() return h end} end
 end,
 LineTraceSingleForObjects=function(self,owner,from,to,queries) assert(queries[1]==0);return false end,
 K2_ClearTimer=function() end})
gs=base({GetTimeSeconds=function() return clock end,
 SpawnEmitterAtLocation=function() fxCreated=fxCreated+1;return fx end})
niagara=base({SpawnSystemAttached=function() fxCreated=fxCreated+1;return fx end})
StaticFindObject=function(path)
 if path=='/Script/Engine.Default__KismetSystemLibrary' then return sys end
 if path=='/Script/Engine.Default__GameplayStatics' then return gs end
 if path=='/Script/Niagara.Default__NiagaraFunctionLibrary' then return niagara end
 if path=='/Script/Niagara.NiagaraSystem' then return niagaraType end
 if path=='/Script/Engine.ParticleSystem' then return particleType end
 if path:find('ElecGun_Projectile_C',1,true) then
  return base({GetCDO=function() return {Trail=base({Asset=lightning,IsA=function() return false end})} end}) end
 if path:find('RocketLauncher_Projectile_C',1,true) then
  return base({GetCDO=function() return {ImpactFX=explosion} end}) end
 return base({})
end
ForEachUObject=function() error('FX fallback not expected') end
owner=base({GetAddress=function() return 1 end,AttackObjectChannel={0,3,7}})
local movement=base({SetComponentTickEnabled=function() end,StopMovementImmediately=function() end})
actor=base({GetAddress=function() return 2 end,RootComponent=base({}),ProjectileMovement=movement,Damage={DamageAmount=50},
 SetActorTickEnabled=function(self,x) assert(x==false) end,
 SetActorEnableCollision=function(self,x) assert(x==false) end,
 SetActorScale3D=function(self,s) assert(s.Y==3 and s.Z==1.6) end,
 K2_GetActorLocation=function() return {X=0,Y=0,Z=0} end,
 K2_SetActorLocation=function(self,pos) self.pos=pos end,
 K2_DestroyActor=function(self) self.dead=true end})
config={waveWidthScale=3,waveHeightScale=1.6,waveHalfWidth=250,waveHalfHeight=90,
 waveLifetime=3,waveDamage=50,waveSplashDamage=25,waveSplashRadius=250}
function nextTick(dt)
 clock=clock+dt;local fn=table.remove(timers,1); assert(fn);onGameThread=false;fn()
end
''')
storm=lua.execute((Path(__file__).resolve().parents[1] / 'QueensDomainArsenal/Scripts/stormwave.lua').read_text())
lua.globals().storm=storm
lua.execute('''
storm.attach(actor,owner,{Pitch=0,Yaw=0,Roll=0},{X=4000,Y=0,Z=0},config)
assert(#timers==1 and fxCreated==1)
nextTick(0.1)
assert(damages[10]==50 and damages[20]==50 and damages[30]==25)
assert(actor.pos.X==400 and not actor.dead)
assert(fxCreated==3) -- lightning + explosions for two direct-hit enemies
nextTick(0.1)
assert(damages[10]==50 and damages[20]==50 and damages[30]==25)
assert(fxCreated==3 and actor.pos.X==800)
local old=traces;nextTick(0);assert(traces==old) -- paused world
-- World geometry blocks anything beyond it, but an enemy before it is hit.
hits={ {Actor={get=function() return wall end},Time=0.1,ImpactPoint={X=900,Y=0,Z=0},bBlockingHit=true},
 {Actor={get=function() return c end},Time=0.2,ImpactPoint={X=1000,Y=0,Z=0},bBlockingHit=true} }
nextTick(0.1)
assert(actor.dead and #timers==0 and damages[30]==25)
assert(actor.Damage.DamageAmount==50)
assert(table.concat(logs):find('contacts=',1,true) and table.concat(logs):find('accepted=3',1,true))
assert(not table.concat(logs):find('error',1,true))
-- A new wave has its own hit set. Static walls also occlude splash damage.
onGameThread=true
actor.dead=nil
hits={ {Actor={get=function() return a end},Time=0.1,ImpactPoint={X=10,Y=0,Z=0},bBlockingHit=true} }
sys.LineTraceSingleForObjects=function() return true end
storm.attach(actor,owner,{Pitch=0,Yaw=0,Roll=0},{X=4000,Y=0,Z=0},config)
nextTick(0.1)
assert(damages[10]==100 and damages[30]==25)
local oldTraces=traces;nextTick(4)
assert(actor.dead and #timers==0 and traces==oldTraces)
-- A failed damage call restores the shared amount and cleans up this wave.
onGameThread=true;actor.dead=nil
a.TryApplyDamage=function() error('mock damage failure') end
storm.attach(actor,owner,{Pitch=0,Yaw=0,Roll=0},{X=4000,Y=0,Z=0},config)
nextTick(0.1)
assert(actor.dead and #timers==0 and actor.Damage.DamageAmount==50)
assert(table.concat(logs):find('Storm update error:',1,true))
''')
print('PASS: expanded swept collision, two-enemy piercing, per-enemy direct/splash deduplication, FX, paused time, wall occlusion, scheduler and damage restoration (mock API).')
