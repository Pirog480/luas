-- neutral_creep_hitboxes.lua
-- VITTLOCK Lua API
-- Shows visible jungle / neutral creep hitboxes in front of the local player.
-- Hidden through walls by TraceLine LOS checks.

local m = ui.script()
m:category("Visuals")

local enabled       = m:switch("Neutral Creep Hitboxes", true)
local max_distance  = m:slider_float("Max distance", 200.0, 5000.0, 1800.0)
local fov_deg       = m:slider_float("Field of view", 10.0, 160.0, 70.0)
local scan_interval = m:slider_float("Scan interval", 0.20, 3.00, 0.80)
local thickness     = m:slider_float("Line thickness", 0.5, 4.0, 1.5)
local color         = m:color("Hitbox color", {0.55, 0.95, 0.35, 1.0})

m:separator()
m:group("Extras")
local draw_name     = m:switch("Draw name", false)
local debug_count   = m:switch("Debug count", false)

local tracked = {}
local last_scan = 0.0
local SCAN_MIN_HANDLE = 1
local SCAN_MAX_HANDLE = 4096

local function lower(s)
    return (s or ""):lower()
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function normalize(v)
    local len = v:Length()
    if len <= 0.0001 then
        return Vector3.new(0.0, 0.0, 0.0), 0.0
    end
    return v * (1.0 / len), len
end

local function is_zero_vec(v)
    return not v or (v.x == 0.0 and v.y == 0.0 and v.z == 0.0)
end

local function valid_pos(v)
    return v and not is_zero_vec(v)
end

local function is_neutral_creep_name(name)
    name = lower(name)
    if name == "" or name == "entity" then return false end

    if name:find("npc_trooper_neutral", 1, true) then return true end
    if name:find("npc_neutral_", 1, true) then return true end
    if name:find("neutral_trooper", 1, true) then return true end

    if name:find("neutral", 1, true) and (name:find("npc", 1, true) or name:find("trooper", 1, true)) then
        return true
    end

    return false
end

local function is_neutral_creep_handle(handle)
    if not handle or handle <= 0 then return false end
    if Engine.GetEntityHealth(handle) <= 0 then return false end
    if Engine.GetEntityTeam(handle) ~= 4 then return false end
    return is_neutral_creep_name(Engine.GetEntityName(handle))
end

local function rescan_neutral_creeps()
    tracked = {}

    for handle = SCAN_MIN_HANDLE, SCAN_MAX_HANDLE do
        if is_neutral_creep_handle(handle) then
            tracked[handle] = true
        end
    end

    last_scan = Engine.GetCurTime()
end

local function eye_position(local_handle)
    local head = Engine.GetBonePosition(local_handle, "Head")
    if valid_pos(head) then
        return head
    end

    local origin = Engine.GetEntityOrigin(local_handle)
    return origin + Vector3.new(0.0, 0.0, 60.0)
end

local function build_creep_box(handle)
    local origin = Engine.GetEntityOrigin(handle)
    if not valid_pos(origin) then return nil end

    local torso = Engine.GetBonePosition(handle, "Torso")
    local head  = Engine.GetBonePosition(handle, "Head")
    local legs  = Engine.GetBonePosition(handle, "Legs")
    local arms  = Engine.GetBonePosition(handle, "Arms")

    if not valid_pos(torso) then torso = origin + Vector3.new(0.0, 0.0, 26.0) end
    if not valid_pos(head)  then head  = origin + Vector3.new(0.0, 0.0, 52.0) end
    if not valid_pos(legs)  then legs  = origin end

    local top_z = math.max(head.z, torso.z + 8.0, origin.z + 36.0)
    local bottom_z = math.min(legs.z, origin.z)

    if bottom_z > top_z - 16.0 then
        bottom_z = top_z - 44.0
    end

    local cx, cy = torso.x, torso.y
    local height = top_z - bottom_z
    local half_w = math.max(10.0, height * 0.22)

    if valid_pos(arms) then
        half_w = math.max(half_w, math.abs(arms.x - cx), math.abs(arms.y - cy))
    end

    local mins = Vector3.new(cx - half_w, cy - half_w, bottom_z)
    local maxs = Vector3.new(cx + half_w, cy + half_w, top_z)
    local focus = Vector3.new(cx, cy, bottom_z + height * 0.58)

    return mins, maxs, focus, height
end

local function is_in_front(eye, target_pos)
    local forward = Engine.AngleVectors(Engine.GetCameraAngles())
    local dir, dist = normalize(target_pos - eye)
    if dist <= 0.0001 then
        return false, dist
    end

    local limit = math.cos(math.rad(fov_deg:get_float() * 0.5))
    return dot(forward, dir) >= limit, dist
end

local function has_line_of_sight(local_handle, target_handle, eye, target_pos)
    local tr = Engine.TraceLine(eye, target_pos, local_handle)
    if not tr.hit then
        return true
    end

    return tr.hit_entity == target_handle
end

local function draw_box_3d(mins, maxs, r, g, b, a, thick)
    local p1 = Vector3.new(mins.x, mins.y, mins.z)
    local p2 = Vector3.new(maxs.x, mins.y, mins.z)
    local p3 = Vector3.new(maxs.x, maxs.y, mins.z)
    local p4 = Vector3.new(mins.x, maxs.y, mins.z)

    local p5 = Vector3.new(mins.x, mins.y, maxs.z)
    local p6 = Vector3.new(maxs.x, mins.y, maxs.z)
    local p7 = Vector3.new(maxs.x, maxs.y, maxs.z)
    local p8 = Vector3.new(mins.x, maxs.y, maxs.z)

    render.line_3d(p1, p2, r, g, b, a, thick)
    render.line_3d(p2, p3, r, g, b, a, thick)
    render.line_3d(p3, p4, r, g, b, a, thick)
    render.line_3d(p4, p1, r, g, b, a, thick)

    render.line_3d(p5, p6, r, g, b, a, thick)
    render.line_3d(p6, p7, r, g, b, a, thick)
    render.line_3d(p7, p8, r, g, b, a, thick)
    render.line_3d(p8, p5, r, g, b, a, thick)

    render.line_3d(p1, p5, r, g, b, a, thick)
    render.line_3d(p2, p6, r, g, b, a, thick)
    render.line_3d(p3, p7, r, g, b, a, thick)
    render.line_3d(p4, p8, r, g, b, a, thick)
end

callbacks.on_entity_create(function(handle)
    if is_neutral_creep_handle(handle) then
        tracked[handle] = true
    end
end)

callbacks.on_entity_destroy(function(handle)
    tracked[handle] = nil
end)

callbacks.on_local_spawn(function()
    last_scan = 0.0
end)

callbacks.on_frame(function()
    if not enabled:get_bool() then return end

    if Engine.GetCurTime() - last_scan >= scan_interval:get_float() then
        rescan_neutral_creeps()
    end
end)

callbacks.on_render(function()
    if not enabled:get_bool() then return end

    if last_scan == 0.0 then
        rescan_neutral_creeps()
    end

    local local_handle = Engine.GetLocalPlayerHandle()
    if not local_handle or local_handle < 0 then return end
    if not Engine.IsEntityAlive(local_handle) then return end

    local eye = eye_position(local_handle)
    local col = color:get_color()
    local thick = thickness:get_float()
    local shown = 0

    for handle in pairs(tracked) do
        if is_neutral_creep_handle(handle) then
            local mins, maxs, focus, height = build_creep_box(handle)
            if mins and maxs and focus then
                local front, dist = is_in_front(eye, focus)
                if front and dist <= max_distance:get_float() and has_line_of_sight(local_handle, handle, eye, focus) then
                    draw_box_3d(mins, maxs, col[1], col[2], col[3], col[4], thick)
                    shown = shown + 1

                    if draw_name:get_bool() then
                        local name_pos = Vector3.new(focus.x, focus.y, maxs.z + math.max(6.0, height * 0.08))
                        local s = Engine.WorldToScreen(name_pos)
                        if s.visible then
                            render.text(s.x, s.y, col[1], col[2], col[3], col[4], Engine.GetEntityName(handle), 13)
                        end
                    end
                end
            end
        else
            tracked[handle] = nil
        end
    end

    if debug_count:get_bool() then
        render.text(30, 300, 0.80, 1.0, 0.80, 0.85, "Neutral hitboxes: " .. tostring(shown), 14)
    end
end)
