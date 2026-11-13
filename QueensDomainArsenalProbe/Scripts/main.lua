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
    log('BEGIN v0.1')
    local classType=StaticFindObject('/Script/CoreUObject.Class')
    if not valid(classType) then error('UClass type unavailable') end
    local classes, assets, seen = {}, {}, {}
    local function addClass(c)
        if not valid(c) then return end
        local name=c:GetFullName()
        if seen[name] then return end
        seen[name]=true
        if #classes<160 then classes[#classes+1]=c end
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
        if not game or not relevant(name) then return end
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
                fields=fields+1; log('  FIELD '..p:GetFullName())
                if fields>=160 then log('  FIELD LIMIT'); return true end
            end)
            local functions=0
            c:ForEachFunction(function(fn)
                functions=functions+1; log('  FUNCTION '..fn:GetFullName())
                local params=0
                fn:ForEachProperty(function(p)
                    params=params+1; log('    PARAM '..p:GetFullName())
                    if params>=40 then return true end
                end)
                if functions>=160 then log('  FUNCTION LIMIT'); return true end
            end)
        end)
        if not ok then log('CLASS INSPECTION ERROR '..tostring(err)) end
    end
    table.sort(assets)
    for _,name in ipairs(assets) do log('ASSET '..name) end
    log('END classes='..#classes..' assets='..#assets..' (loaded objects only; limits 160/200)')
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
log('Loaded. Load a save, equip a weapon, then press F8 once. This is an API probe, not a weapon mod.')
