-- hero_trail.lua
-- VITTLOCK Lua API
-- Visual trail behind the local hero with configurable length, lifetime and 1-4 color gradient.

local m = ui.script()
m:category("Visuals")

local enabled         = m:switch("Hero Trail", true)
local trail_length    = m:slider_float("Trail length", 50.0, 4000.0, 900.0)
local life_time       = m:slider_float("Life time", 0.10, 8.00, 2.20)
local thickness       = m:slider_float("Thickness", 0.5, 6.0, 2.0)
local height_offset   = m:slider_float("Height offset", -20.0, 80.0, 10.0)
local sample_interval = m:slider_float("Sample interval", 0.01, 0.25, 0.03)
local min_step        = m:slider_float("Min step", 0.0, 40.0, 4.0)
local break_distance  = m:slider_float("Break distance", 30.0, 600.0, 180.0)

m:separator()
m:group("Gradient")
local color_count     = m:combo("Color count", {"1", "2", "3", "4"}, 1)
local color_1         = m:color("Color 1", {0.18, 0.65, 1.00, 1.0})
local color_2         = m:color("Color 2", {0.65, 0.25, 1.00, 1.0})
local color_3         = m:color("Color 3", {1.00, 0.32, 0.58, 1.0})
local color_4         = m:color("Color 4", {1.00, 0.85, 0.20, 1.0})
local alpha           = m:slider_float("Alpha", 0.05, 1.0, 0.90)
local fade_tail       = m:switch("Fade tail", true)

m:separator()
m:group("Extras")
local use_torso       = m:switch("Use torso anchor", false)
local debug_points    = m:switch("Debug points", false)

local points = {}
local last_sample_time = 0.0
local last_handle = -1

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function color_lerp(c1, c2, t)
    return {
        lerp(c1[1], c2[1], t),
        lerp(c1[2], c2[2], t),
        lerp(c1[3], c2[3], t),
        lerp(c1[4], c2[4], t),
    }
end

local function clear_trail()
    points = {}
    last_sample_time = 0.0
end

local function get_anchor_position(local_handle)
    local base = nil

    if use_torso:get_bool() then
        local torso = Engine.GetBonePosition(local_handle, "Torso")
        if torso and not (torso.x == 0.0 and torso.y == 0.0 and torso.z == 0.0) then
            base = torso
        end
    end

    if not base then
        base = Engine.GetEntityOrigin(local_handle)
    end

    return base + Vector3.new(0.0, 0.0, height_offset:get_float())
end

local function get_gradient_colors()
    local count = color_count:get_int() + 1
    local cols = {
        color_1:get_color(),
        color_2:get_color(),
        color_3:get_color(),
        color_4:get_color(),
    }

    local out = {}
    for i = 1, count do
        out[i] = cols[i]
    end
    return out
end

local function gradient_color(t)
    local cols = get_gradient_colors()
    local count = #cols

    if count <= 1 then
        return cols[1]
    end

    t = clamp(t, 0.0, 1.0)
    local scaled = t * (count - 1)
    local idx = math.floor(scaled) + 1
    local frac = scaled - math.floor(scaled)

    if idx >= count then
        return cols[count]
    end

    return color_lerp(cols[idx], cols[idx + 1], frac)
end

local function total_trail_length()
    local total = 0.0
    for i = 2, #points do
        total = total + (points[i].pos - points[i - 1].pos):Length()
    end
    return total
end

local function trim_trail(now)
    local ttl = life_time:get_float()
    while #points > 0 and (now - points[1].time) > ttl do
        table.remove(points, 1)
    end

    local max_len = trail_length:get_float()
    while #points > 1 and total_trail_length() > max_len do
        table.remove(points, 1)
    end
end

local function add_point(pos, now)
    if #points == 0 then
        points[1] = { pos = pos, time = now }
        return
    end

    local last = points[#points]
    local dist = (pos - last.pos):Length()

    if dist <= min_step:get_float() then
        return
    end

    if dist >= break_distance:get_float() then
        clear_trail()
        points[1] = { pos = pos, time = now }
        return
    end

    points[#points + 1] = { pos = pos, time = now }
end

callbacks.on_local_spawn(function()
    last_handle = -1
    clear_trail()
end)

callbacks.on_local_death(function()
    last_handle = -1
    clear_trail()
end)

callbacks.on_frame(function()
    if not enabled:get_bool() then return end

    local local_handle = Engine.GetLocalPlayerHandle()
    if not local_handle or local_handle < 0 then
        clear_trail()
        return
    end

    if not Engine.IsEntityAlive(local_handle) then
        clear_trail()
        return
    end

    if last_handle ~= local_handle then
        last_handle = local_handle
        clear_trail()
    end

    local now = Engine.GetCurTime()
    if last_sample_time ~= 0.0 and (now - last_sample_time) < sample_interval:get_float() then
        trim_trail(now)
        return
    end

    local pos = get_anchor_position(local_handle)
    add_point(pos, now)
    trim_trail(now)
    last_sample_time = now
end)

callbacks.on_render(function()
    if not enabled:get_bool() then return end
    if #points < 2 then return end

    local base_alpha = alpha:get_float()
    local thick = thickness:get_float()
    local denom = math.max(1, #points - 1)

    for i = 2, #points do
        local p0 = points[i - 1]
        local p1 = points[i]
        local seg_index = i - 1
        local t = (seg_index - 0.5) / denom
        local c = gradient_color(t)

        local seg_alpha = base_alpha * c[4]
        if fade_tail:get_bool() then
            seg_alpha = seg_alpha * clamp(t, 0.08, 1.0)
        end

        render.line_3d(p0.pos, p1.pos, c[1], c[2], c[3], seg_alpha, thick)
    end

    if debug_points:get_bool() then
        render.text(30, 360, 1.0, 1.0, 1.0, 0.85, "Trail points: " .. tostring(#points), 14)
    end
end)
