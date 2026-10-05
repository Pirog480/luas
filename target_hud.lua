-- target_hud.lua
-- VITTLOCK Lua API
-- Shows a target HUD after you damage an enemy hero.
-- Includes hero portrait, HP, extra stats, and multiple visual styles.

local m = ui.script()
m:category("Visuals")

local enabled         = m:switch("Target HUD", true)
local style           = m:combo("Style", {"Compact", "Ring", "Flat"}, 0)
local pos_x           = m:slider_int("Position X", 0, 3840, 80)
local pos_y           = m:slider_int("Position Y", 0, 2160, 120)
local scale           = m:slider_float("Scale", 0.70, 2.00, 1.00)
local show_time       = m:slider_float("Show time", 0.5, 8.0, 2.2)
local fade_speed      = m:slider_float("Fade speed", 4.0, 20.0, 10.0)

m:separator()
m:group("Tracking")
local visible_only    = m:switch("Visible only", false)
local damage_window   = m:slider_float("Combat window", 0.10, 2.00, 0.85)
local min_damage      = m:slider_int("Min damage", 1, 300, 1)
local sticky_target   = m:switch("Refresh while hitting same target", true)

m:separator()
m:group("Colors")
local accent_color    = m:color("Accent", {0.20, 0.95, 0.45, 1.0})
local bg_color        = m:color("Background", {0.07, 0.12, 0.08, 0.92})
local text_color      = m:color("Text", {1.0, 1.0, 1.0, 1.0})
local sub_color       = m:color("Sub text", {0.80, 0.92, 0.80, 1.0})
local hp_low_color    = m:color("Low HP", {1.00, 0.34, 0.34, 1.0})

m:separator()
m:group("Extras")
local draw_avatar     = m:switch("Draw hero icon", true)
local draw_healthbar  = m:switch("Draw HP bar", true)
local show_last_dmg   = m:switch("Show last damage", true)
local debug_text      = m:switch("Debug text", false)

local tracked_hp = {}
local current_target = -1
local current_damage = 0
local target_until = 0.0
local hud_alpha = 0.0
local recent_combat_until = 0.0
local last_frame_time = 0.0
local scan_count = 0

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function ease(current, target, speed, dt)
    return current + (target - current) * clamp(speed * dt, 0.0, 1.0)
end

local function valid_vec(v)
    return v and not (v.x == 0.0 and v.y == 0.0 and v.z == 0.0)
end

local function get_dt()
    local now = Engine.GetCurTime()
    if last_frame_time == 0.0 then last_frame_time = now end
    local dt = clamp(now - last_frame_time, 0.0, 0.10)
    last_frame_time = now
    return dt
end

local function color_lerp(c1, c2, t)
    return {
        lerp(c1[1], c2[1], t),
        lerp(c1[2], c2[2], t),
        lerp(c1[3], c2[3], t),
        lerp(c1[4], c2[4], t),
    }
end

local function health_color(frac)
    local hi = accent_color:get_color()
    local lo = hp_low_color:get_color()
    return color_lerp(lo, hi, clamp(frac, 0.0, 1.0))
end

local function lower(s)
    return (s or ""):lower()
end

local function prettify_hero_name(raw)
    local slug = lower(raw or "")
    slug = slug:match("hero_([a-z0-9_]+)") or slug
    if slug == "" then return "Enemy" end

    local out = slug:gsub("_", " ")
    out = out:gsub("(%a)([%w_']*)", function(a, b)
        return a:upper() .. b
    end)
    return out
end

local function hero_slug(raw)
    return lower((raw or ""):match("hero_([a-z0-9_]+)") or "")
end

local function hero_icon_path(handle)
    local slug = hero_slug(Engine.GetEntityName(handle))
    if slug == "" then return nil end
    return "panorama/images/heroes/" .. slug .. "_sm_psd.vtex_c"
end

local function get_eye_pos(handle)
    local head = Engine.GetBonePosition(handle, "Head")
    if valid_vec(head) then return head end
    return Engine.GetEntityOrigin(handle) + Vector3.new(0.0, 0.0, 60.0)
end

local function get_focus_pos(handle)
    local torso = Engine.GetBonePosition(handle, "Torso")
    if valid_vec(torso) then return torso end
    local head = Engine.GetBonePosition(handle, "Head")
    local legs = Engine.GetBonePosition(handle, "Legs")
    if valid_vec(head) and valid_vec(legs) then
        return legs + (head - legs) * 0.45
    end
    return Engine.GetEntityOrigin(handle)
end

local function get_velocity(handle)
    local ok, vel = pcall(function()
        return Engine.GetProp(handle, "m_vecVelocity")
    end)
    if ok and vel and vel.x and vel.y and vel.z then
        return vel
    end
    return Vector3.new(0.0, 0.0, 0.0)
end

local function is_valid_enemy(local_handle, local_team, handle)
    if not handle or handle <= 0 then return false end
    if handle == local_handle then return false end
    if not Engine.IsPlayer(handle) then return false end
    if not Engine.IsEntityAlive(handle) then return false end
    if Engine.GetEntityHealth(handle) <= 0 then return false end
    if Engine.GetEntityTeam(handle) == local_team then return false end
    return true
end

local function is_visible(local_handle, eye, handle)
    local pos = get_focus_pos(handle)
    local tr = Engine.TraceLine(eye, pos, local_handle)
    if not tr.hit then return true end
    return tr.hit_entity == handle
end

local function metric_to_screen_center(handle)
    local pos = get_focus_pos(handle)
    local s = Engine.WorldToScreen(pos)
    if not s.visible then return math.huge end
    local screen = Engine.GetScreenSize()
    local dx = s.x - screen.w * 0.5
    local dy = s.y - screen.h * 0.5
    return math.sqrt(dx * dx + dy * dy)
end

local function set_target(handle, damage)
    current_target = handle
    current_damage = damage or 0
    target_until = Engine.GetCurTime() + show_time:get_float()
end

local function track_damage_events(local_handle, local_team)
    local players = Engine.GetPlayers() or {}
    local eye = get_eye_pos(local_handle)
    local now = Engine.GetCurTime()
    local best_handle = -1
    local best_damage = 0
    local best_metric = math.huge
    scan_count = 0

    local present = {}
    for _, handle in ipairs(players) do
        if is_valid_enemy(local_handle, local_team, handle) then
            present[handle] = true
            scan_count = scan_count + 1

            local hp = Engine.GetEntityHealth(handle)
            local prev = tracked_hp[handle]
            tracked_hp[handle] = hp

            if prev and hp < prev then
                local dmg = prev - hp
                if dmg >= min_damage:get_int() and now <= recent_combat_until then
                    if (not visible_only:get_bool()) or is_visible(local_handle, eye, handle) then
                        local metric = metric_to_screen_center(handle)
                        if handle == current_target and sticky_target:get_bool() then
                            metric = metric - 5000.0
                        end
                        if metric < best_metric then
                            best_metric = metric
                            best_handle = handle
                            best_damage = dmg
                        end
                    end
                end
            end
        end
    end

    for handle in pairs(tracked_hp) do
        if not present[handle] then
            tracked_hp[handle] = nil
        end
    end

    if best_handle ~= -1 then
        set_target(best_handle, best_damage)
    end
end

local function draw_bar(x, y, w, h, frac, bg, fg)
    render.filled_rect(x, y, w, h, bg[1], bg[2], bg[3], bg[4], h * 0.5)
    render.filled_rect(x + 1, y + 1, math.max(0, (w - 2) * clamp(frac, 0.0, 1.0)), math.max(0, h - 2), fg[1], fg[2], fg[3], fg[4], math.max(0, h * 0.5 - 1))
end

local function draw_arc(cx, cy, radius, start_ang, end_ang, color, alpha, thickness, segments)
    local prev_x, prev_y = nil, nil
    for i = 0, segments do
        local t = i / segments
        local a = start_ang + (end_ang - start_ang) * t
        local x = cx + math.cos(a) * radius
        local y = cy + math.sin(a) * radius
        if prev_x then
            render.line(prev_x, prev_y, x, y, color[1], color[2], color[3], alpha, thickness)
        end
        prev_x, prev_y = x, y
    end
end

local function draw_compact_style(handle, alpha_mul)
    local sc = scale:get_float()
    local x = pos_x:get_int()
    local y = pos_y:get_int()
    local w = 228.0 * sc
    local h = 76.0 * sc
    local avatar = 48.0 * sc

    local bg = bg_color:get_color()
    local txt = text_color:get_color()
    local sub = sub_color:get_color()
    local hp = Engine.GetEntityHealth(handle)
    local max_hp = math.max(1, Engine.GetEntityMaxHealth(handle))
    local frac = clamp(hp / max_hp, 0.0, 1.0)
    local hp_col = health_color(frac)
    local dist = (get_focus_pos(handle) - Engine.GetEntityOrigin(Engine.GetLocalPlayerHandle())):Length()
    local speed = get_velocity(handle):Length2D()

    render.filled_rect(x + 3 * sc, y + 4 * sc, w, h, 0.0, 0.0, 0.0, 0.10 * alpha_mul, 12.0 * sc)
    render.filled_rect(x, y, w, h, bg[1], bg[2], bg[3], bg[4] * alpha_mul, 12.0 * sc)
    render.rect(x, y, w, h, 1.0, 1.0, 1.0, 0.05 * alpha_mul, 1.0, 12.0 * sc)

    if draw_avatar:get_bool() then
        render.filled_rect(x + 10 * sc, y + 14 * sc, avatar, avatar, 0.12, 0.12, 0.12, 0.95 * alpha_mul, 8.0 * sc)
        local icon = hero_icon_path(handle)
        if icon then
            render.panorama_image(icon, x + 10 * sc, y + 14 * sc, avatar, avatar, 1.0, 1.0, 1.0, alpha_mul)
        end
    end

    local text_x = x + 68 * sc
    render.text(text_x, y + 10 * sc, txt[1], txt[2], txt[3], 0.96 * alpha_mul, prettify_hero_name(Engine.GetEntityName(handle)), 16 * sc)
    render.text(x + w - 58 * sc, y + 10 * sc, hp_col[1], hp_col[2], hp_col[3], 0.98 * alpha_mul, tostring(hp) .. " HP", 15 * sc)

    render.text(text_x, y + 33 * sc, sub[1], sub[2], sub[3], 0.80 * alpha_mul,
        string.format("Dist %.0f  |  Speed %.0f", dist, speed), 12 * sc)

    if show_last_dmg:get_bool() and current_damage > 0 then
        render.text(text_x, y + 48 * sc, hp_col[1], hp_col[2], hp_col[3], 0.88 * alpha_mul,
            string.format("Last hit -%d", current_damage), 12 * sc)
    else
        render.text(text_x, y + 48 * sc, sub[1], sub[2], sub[3], 0.78 * alpha_mul,
            string.format("%d / %d", hp, max_hp), 12 * sc)
    end

    if draw_healthbar:get_bool() then
        draw_bar(x + 66 * sc, y + 60 * sc, w - 78 * sc, 8 * sc,
            frac,
            {0.10, 0.16, 0.11, 0.90 * alpha_mul},
            {hp_col[1], hp_col[2], hp_col[3], 0.96 * alpha_mul}
        )
    end
end

local function draw_ring_style(handle, alpha_mul)
    local sc = scale:get_float()
    local x = pos_x:get_int()
    local y = pos_y:get_int()
    local w = 218.0 * sc
    local h = 88.0 * sc
    local ring_r = 24.0 * sc
    local cx = x + 36.0 * sc
    local cy = y + 42.0 * sc

    local bg = bg_color:get_color()
    local txt = text_color:get_color()
    local sub = sub_color:get_color()
    local hp = Engine.GetEntityHealth(handle)
    local max_hp = math.max(1, Engine.GetEntityMaxHealth(handle))
    local frac = clamp(hp / max_hp, 0.0, 1.0)
    local hp_col = health_color(frac)
    local dist = (get_focus_pos(handle) - Engine.GetEntityOrigin(Engine.GetLocalPlayerHandle())):Length()
    local speed = get_velocity(handle):Length2D()

    render.filled_rect(x + 3 * sc, y + 4 * sc, w, h, 0.0, 0.0, 0.0, 0.10 * alpha_mul, 12.0 * sc)
    render.filled_rect(x, y, w, h, bg[1], bg[2], bg[3], bg[4] * alpha_mul, 12.0 * sc)
    render.rect(x, y, w, h, 1.0, 1.0, 1.0, 0.05 * alpha_mul, 1.0, 12.0 * sc)

    render.circle(cx, cy, ring_r, 0.18, 0.18, 0.18, 0.70 * alpha_mul, 48, 5.0 * sc)
    draw_arc(cx, cy, ring_r, -math.pi * 0.5, -math.pi * 0.5 + math.pi * 2.0 * frac, hp_col, 0.95 * alpha_mul, 5.0 * sc, 48)

    if draw_avatar:get_bool() then
        render.filled_rect(cx - 16 * sc, cy - 16 * sc, 32 * sc, 32 * sc, 0.12, 0.12, 0.12, 0.95 * alpha_mul, 6.0 * sc)
        local icon = hero_icon_path(handle)
        if icon then
            render.panorama_image(icon, cx - 16 * sc, cy - 16 * sc, 32 * sc, 32 * sc, 1.0, 1.0, 1.0, alpha_mul)
        end
    end

    local tx = x + 72 * sc
    render.text(tx, y + 14 * sc, txt[1], txt[2], txt[3], 0.96 * alpha_mul, prettify_hero_name(Engine.GetEntityName(handle)), 16 * sc)
    render.text(tx, y + 35 * sc, hp_col[1], hp_col[2], hp_col[3], 0.98 * alpha_mul,
        string.format("%d / %d HP", hp, max_hp), 13 * sc)
    render.text(tx, y + 54 * sc, sub[1], sub[2], sub[3], 0.82 * alpha_mul,
        string.format("Dist %.0f  •  Speed %.0f", dist, speed), 12 * sc)

    if show_last_dmg:get_bool() and current_damage > 0 then
        render.text(x + w - 66 * sc, y + 14 * sc, hp_col[1], hp_col[2], hp_col[3], 0.92 * alpha_mul,
            string.format("-%d", current_damage), 18 * sc)
    end
end

local function draw_flat_style(handle, alpha_mul)
    local sc = scale:get_float()
    local x = pos_x:get_int()
    local y = pos_y:get_int()
    local w = 240.0 * sc
    local h = 58.0 * sc

    local bg = bg_color:get_color()
    local txt = text_color:get_color()
    local sub = sub_color:get_color()
    local hp = Engine.GetEntityHealth(handle)
    local max_hp = math.max(1, Engine.GetEntityMaxHealth(handle))
    local frac = clamp(hp / max_hp, 0.0, 1.0)
    local hp_col = health_color(frac)
    local dist = (get_focus_pos(handle) - Engine.GetEntityOrigin(Engine.GetLocalPlayerHandle())):Length()

    render.filled_rect(x, y, w, h, bg[1], bg[2], bg[3], bg[4] * alpha_mul, 8.0 * sc)
    render.filled_rect(x, y, 4 * sc, h, hp_col[1], hp_col[2], hp_col[3], 0.95 * alpha_mul, 8.0 * sc)
    render.rect(x, y, w, h, 1.0, 1.0, 1.0, 0.05 * alpha_mul, 1.0, 8.0 * sc)

    if draw_avatar:get_bool() then
        render.filled_rect(x + 10 * sc, y + 10 * sc, 38 * sc, 38 * sc, 0.12, 0.12, 0.12, 0.95 * alpha_mul, 6.0 * sc)
        local icon = hero_icon_path(handle)
        if icon then
            render.panorama_image(icon, x + 10 * sc, y + 10 * sc, 38 * sc, 38 * sc, 1.0, 1.0, 1.0, alpha_mul)
        end
    end

    render.text(x + 58 * sc, y + 10 * sc, txt[1], txt[2], txt[3], 0.96 * alpha_mul, prettify_hero_name(Engine.GetEntityName(handle)), 15 * sc)
    render.text(x + 58 * sc, y + 30 * sc, sub[1], sub[2], sub[3], 0.82 * alpha_mul,
        string.format("HP %d/%d  |  Dist %.0f", hp, max_hp, dist), 12 * sc)

    if draw_healthbar:get_bool() then
        draw_bar(x + 148 * sc, y + 18 * sc, 80 * sc, 22 * sc,
            frac,
            {0.10, 0.10, 0.10, 0.65 * alpha_mul},
            {hp_col[1], hp_col[2], hp_col[3], 0.98 * alpha_mul}
        )
    end
end

callbacks.on_local_spawn(function()
    tracked_hp = {}
    current_target = -1
    current_damage = 0
    target_until = 0.0
end)

callbacks.on_local_death(function()
    current_target = -1
    current_damage = 0
    target_until = 0.0
end)

callbacks.on_pre_createmove(function(cmd)
    if not enabled:get_bool() then return end

    if cmd:HasButtonState(InputBitMask_t.IN_ATTACK)
        or cmd:HasButtonState(InputBitMask_t.IN_ATTACK2)
        or cmd:HasButtonState(InputBitMask_t.IN_ABILITY1)
        or cmd:HasButtonState(InputBitMask_t.IN_ABILITY2)
        or cmd:HasButtonState(InputBitMask_t.IN_ABILITY3)
        or cmd:HasButtonState(InputBitMask_t.IN_ABILITY4)
        or cmd:HasButtonState(InputBitMask_t.IN_WEAPON1) then
        recent_combat_until = Engine.GetCurTime() + damage_window:get_float()
    end
end)

callbacks.on_frame(function()
    if not enabled:get_bool() then return end

    local local_handle = Engine.GetLocalPlayerHandle()
    if not local_handle or local_handle < 0 then return end
    if not Engine.IsEntityAlive(local_handle) then return end

    local local_team = Engine.GetEntityTeam(local_handle)
    track_damage_events(local_handle, local_team)
end)

callbacks.on_render(function()
    if not enabled:get_bool() then return end

    local now = Engine.GetCurTime()
    local visible = false
    if current_target ~= -1 and now <= target_until then
        local local_handle = Engine.GetLocalPlayerHandle()
        local local_team = Engine.GetEntityTeam(local_handle)
        visible = is_valid_enemy(local_handle, local_team, current_target)
    end

    hud_alpha = ease(hud_alpha, visible and 1.0 or 0.0, fade_speed:get_float(), get_dt())
    if hud_alpha <= 0.01 then return end

    if style:get_int() == 0 then
        draw_compact_style(current_target, hud_alpha)
    elseif style:get_int() == 1 then
        draw_ring_style(current_target, hud_alpha)
    else
        draw_flat_style(current_target, hud_alpha)
    end

    if debug_text:get_bool() then
        render.text(pos_x:get_int(), pos_y:get_int() + 100 * scale:get_float(), 1.0, 1.0, 1.0, 0.85,
            string.format("scan=%d target=%d damage=%d", scan_count, current_target, current_damage), 13)
    end
end)
