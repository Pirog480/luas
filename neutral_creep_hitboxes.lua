-- neutral_creep_hitboxes.lua
-- VITTLOCK Lua API
-- Shows visible jungle / neutral creep hit volumes in front of the local player.
-- Hidden through walls by TraceLine LOS checks.

local m = ui.script()
m:category("Visuals")

local enabled       = m:switch("Neutral Creep Hitboxes", true)
local max_distance  = m:slider_float("Max distance", 200.0, 5000.0, 1800.0)
local fov_deg       = m:slider_float("Field of view", 10.0, 160.0, 70.0)
local scan_interval = m:slider_float("Scan interval", 0.10, 2.00, 0.35)
local thickness     = m:slider_float("Line thickness", 0.5, 4.0, 1.4)
local detail        = m:slider_int("Detail", 6, 18, 10)
local color         = m:color("Hitbox color", {0.55, 0.95, 0.35, 1.0})

m:separator()
m:group("Extras")
local draw_name     = m:switch("Draw name", false)
local debug_count   = m:switch("Debug count", false)

local tracked = {}
local last_scan = 0.0
local SCAN_MIN_HANDLE = 1
local SCAN_MAX_HANDLE = 4096
local TAU = math.pi * 2.0

local function lower(s)
    return (s or ""):lower()
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
    return Vector3.new(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
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

local function lerp_vec(a, b, t)
    return a + (b - a) * t
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
    if Engine.GetEntityTeam(handle) ~= 4 then return false end
    if not Engine.IsEntityAlive(handle) then return false end
    if Engine.GetEntityHealth(handle) <= 0 then return false end
    if Engine.GetEntityMaxHealth(handle) <= 0 then return false end
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

local function get_creep_points(handle)
    local origin = Engine.GetEntityOrigin(handle)
    if not valid_pos(origin) then return nil end

    local legs  = Engine.GetBonePosition(handle, "Legs")
    local torso = Engine.GetBonePosition(handle, "Torso")
    local neck  = Engine.GetBonePosition(handle, "Neck")
    local head  = Engine.GetBonePosition(handle, "Head")
    local arms  = Engine.GetBonePosition(handle, "Arms")

    if not valid_pos(legs) then legs = origin end
    if not valid_pos(torso) then torso = legs + Vector3.new(0.0, 0.0, 24.0) end
    if not valid_pos(neck) then neck = torso + Vector3.new(0.0, 0.0, 12.0) end
    if not valid_pos(head) then head = neck + Vector3.new(0.0, 0.0, 12.0) end
    if not valid_pos(arms) then arms = torso + Vector3.new(0.0, 0.0, 4.0) end

    local up, body_len = normalize(head - legs)
    if body_len <= 0.0001 then
        up = Vector3.new(0.0, 0.0, 1.0)
        body_len = 48.0
    end

    local height = math.max(36.0, body_len)

    local head_top = head + up * math.max(3.0, height * 0.06)
    local chest = lerp_vec(torso, neck, 0.45)
    local belly = lerp_vec(legs, torso, 0.78)
    local hips  = lerp_vec(legs, torso, 0.42)
    local knees = lerp_vec(legs, torso, 0.15)

    local arm_span = (arms - torso):Length()
    if arm_span <= 0.0001 then
        arm_span = height * 0.18
    end

    local head_r  = math.max(5.0, height * 0.10)
    local neck_r  = math.max(4.0, head_r * 0.65)
    local chest_r = math.max(9.0, arm_span * 0.90, height * 0.18)
    local belly_r = math.max(8.0, chest_r * 0.88)
    local hips_r  = math.max(7.0, chest_r * 0.78)
    local leg_r   = math.max(6.0, hips_r * 0.62)

    return {
        origin = origin,
        legs = legs,
        knees = knees,
        hips = hips,
        belly = belly,
        chest = chest,
        neck = neck,
        head = head,
        head_top = head_top,
        up = up,
        height = height,
        arm_span = arm_span,
        rings = {
            { center = head,     rx = head_r,  ry = head_r * 0.92 },
            { center = neck,     rx = neck_r,  ry = neck_r * 0.72 },
            { center = chest,    rx = chest_r, ry = chest_r * 0.62 },
            { center = belly,    rx = belly_r, ry = belly_r * 0.58 },
            { center = hips,     rx = hips_r,  ry = hips_r * 0.52 },
            { center = knees,    rx = leg_r,   ry = leg_r * 0.45 },
        }
    }
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

local function build_ring_points(center, up, eye, rx, ry, segments)
    local view_dir = normalize(eye - center)
    if view_dir.x == 0.0 and view_dir.y == 0.0 and view_dir.z == 0.0 then
        view_dir = Vector3.new(1.0, 0.0, 0.0)
    end

    local right = normalize(cross(up, view_dir))
    if right.x == 0.0 and right.y == 0.0 and right.z == 0.0 then
        right = Vector3.new(1.0, 0.0, 0.0)
    end

    local forward = normalize(cross(right, up))
    if forward.x == 0.0 and forward.y == 0.0 and forward.z == 0.0 then
        forward = Vector3.new(0.0, 1.0, 0.0)
    end

    local pts = {}
    for i = 0, segments - 1 do
        local ang = (i / segments) * TAU
        pts[i + 1] = center
            + right * (math.cos(ang) * rx)
            + forward * (math.sin(ang) * ry)
    end
    return pts
end

local function draw_loop(points, r, g, b, a, thick)
    for i = 1, #points do
        local j = (i % #points) + 1
        render.line_3d(points[i], points[j], r, g, b, a, thick)
    end
end

local function draw_between_loops(a_pts, b_pts, r, g, b, a, thick)
    local count = math.min(#a_pts, #b_pts)
    for i = 1, count do
        render.line_3d(a_pts[i], b_pts[i], r, g, b, a, thick)
    end
end

local function draw_creep_volume(creep, eye, r, g, b, a, thick, segments)
    local loops = {}
    for i = 1, #creep.rings do
        local ring = creep.rings[i]
        loops[i] = build_ring_points(ring.center, creep.up, eye, ring.rx, ring.ry, segments)
    end

    for i = 1, #loops do
        draw_loop(loops[i], r, g, b, a, thick)
    end

    for i = 1, #loops - 1 do
        draw_between_loops(loops[i], loops[i + 1], r, g, b, a, thick)
    end

    render.line_3d(creep.legs, creep.knees, r, g, b, a, thick)
    render.line_3d(creep.knees, creep.hips, r, g, b, a, thick)
    render.line_3d(creep.hips, creep.belly, r, g, b, a, thick)
    render.line_3d(creep.belly, creep.chest, r, g, b, a, thick)
    render.line_3d(creep.chest, creep.neck, r, g, b, a, thick)
    render.line_3d(creep.neck, creep.head, r, g, b, a, thick)
    render.line_3d(creep.head, creep.head_top, r, g, b, a, thick)
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

    for handle in pairs(tracked) do
        if not is_neutral_creep_handle(handle) then
            tracked[handle] = nil
        end
    end

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
    local segs = detail:get_int()
    local shown = 0

    for handle in pairs(tracked) do
        if not is_neutral_creep_handle(handle) then
            tracked[handle] = nil
        else
            local creep = get_creep_points(handle)
            if creep then
                local visible, dist = is_in_front(eye, creep.chest)
                if visible and dist <= max_distance:get_float() then
                    local los = has_line_of_sight(local_handle, handle, eye, creep.chest)
                        or has_line_of_sight(local_handle, handle, eye, creep.head)
                        or has_line_of_sight(local_handle, handle, eye, creep.belly)

                    if los then
                        draw_creep_volume(creep, eye, col[1], col[2], col[3], col[4], thick, segs)
                        shown = shown + 1

                        if draw_name:get_bool() then
                            local name_pos = creep.head_top + creep.up * math.max(4.0, creep.height * 0.05)
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
    end

    if debug_count:get_bool() then
        render.text(30, 300, 0.80, 1.0, 0.80, 0.85, "Neutral hit volumes: " .. tostring(shown), 14)
    end
end)
