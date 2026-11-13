-- Experimental UE4SS HUD mod, diagnostic build 0.2. No game assets are redistributed.
local geometry = require('geometry')
local config = {
    size = 240, margin = 24, radius = 6000, -- Unreal units; normally cm
    sampleDistance = 80, teleportDistance = 20000,
    maxPoints = 1500, floorTolerance = 350,
}
local trail, lastWorld, previous = {}, nil, nil
local enabled, errors, rendered = true, 0, false
local cyan={R=0.15,G=0.9,B=1,A=1}
local gray={R=0.3,G=0.35,B=0.4,A=0.65}
local white={R=1,G=1,B=1,A=1}
local function valid(o) return o and o:IsValid() end
local function log(s) print('[QueensDomainMinimap] '..s..'\n') end
local notes = {}
local function note(key,message)
    if not notes[key] then notes[key]=true; log(message) end
end
log('Build 0.2 loaded')
local function reset() trail={}; previous=nil end
local function line(canvas,x1,y1,x2,y2,color,width)
    canvas:K2_DrawLine({X=x1,Y=y1},{X=x2,Y=y2},width or 1,color)
end
local function draw(context, sizeX, sizeY)
    if not enabled then return end
    local hud=context:get()
    if not valid(hud) then note('hud','Skipped: invalid HUD'); return end
    local pc=hud:GetOwningPlayerController()
    if not valid(pc) then note('pc','Skipped: no owning controller'); return end
    if not pc:IsLocalController() then note('remote','Skipped: non-local controller'); return end
    local pawn=pc:K2_GetPawn()
    local canvas=hud.Canvas
    if not valid(pawn) then note('pawn','Skipped: no pawn'); return end
    if not valid(canvas) then note('canvas','Skipped: no Canvas in HUD callback'); return end
    local world=pawn:GetLevel()
    if not valid(world) then note('level','Skipped: no level'); return end
    local worldKey=world:GetAddress()
    if worldKey~=lastWorld then reset(); lastWorld=worldKey end
    local p=pawn:K2_GetActorLocation()
    local pos={X=p.X,Y=p.Y,Z=p.Z}
    local yaw=pawn:K2_GetActorRotation().Yaw*math.pi/180
    local dx,dy=0,0
    if previous then dx=pos.X-previous.X; dy=pos.Y-previous.Y end
    local distance=math.sqrt(dx*dx+dy*dy)
    if previous and distance>config.teleportDistance then reset() end
    if not previous or distance>=config.sampleDistance then
        trail[#trail+1]=pos; previous=pos
        if #trail>config.maxPoints then table.remove(trail,1) end
    end
    local sx,sy=sizeX:get(),sizeY:get()
    if sx<160 or sy<160 then note('size','Skipped: viewport too small'); return end
    local size=math.min(config.size,sx-2*config.margin,sy-2*config.margin)
    local half=size/2
    local cx,cy=sx-config.margin-half,config.margin+half
    -- The map is fixed: +X right, +Y up. No assumption about in-game north.
    local function segment(a,b,color,width)
        local ax,ay=geometry.project(a,pos,config.radius,half)
        local bx,by=geometry.project(b,pos,config.radius,half)
        local x1,y1,x2,y2=geometry.clip(ax,ay,bx,by,half)
        if x1 then line(canvas,cx+x1,cy+y1,cx+x2,cy+y2,color,width) end
    end
    for i=-2,2 do
        local offset=i*half/2
        line(canvas,cx-half,cy+offset,cx+half,cy+offset,gray)
        line(canvas,cx+offset,cy-half,cx+offset,cy+half,gray)
    end
    for i=2,#trail do
        local a,b=trail[i-1],trail[i]
        if math.abs(a.Z-pos.Z)<=config.floorTolerance and math.abs(b.Z-pos.Z)<=config.floorTolerance then
            segment(a,b,cyan,2)
        end
    end
    if previous and (previous.X~=pos.X or previous.Y~=pos.Y) then
        segment(previous,pos,cyan,2)
    end
    line(canvas,cx-half,cy-half,cx+half,cy-half,white)
    line(canvas,cx+half,cy-half,cx+half,cy+half,white)
    line(canvas,cx+half,cy+half,cx-half,cy+half,white)
    line(canvas,cx-half,cy+half,cx-half,cy-half,white)
    local fx,fy=math.cos(yaw),-math.sin(yaw)
    local tx,ty=cx+fx*10,cy+fy*10
    local lx,ly=cx-fx*6-fy*5,cy-fy*6+fx*5
    local rx,ry=cx-fx*6+fy*5,cy-fy*6-fx*5
    line(canvas,tx,ty,lx,ly,white,2)
    line(canvas,lx,ly,rx,ry,white,2)
    line(canvas,rx,ry,tx,ty,white,2)
    if not rendered then rendered=true; log('First HUD frame drawn.') end
end
local hooks = {}
local function attach(path)
    if hooks[path] then return end
    local ok,pre,post=pcall(RegisterHook,path,function(context,sx,sy)
        note('event:'..path,'HUD event received: '..path)
        local success,message=pcall(draw,context,sx,sy)
        if not success then
            errors=errors+1
            if errors<=3 then log('Draw error: '..tostring(message)) end
            if errors>=3 then enabled=false; note('disabled','Disabled after repeated errors') end
        end
    end)
    if ok then
        hooks[path]={pre,post}
        log('HUD hook registered: '..path)
    else log('HUD hook failed: '..path..': '..tostring(pre)) end
end

local function inspect()
    local huds=FindAllOf('HUD') or {}
    log('HUD inspection: '..#huds..' instances')
    for _,hud in ipairs(huds) do
        if valid(hud) then
            log('HUD instance: '..hud:GetFullName())
            log('HUD bShowHUD: '..tostring(hud.bShowHUD))
            local class=hud:GetClass()
            -- A Blueprint override is a separate UFunction from the engine event.
            while valid(class) do
                local name=class:GetFullName():match('^[^ ]+ (.+)$')
                if name then
                    local path=name..':ReceiveDrawHUD'
                    local fn=StaticFindObject(path)
                    if valid(fn) then attach(path) end
                end
                class=class:GetSuperStruct()
            end
        end
    end
    log('Draw completed: '..tostring(rendered))
end

local pending=false
local function scheduleInspection()
    if pending then return end
    pending=true
    ExecuteWithDelay(3000,function()
        ExecuteInGameThread(function()
            pending=false
            local ok,err=pcall(inspect)
            if not ok then log('Inspection error: '..tostring(err)) end
        end)
    end)
end
attach('/Script/Engine.HUD:ReceiveDrawHUD')
local ok,err=pcall(function()
    RegisterHook('/Script/Engine.PlayerController:ClientRestart',function()
        scheduleInspection()
    end)
end)
if not ok then log('Restart hook failed: '..tostring(err)) end
scheduleInspection()
-- Async callbacks only queue work; UObject inspection runs on the game thread.
