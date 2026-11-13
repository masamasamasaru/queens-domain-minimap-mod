-- Read-only weapon API discovery for QueensDomain / UE4SS 4.0.0.
-- Does not spawn items, call attacks, or edit saves/properties.
local busy = false
local function log(s) print('[QDArsenalProbe] '..s..'\n') end
local function valid(o) return o and o:IsValid() end
local terms = {'weapon','projectile','inventory','combat','player','spell','throw','damage','equip','bullet','magic'}
local function relevant(name)
    name=name:lower()
    for _,term in ipairs(terms) do
        if name:find(term,1,true) then return true end
    end
    return false
end
local function inspect()
    log('BEGIN v0.2')
    local classType=StaticFindObject('/Script/CoreUObject.Class')
    if not valid(classType) then error('UClass type unavailable') end
    local classes, assets, seen = {}, {}, {}
    local structures, valueCount = {}, 0
    local function schema(p,depth)
        if depth>2 or not p:GetFullName():find('StructProperty ',1,true) then return end
        local st=p:GetStruct()
        if not valid(st) then return end
        local name=st:GetFullName()
        log('    STRUCT TYPE '..name)
        if structures[name] then return end
        structures[name]=true
        st:ForEachProperty(function(field)
            log('    STRUCT FIELD '..field:GetFullName())
            schema(field,depth+1)
        end)
    end
    local function values(o)
        if valueCount>=100 then return end
        valueCount=valueCount+1
        log('VALUES '..o:GetFullName())
        for _,key in ipairs({'GunFireRate','PrimaryEnergyConsumption','SecondaryEnergyConsumption',
            'MaxCharges','ChargeOverTime','AttackAnimSpeed','PrimaryAttackPower','SecondaryAttackPower',
            'PrimaryAttackForce','SecondaryAttackForce','Damage','StartingVelocity','STartingVel',
            'HitMultiplier','InitialSpeed','MaxSpeed','ProjectileGravityScale'}) do
            local ok,value=pcall(function() return o[key] end)
            if ok and value~=nil then
                local t=type(value)
                if t=='number' or t=='boolean' or t=='string' then
                    log('  VALUE '..key..'='..tostring(value))
                end
            end
        end
    end
    local function addClass(c)
        if not valid(c) then return end
        local name=c:GetFullName()
        if seen[name] then return end
        seen[name]=true
        if #classes<400 then classes[#classes+1]=c end
    end
    -- Include the actual possessed pawn even if its name lacks a weapon keyword.
    for _,pc in ipairs(FindAllOf('PlayerController') or {}) do
        local ok,err=pcall(function()
            if valid(pc) and pc:IsLocalController() then
                local pawn=pc:K2_GetPawn()
                if valid(pawn) then
                    log('LOCAL PAWN '..pawn:GetFullName())
                    local c=pawn:GetClass()
                    for _=1,10 do
                        if not valid(c) then break end
                        addClass(c); c=c:GetSuperStruct()
                    end
                end
            end
        end)
        if not ok then log('PLAYER INSPECTION ERROR '..tostring(err)) end
    end
    ForEachUObject(function(o)
        if not valid(o) then return end
        local name=o:GetFullName()
        -- Restrict to game assets and game-style native types, not engine internals.
        local game=name:find('/Game/',1,true) or name:find('.FS_',1,true) or name:find('.FB_',1,true)
        if name:find('AnimBlueprintGeneratedClass ',1,true) or name:find('WidgetBlueprintGeneratedClass ',1,true)
            or name:find('/StatusEffectVisualizers/',1,true) or name:find('/Game/UI/',1,true)
            or name:find('/Game/Enemies/',1,true) then return end
        if not game then return end
        local c=o:GetClass()
        local cn=valid(c) and c:GetFullName() or ''
        if cn:find('FS_WeaponStats',1,true) or cn:find('FS_ThrowingWeaponStats',1,true)
            or cn:find('ArcProjectile',1,true) then values(o) end
        if not relevant(name) then return end
        if o:IsA(classType) then addClass(o)
        elseif #assets<200 and (name:find('DataTable ',1,true) or name:find('DataAsset ',1,true)) then
            assets[#assets+1]=name
        end
    end)
    table.sort(classes,function(a,b) return a:GetFullName()<b:GetFullName() end)
    for _,c in ipairs(classes) do
        local ok,err=pcall(function()
            log('CLASS '..c:GetFullName())
            local fields=0
            c:ForEachProperty(function(p)
                fields=fields+1; log('  FIELD '..p:GetFullName()); schema(p,0)
                if fields>=1500 then log('  FIELD LIMIT'); return true end
            end)
            local functions=0
            c:ForEachFunction(function(fn)
                functions=functions+1; log('  FUNCTION '..fn:GetFullName())
                local params=0
                fn:ForEachProperty(function(p)
                    local n=p:GetFullName():match(':([^:]+)$') or ''
                    -- Blueprint function fields include locals, not only parameters.
                    if n:match('^CallFunc_') or n:match('^K2Node_') or n:match('^Temp_')
                        or n:match('^K2Node') then return end
                    params=params+1; log('    FNFIELD '..p:GetFullName()); schema(p,0)
                    if params>=100 then return true end
                end)
                if functions>=1500 then log('  FUNCTION LIMIT'); return true end
            end)
        end)
        if not ok then log('CLASS INSPECTION ERROR '..tostring(err)) end
    end
    table.sort(assets)
    for _,name in ipairs(assets) do log('ASSET '..name) end
    log('END classes='..#classes..' assets='..#assets..' (loaded objects only; limits 400/200)')
end
local function request()
    if busy then log('Inspection already queued/running'); return end
    busy=true
    local ok,err=pcall(function()
        ExecuteInGameThread(function()
            local success,message=pcall(inspect)
            busy=false
            if not success then log('ERROR '..tostring(message)) end
        end)
    end)
    if not ok then busy=false; log('QUEUE ERROR '..tostring(err)) end
end
RegisterKeyBind(Key.F8,request)
log('Loaded. Load a save, equip a weapon, then press F8 once. Probe v0.2: focused full weapon API and struct schemas; not a weapon mod.')
