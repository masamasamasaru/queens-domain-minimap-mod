local M = {}
function M.project(p, origin, radius, half)
    return (p.X-origin.X)*half/radius, -(p.Y-origin.Y)*half/radius
end
-- Clip a segment to the square map (Liang-Barsky).
function M.clip(x1,y1,x2,y2,h)
    local dx,dy=x2-x1,y2-y1
    local a,b=0,1
    local ps,qs={-dx,dx,-dy,dy},{x1+h,h-x1,y1+h,h-y1}
    for i=1,4 do
        local p,q=ps[i],qs[i]
        if p==0 then if q<0 then return end
        else
            local t=q/p
            if p<0 then a=math.max(a,t) else b=math.min(b,t) end
            if a>b then return end
        end
    end
    return x1+a*dx,y1+a*dy,x1+b*dx,y1+b*dy
end
return M
