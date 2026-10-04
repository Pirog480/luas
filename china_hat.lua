-- local_china_hat.lua
-- VITTLOCK Lua API
-- Draws a gradient china hat above the local player with size/position controls.
-- Improved to use a stable torso-based anchor with cached vertical lift so the hat stays locked to the hero without head-bone jitter or origin lag.

local m = ui.script()
m:category("Visuals")

local enabled        = m:switch("China Hat", true)
local radius         = m:slider_float("Hat radius", 8.0, 80.0, 26.0)
local height         = m:slider_float("Hat height", 2.0, 40.0, 12.0)
local segments       = m:slider_int("Hat segments", 12, 96, 40)

m:separator()
m:group("Position")
local offset_x       = m:slider_float("Offset X", -30.0, 30.0, 0.0)
local offset_y       = m:slider_float("Offset Y", -30.0, 30.0, 0.0)
local offset_z       = m:slider_float("Offset Z", -30.0, 40.0, 14.0)
local debug_anchor   = m:switch("Debug anchor", false)

m:separator()
m:group("Gradient")
local color_a        = m:color("Gradient color A", {1.0, 0.20, 0.45, 1.0})
local color_b        = m:color("Gradient color B", {0.15, 0.75, 1.0, 1.0})
local alpha          = m:slider_float("Fill alpha", 0.05, 1.0, 0.70)
local gradient_rot   = m:slider_float("Gradient rotation", 0.0, 360.0, 0.0)
local gradient_speed = m:slider_float("Gradient speed", 0.0, 180.0, 25.0)

m:separator()
m:group("Outline")
local draw_outline   = m:switch("Draw outline", true)
local outline_alpha  = m:slider_float("Outline alpha", 0.05, 1.0, 0.85)
local outline_thick  = m:slider_float("Outline thickness", 0.5, 3.0, 1.0)

local TAU = math.pi * 2.0
local cached_local_handle = -1
local cached_head_height = 30.0

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function mix_color(c1, c2, t, alpha_mul)
    return
        lerp(c1[1], c2[1], t),
        lerp(c1[2], c2[2], t),
        lerp(c1[3], c2[3], t),
        lerp(c1[4], c2[4], t) * alpha_mul
end

local function refresh_cached_head_height(handle)
    if handle == cached_local_handle then
        return cached_head_height
    end

    cached_local_handle = handle
    cached_head_height = 30.0

    local torso = Engine.GetBonePosition(handle, "Torso")
    local head = Engine.GetBonePosition(handle, "Head")

    if torso and head then
        local dz = head.z - torso.z
        if dz and dz > 1.0 and dz < 120.0 then
            cached_head_height = dz
            return cached_head_height
        end
    end

    local origin = Engine.GetEntityOrigin(handle)
    if head and origin then
        local dz = head.z - origin.z
        if dz and dz > 1.0 and dz < 200.0 then
            cached_head_height = dz
        end
    end

    return cached_head_height
end

local function get_hat_anchor(handle)
    local torso = Engine.GetBonePosition(handle, "Torso")
    if torso and not (torso.x == 0.0 and torso.y == 0.0 and torso.z == 0.0) then
        return torso
    end

    return Engine.GetEntityOrigin(handle)
end

local function get_hat_center_world(handle)
    local anchor = get_hat_anchor(handle)
    local head_height = refresh_cached_head_height(handle)

    return anchor + Vector3.new(
        offset_x:get_float(),
        offset_y:get_float(),
        head_height + offset_z:get_float()
    )
end

callbacks.on_local_spawn(function()
    cached_local_handle = -1
end)

callbacks.on_local_death(function()
    cached_local_handle = -1
end)

callbacks.on_render(function()
    if not enabled:get_bool() then return end

    local local_handle = Engine.GetLocalPlayerHandle()
    if not local_handle or local_handle < 0 then return end
    if not Engine.IsEntityAlive(local_handle) then return end

    local center_world = get_hat_center_world(local_handle)
    local cone_height = height:get_float()
    local brim_radius = radius:get_float()
    local detail = segments:get_int()
    local fill_alpha = alpha:get_float()
    local c1 = color_a:get_color()
    local c2 = color_b:get_color()
    local gradient_phase = math.rad(gradient_rot:get_float() + Engine.GetCurTime() * gradient_speed:get_float())

    if detail < 3 then detail = 3 end

    local center_screen = Engine.WorldToScreen(center_world)
    if not center_screen.visible then return end

    local apex_world = center_world + Vector3.new(0.0, 0.0, cone_height)
    local apex_screen = Engine.WorldToScreen(apex_world)
    if not apex_screen.visible then return end

    local sample_x = Engine.WorldToScreen(center_world + Vector3.new(brim_radius, 0.0, 0.0))
    local sample_y = Engine.WorldToScreen(center_world + Vector3.new(0.0, brim_radius, 0.0))
    if not sample_x.visible and not sample_y.visible then return end

    local brim_rx = 0.0
    local brim_ry = 0.0

    if sample_x.visible then
        brim_rx = math.max(brim_rx, math.abs(sample_x.x - center_screen.x))
        brim_ry = math.max(brim_ry, math.abs(sample_x.y - center_screen.y))
    end

    if sample_y.visible then
        brim_rx = math.max(brim_rx, math.abs(sample_y.x - center_screen.x))
        brim_ry = math.max(brim_ry, math.abs(sample_y.y - center_screen.y))
    end

    brim_rx = math.max(brim_rx, 4.0)
    brim_ry = math.max(brim_ry, brim_rx * 0.28)

    if debug_anchor:get_bool() then
        render.circle(center_screen.x, center_screen.y, 4.0, 1.0, 1.0, 1.0, 0.85, 18, 1.0)
        render.line(center_screen.x, center_screen.y, apex_screen.x, apex_screen.y, 1.0, 1.0, 1.0, 0.55, 1.0)
    end

    local rim_screen = {}

    for i = 0, detail - 1 do
        local a = (i / detail) * TAU
        rim_screen[i + 1] = {
            x = center_screen.x + math.cos(a) * brim_rx,
            y = center_screen.y + math.sin(a) * brim_ry,
            visible = true,
        }
    end

    for i = 1, detail do
        local j = (i % detail) + 1
        local p1 = rim_screen[i]
        local p2 = rim_screen[j]
        local slice_angle = ((i - 1) / detail) * TAU
        local t = 0.5 + 0.5 * math.sin(slice_angle + gradient_phase)
        local r, g, b, a = mix_color(c1, c2, t, fill_alpha)

        render.filled_polygon({
            { apex_screen.x, apex_screen.y },
            { p1.x, p1.y },
            { p2.x, p2.y }
        }, r, g, b, a)
    end

    if draw_outline:get_bool() then
        local oa = outline_alpha:get_float()
        local th = outline_thick:get_float()

        for i = 1, detail do
            local j = (i % detail) + 1
            local p1 = rim_screen[i]
            local p2 = rim_screen[j]
            local slice_angle = ((i - 1) / detail) * TAU
            local t = 0.5 + 0.5 * math.sin(slice_angle + gradient_phase)
            local r, g, b, a = mix_color(c1, c2, t, oa)

            render.line(p1.x, p1.y, p2.x, p2.y, r, g, b, a, th)
            render.line(apex_screen.x, apex_screen.y, p1.x, p1.y, r, g, b, a, th)
        end
    end
end)
