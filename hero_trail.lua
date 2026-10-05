-- hero_trail.lua
-- VITTLOCK Lua API
-- Flat filled ribbon trail behind the local hero, spanning from head to legs.
-- Supports configurable length, lifetime and 1-4 color gradient.

local m = ui.script()
m:category("Visuals")

local enabled         = m:switch("Hero Trail", true)
local trail_length    = m:slider_float("Trail length", 50.0, 4000.0, 900.0)
local life_time       = m:slider_float("Life time", 0.10, 8.00, 2.20)
local thickness       = m:slider_float("Outline thickness", 0.0, 4.0, 1.0)
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
local fill_quality    = m:slider_int("Fill quality", 1, 6, 3)
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

local function valid_pos(v)
    return v and not (v.x == 0.0 and v.y == 0.0 and v.z == 0.0)
end

local function vec_lerp(a, b, t)
    return a + (b - a) * t
end

local function get_sample(local_handle)
    local origin = Engine.GetEntityOrigin(local_handle)
    local head = Engine.GetBonePosition(local_handle, "Head")
    local neck = Engine.GetBonePosition(local_handle, "Neck")
    local torso = Engine.GetBonePosition(local_handle, "Torso")
    local legs = Engine.GetBonePosition(local_handle, "Legs")

    if not valid_pos(legs) then
        legs = origin
    end

    if not valid_pos(torso) then
        torso = origin + Vector3.new(0.0, 0.0, 38.0)
    end

    if not valid_pos(neck) then
        neck = torso + Vector3.new(0.0, 0.0, 14.0)
    end

    if not valid_pos(head) then
        head = neck + Vector3.new(0.0, 0.0, 10.0)
    end

    local shift = Vector3.new(0.0, 0.0, height_offset:get_float())
    local top = head + shift
    local bottom = legs + shift
    local center = vec_lerp(bottom, top, 0.5)

    return {
        top = top,
        bottom = bottom,
        center = center,
    }
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
        total = total + (points[i].center - points[i - 1].center):Length()
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

local function add_point(sample, now)
    if #points == 0 then
        sample.time = now
        points[1] = sample
        return
    end

    local last = points[#points]
    local dist = (sample.center - last.center):Length()

    if dist <= min_step:get_float() then
        return
    end

    if dist >= break_distance:get_float() then
        clear_trail()
        sample.time = now
        points[1] = sample
        return
    end

    sample.time = now
    points[#points + 1] = sample
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

    local sample = get_sample(local_handle)
    add_point(sample, now)
    trim_trail(now)
    last_sample_time = now
end)

callbacks.on_render(function()
    if not enabled:get_bool() then return end
    if #points < 2 then return end

    local base_alpha = alpha:get_float()
    local outline_thick = thickness:get_float()
    local denom = math.max(1, #points - 1)
    local slices = fill_quality:get_int()

    for i = 2, #points do
        local p0 = points[i - 1]
        local p1 = points[i]
        local seg_from = (i - 2) / denom
        local seg_to = (i - 1) / denom

        for s = 0, slices - 1 do
            local t0 = s / slices
            local t1 = (s + 1) / slices

            local top_a = vec_lerp(p0.top, p1.top, t0)
            local bot_a = vec_lerp(p0.bottom, p1.bottom, t0)
            local top_b = vec_lerp(p0.top, p1.top, t1)
            local bot_b = vec_lerp(p0.bottom, p1.bottom, t1)

            local a0 = Engine.WorldToScreen(top_a)
            local a1 = Engine.WorldToScreen(top_b)
            local b1 = Engine.WorldToScreen(bot_b)
            local b0 = Engine.WorldToScreen(bot_a)

            if a0.visible and a1.visible and b1.visible and b0.visible then
                local gt = lerp(seg_from, seg_to, (t0 + t1) * 0.5)
                local c = gradient_color(gt)
                local seg_alpha = base_alpha * c[4]

                if fade_tail:get_bool() then
                    seg_alpha = seg_alpha * clamp(gt, 0.06, 1.0)
                end

                local quad = {
                    { a0.x, a0.y },
                    { a1.x, a1.y },
                    { b1.x, b1.y },
                    { b0.x, b0.y },
                }

                render.filled_polygon(quad, c[1], c[2], c[3], seg_alpha)
                if outline_thick > 0.0 then
                    render.polygon(quad, c[1], c[2], c[3], math.min(1.0, seg_alpha * 0.9), true, outline_thick)
                end
            end
        end
    end

    if debug_points:get_bool() then
        render.text(30, 360, 1.0, 1.0, 1.0, 0.85, "Trail points: " .. tostring(#points), 14)
    end
end)
