-- vector_aim.lua
-- VITTLOCK Lua API
-- Smooth angle-based aim assist (closest available alternative to mouse-move aiming in this API).
-- Uses a single global smoothing value, optional velocity prediction, and one selectable target bone.

local m = ui.script()
m:category("Aimbot")

local enabled         = m:switch("Vector Aim", false)
local require_key     = m:switch("Require aim key", true)
local aim_key         = m:keybind("Aim key", 0x02) -- RMB
local visible_only    = m:switch("Visible only", false)
local ignore_fov_when_locked = m:switch("Sticky target", true)

m:separator()
m:group("Targeting")
local aim_bone        = m:combo("Aim bone", {"Head", "Neck", "Chest", "Pelvis"}, 0)
local fov_deg         = m:slider_float("FOV", 1.0, 45.0, 8.0)
local max_distance    = m:slider_float("Max distance", 200.0, 5000.0, 2200.0)
local smooth          = m:slider_float("Smooth", 1.0, 30.0, 8.0)

m:separator()
m:group("Prediction")
local use_prediction  = m:switch("Enable prediction", true)
local pred_strength   = m:slider_float("Prediction strength", 0.00, 0.35, 0.10)

m:separator()
m:group("Debug")
local draw_fov        = m:switch("Draw FOV", false)
local draw_target     = m:switch("Draw target", false)

local locked_handle = -1

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function normalize_yaw(y)
    while y > 180.0 do y = y - 360.0 end
    while y < -180.0 do y = y + 360.0 end
    return y
end

local function normalize_pitch(p)
    if p > 89.0 then return 89.0 end
    if p < -89.0 then return -89.0 end
    return p
end

local function angle_delta(current, target)
    local dx = normalize_pitch(target.x - current.x)
    local dy = normalize_yaw(target.y - current.y)
    return dx, dy
end

local function angle_len(dx, dy)
    return math.sqrt(dx * dx + dy * dy)
end

local function calc_angle(from, to)
    local delta = to - from
    local horiz = math.sqrt(delta.x * delta.x + delta.y * delta.y)
    local yaw = math.atan2(delta.y, delta.x) * 180.0 / math.pi
    local pitch = -math.atan2(delta.z, horiz) * 180.0 / math.pi
    return QAngle.new(normalize_pitch(pitch), normalize_yaw(yaw), 0.0)
end

local function get_eye_pos(local_handle)
    local head = Engine.GetBonePosition(local_handle, "Head")
    if head and not (head.x == 0.0 and head.y == 0.0 and head.z == 0.0) then
        return head
    end
    return Engine.GetEntityOrigin(local_handle) + Vector3.new(0.0, 0.0, 60.0)
end

local function get_target_bone_position(enemy)
    local choice = aim_bone:get_int()
    local head = Engine.GetBonePosition(enemy:get_handle(), "Head")
    local neck = Engine.GetBonePosition(enemy:get_handle(), "Neck")
    local torso = Engine.GetBonePosition(enemy:get_handle(), "Torso")
    local legs = Engine.GetBonePosition(enemy:get_handle(), "Legs")

    if choice == 0 then
        return head
    elseif choice == 1 then
        return neck
    elseif choice == 2 then
        if neck and torso then
            return torso + (neck - torso) * 0.35
        end
        return torso
    else
        if legs and torso then
            return legs + (torso - legs) * 0.28
        end
        return legs
    end
end

local function get_entity_velocity(enemy)
    if enemy.get_prop then
        local ok, vel = pcall(function()
            return enemy:get_prop("m_vecVelocity")
        end)
        if ok and vel and type(vel) == "table" and vel.x and vel.y and vel.z then
            return vel
        end
    end
    return Vector3.new(0.0, 0.0, 0.0)
end

local function predict_position(enemy, pos, distance)
    if not use_prediction:get_bool() then
        return pos
    end

    local vel = get_entity_velocity(enemy)
    local t = pred_strength:get_float()

    if net_channel and net_channel.latency then
        local ok, latency = pcall(net_channel.latency)
        if ok and latency and latency > 0 then
            t = t + clamp(latency * 0.5, 0.0, 0.08)
        end
    end

    t = t + clamp(distance / 9000.0, 0.0, 0.12)
    return pos + vel * t
end

local function can_see(local_handle, eye, target_handle, pos)
    local tr = Engine.TraceLine(eye, pos, local_handle)
    if not tr.hit then return true end
    return tr.hit_entity == target_handle
end

local function is_valid_enemy(enemy)
    return enemy and enemy:valid() and enemy:is_alive()
end

local function get_locked_enemy()
    if locked_handle == -1 then return nil end
    local ent = entity_list:by_handle(locked_handle)
    if is_valid_enemy(ent) then
        return ent
    end
    locked_handle = -1
    return nil
end

local function choose_target(local_handle, eye, current_angles)
    local best_enemy = nil
    local best_pos = nil
    local best_metric = math.huge
    local max_dist = max_distance:get_float()
    local max_fov = fov_deg:get_float()

    if ignore_fov_when_locked:get_bool() then
        local locked = get_locked_enemy()
        if locked then
            local pos = get_target_bone_position(locked)
            if pos then
                local dist = (pos - eye):Length()
                if dist <= max_dist then
                    local predicted = predict_position(locked, pos, dist)
                    if (not visible_only:get_bool()) or can_see(local_handle, eye, locked:get_handle(), predicted) then
                        return locked, predicted
                    end
                end
            end
        end
    end

    for _, enemy in ipairs(entity_list:enemies()) do
        if is_valid_enemy(enemy) then
            local pos = get_target_bone_position(enemy)
            if pos then
                local dist = (pos - eye):Length()
                if dist <= max_dist then
                    local predicted = predict_position(enemy, pos, dist)
                    if (not visible_only:get_bool()) or can_see(local_handle, eye, enemy:get_handle(), predicted) then
                        local target_angles = calc_angle(eye, predicted)
                        local dx, dy = angle_delta(current_angles, target_angles)
                        local ang = angle_len(dx, dy)
                        if ang <= max_fov and ang < best_metric then
                            best_metric = ang
                            best_enemy = enemy
                            best_pos = predicted
                        end
                    end
                end
            end
        end
    end

    return best_enemy, best_pos
end

local function should_run()
    if not enabled:get_bool() then return false end
    if not require_key:get_bool() then return true end

    local key = aim_key:get_int()
    if not key or key == 0 then return false end
    return input.is_key_down(key)
end

callbacks.on_local_death(function()
    locked_handle = -1
end)

callbacks.on_pre_createmove(function(cmd)
    if not should_run() then
        locked_handle = -1
        return
    end

    local local_handle = Engine.GetLocalPlayerHandle()
    if not local_handle or local_handle < 0 then return end
    if not Engine.IsEntityAlive(local_handle) then return end

    local eye = get_eye_pos(local_handle)
    local current = cmd:GetViewAngles()
    if not current then
        current = cmd:GetCameraAngles()
    end
    if not current then return end

    local target_enemy, target_pos = choose_target(local_handle, eye, current)
    if not target_enemy or not target_pos then
        locked_handle = -1
        return
    end

    locked_handle = target_enemy:get_handle()

    local desired = calc_angle(eye, target_pos)
    local dx, dy = angle_delta(current, desired)
    local mag = angle_len(dx, dy)
    if mag <= 0.0001 then return end

    local divisor = math.max(1.0, smooth:get_float())
    local step = mag / divisor
    step = clamp(step, 0.02, mag)

    local nx = dx / mag
    local ny = dy / mag

    local out = QAngle.new(
        normalize_pitch(current.x + nx * step),
        normalize_yaw(current.y + ny * step),
        0.0
    )

    cmd:SetViewAngles(out)
end)

callbacks.on_render(function()
    if not enabled:get_bool() then return end

    if draw_fov:get_bool() then
        local screen = Engine.GetScreenSize()
        local cx = screen.w * 0.5
        local cy = screen.h * 0.5
        local radius = math.min(screen.w, screen.h) * (fov_deg:get_float() / 180.0)
        render.circle(cx, cy, radius, 0.35, 0.75, 1.0, 0.45, 64, 1.0)
    end

    if draw_target:get_bool() and locked_handle ~= -1 then
        local ent = entity_list:by_handle(locked_handle)
        if ent and ent:valid() and ent:is_alive() then
            local pos = get_target_bone_position(ent)
            if pos then
                local s = Engine.WorldToScreen(pos)
                if s.visible then
                    render.circle(s.x, s.y, 6.0, 1.0, 0.25, 0.25, 0.9, 24, 1.5)
                end
            end
        end
    end
end)
