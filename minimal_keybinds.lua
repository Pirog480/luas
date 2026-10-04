-- minimal_keybinds.lua
-- VITTLOCK Lua API
-- Minimalistic animated keybinds overlay for movement, abilities and mouse buttons.
-- Tries to read the user's real Deadlock binds from citadelkeys_personal.lst / user_keys_0_slot0.vcfg.

local m = ui.script()
m:category("Visuals")

local enabled = m:switch("Minimal Keybinds", true)

m:separator()
m:group("Layout")
local pos_x   = m:slider_int("Position X", 0, 3840, 40)
local pos_y   = m:slider_int("Position Y", 0, 2160, 420)
local scale   = m:slider_float("Scale", 0.70, 1.80, 1.00)
local gap_mul = m:slider_float("Spacing", 0.60, 1.60, 1.00)

m:separator()
m:group("Style")
local bg_alpha      = m:slider_float("Background alpha", 0.10, 1.00, 0.72)
local accent_alpha  = m:slider_float("Accent alpha", 0.05, 1.00, 0.25)
local outline_alpha = m:slider_float("Outline alpha", 0.02, 0.50, 0.09)
local animate_speed = m:slider_float("Animation speed", 4.0, 20.0, 10.0)

m:separator()
m:group("Bind file")
local auto_detect = m:switch("Auto detect bind file", true)
local bind_path   = m:input_text("Manual bind file path", 260, "")
local status_hint = m:switch("Show status text", false)

local requested_reload = false
m:button("Reload bind file", function()
    requested_reload = true
end)

local ACTIONS = {
    { id = "Ability1",       fallback = "1" },
    { id = "Ability2",       fallback = "2" },
    { id = "Ability3",       fallback = "3" },
    { id = "Ability4",       fallback = "4" },
    { id = "MoveForward",    fallback = "W" },
    { id = "MoveLeft",       fallback = "A" },
    { id = "MoveBackwards",  fallback = "S" },
    { id = "MoveRight",      fallback = "D" },
    { id = "Attack",         fallback = "MOUSE1" },
    { id = "ADS",            fallback = "MOUSE2", alt_id = "Attack2" },
}

local BIND_STATE = {}
local PANEL_STATUS = {
    source = "defaults",
    path = "",
    message = "using defaults",
}

local last_bind_refresh = 0.0
local last_frame_time = 0.0

local VK_WHEEL_UP = -1001
local VK_WHEEL_DOWN = -1002

local PRETTY_KEY = {
    ["MOUSE1"] = "LMB",
    ["MOUSE2"] = "RMB",
    ["MOUSE3"] = "MMB",
    ["MOUSE4"] = "MB4",
    ["MOUSE5"] = "MB5",
    ["MWHEELUP"] = "WH↑",
    ["MWHEELDOWN"] = "WH↓",
    ["SPACE"] = "SPACE",
    ["ENTER"] = "ENTER",
    ["ESCAPE"] = "ESC",
    ["BACKSPACE"] = "BSP",
    ["SHIFT"] = "SHIFT",
    ["CTRL"] = "CTRL",
    ["CONTROL"] = "CTRL",
    ["ALT"] = "ALT",
    ["CAPSLOCK"] = "CAPS",
    ["TAB"] = "TAB",
    ["INSERT"] = "INS",
    ["DELETE"] = "DEL",
    ["HOME"] = "HOME",
    ["END"] = "END",
    ["PAGEUP"] = "PGUP",
    ["PAGEDOWN"] = "PGDN",
    ["UP"] = "↑",
    ["DOWN"] = "↓",
    ["LEFT"] = "←",
    ["RIGHT"] = "→",
    ["UPARROW"] = "↑",
    ["DOWNARROW"] = "↓",
    ["LEFTARROW"] = "←",
    ["RIGHTARROW"] = "→",
    ["OEM_3"] = "`",
}

local VK_MAP = {
    ["MOUSE1"] = 0x01,
    ["MOUSE2"] = 0x02,
    ["MOUSE3"] = 0x04,
    ["MOUSE4"] = 0x05,
    ["MOUSE5"] = 0x06,
    ["BACKSPACE"] = 0x08,
    ["TAB"] = 0x09,
    ["ENTER"] = 0x0D,
    ["SHIFT"] = 0x10,
    ["CTRL"] = 0x11,
    ["CONTROL"] = 0x11,
    ["ALT"] = 0x12,
    ["PAUSE"] = 0x13,
    ["CAPSLOCK"] = 0x14,
    ["ESC"] = 0x1B,
    ["ESCAPE"] = 0x1B,
    ["SPACE"] = 0x20,
    ["PAGEUP"] = 0x21,
    ["PGUP"] = 0x21,
    ["PAGEDOWN"] = 0x22,
    ["PGDN"] = 0x22,
    ["END"] = 0x23,
    ["HOME"] = 0x24,
    ["LEFT"] = 0x25,
    ["UP"] = 0x26,
    ["RIGHT"] = 0x27,
    ["DOWN"] = 0x28,
    ["LEFTARROW"] = 0x25,
    ["UPARROW"] = 0x26,
    ["RIGHTARROW"] = 0x27,
    ["DOWNARROW"] = 0x28,
    ["INSERT"] = 0x2D,
    ["DELETE"] = 0x2E,
    ["NUMLOCK"] = 0x90,
    ["SCROLLLOCK"] = 0x91,
    ["LSHIFT"] = 0xA0,
    ["RSHIFT"] = 0xA1,
    ["LCTRL"] = 0xA2,
    ["RCTRL"] = 0xA3,
    ["LALT"] = 0xA4,
    ["RALT"] = 0xA5,
    [";"] = 0xBA,
    ["="] = 0xBB,
    [","] = 0xBC,
    ["-"] = 0xBD,
    ["."] = 0xBE,
    ["/"] = 0xBF,
    ["`"] = 0xC0,
    ["["] = 0xDB,
    ["\\"] = 0xDC,
    ["]"] = 0xDD,
    ["'"] = 0xDE,
    ["MWHEELUP"] = VK_WHEEL_UP,
    ["MWHEELDOWN"] = VK_WHEEL_DOWN,
}

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

local function split_lines(text)
    local lines = {}
    if not text or text == "" then return lines end

    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

local function normalize_path(path)
    return (path or ""):gsub("\\", "/")
end

local function io_read_all(path)
    if not io or not io.open or not path or path == "" then return nil end
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function io_file_exists(path)
    return io_read_all(path) ~= nil
end

local function maybe_add(tbl, value)
    if not value or value == "" then return end
    for i = 1, #tbl do
        if tbl[i] == value then
            return
        end
    end
    tbl[#tbl + 1] = value
end

local parse_keyvalues

local function candidate_steam_roots()
    local roots = {}
    local pf86 = os and os.getenv and os.getenv("ProgramFiles(x86)") or nil
    local pf = os and os.getenv and os.getenv("ProgramFiles") or nil
    local home_drive = os and os.getenv and os.getenv("SystemDrive") or 'C:'
    local steam_path = os and os.getenv and (os.getenv("SteamPath") or os.getenv("SteamDir")) or nil

    maybe_add(roots, normalize_path(steam_path or ""))
    maybe_add(roots, normalize_path((pf86 or "") .. "/Steam"))
    maybe_add(roots, normalize_path((pf or "") .. "/Steam"))
    maybe_add(roots, normalize_path((home_drive or 'C:') .. "/Steam"))
    maybe_add(roots, "C:/Program Files (x86)/Steam")
    maybe_add(roots, "C:/Program Files/Steam")
    maybe_add(roots, "C:/Steam")
    maybe_add(roots, "D:/Steam")
    maybe_add(roots, "E:/Steam")
    maybe_add(roots, "F:/Steam")
    maybe_add(roots, "G:/Steam")

    return roots
end

local function collect_steam_ids(node, primary, secondary)
    if type(node) ~= "table" then return end

    for k, v in pairs(node) do
        if type(v) == "table" then
            if type(k) == "string" and k:match("^%d+$") then
                local most_recent = tostring(v.MostRecent or v.mostrecent or "")
                if most_recent == "1" or most_recent:lower() == "true" then
                    maybe_add(primary, k)
                else
                    maybe_add(secondary, k)
                end
            end
            collect_steam_ids(v, primary, secondary)
        end
    end
end

local function add_loginusers_bind_paths(paths, steam_root)
    local loginusers_path = normalize_path(steam_root .. "/config/loginusers.vdf")
    local raw = io_read_all(loginusers_path)
    if not raw then return end

    local parsed = parse_keyvalues(raw)
    if type(parsed) ~= "table" then return end

    local preferred = {}
    local fallback = {}
    collect_steam_ids(parsed, preferred, fallback)

    for i = 1, #preferred do
        maybe_add(paths, normalize_path(steam_root .. "/userdata/" .. preferred[i] .. "/1422450/remote/cfg/citadelkeys_personal.lst"))
    end
    for i = 1, #fallback do
        maybe_add(paths, normalize_path(steam_root .. "/userdata/" .. fallback[i] .. "/1422450/remote/cfg/citadelkeys_personal.lst"))
    end
end

local function candidate_bind_paths()
    local paths = {}
    local custom = normalize_path(bind_path:get_string() or "")
    if custom ~= "" then
        maybe_add(paths, custom)
    end

    if auto_detect:get_bool() then
        local steam_roots = candidate_steam_roots()
        for i = 1, #steam_roots do
            local root = steam_roots[i]
            add_loginusers_bind_paths(paths, root)
            maybe_add(paths, root .. "/steamapps/common/Deadlock/game/citadel/cfg/user_keys_0_slot0.vcfg")
            maybe_add(paths, root .. "/steamapps/common/Project8/game/citadel/cfg/user_keys_0_slot0.vcfg")
            maybe_add(paths, root .. "/steamapps/common/Project8Staging/game/citadel/cfg/user_keys_0_slot0.vcfg")
        end
    end

    return paths
end

local function tokenize_keyvalues(text)
    local tokens = {}
    local i = 1
    local n = #text

    while i <= n do
        local ch = text:sub(i, i)

        if ch == '"' then
            local j = i + 1
            local buf = {}

            while j <= n do
                local c = text:sub(j, j)
                if c == '\\' and j < n then
                    buf[#buf + 1] = text:sub(j + 1, j + 1)
                    j = j + 2
                elseif c == '"' then
                    break
                else
                    buf[#buf + 1] = c
                    j = j + 1
                end
            end

            tokens[#tokens + 1] = { t = "string", v = table.concat(buf) }
            i = j + 1
        elseif ch == '{' or ch == '}' then
            tokens[#tokens + 1] = { t = ch }
            i = i + 1
        else
            i = i + 1
        end
    end

    return tokens
end

local function parse_keyvalues_object(tokens, index)
    local obj = {}
    local i = index

    while i <= #tokens do
        local tok = tokens[i]
        if tok.t == '}' then
            return obj, i + 1
        end

        if tok.t == "string" then
            local key = tok.v
            local nxt = tokens[i + 1]

            if nxt and nxt.t == '{' then
                local child
                child, i = parse_keyvalues_object(tokens, i + 2)
                obj[key] = child
            elseif nxt and nxt.t == "string" then
                obj[key] = nxt.v
                i = i + 2
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end

    return obj, i
end

parse_keyvalues = function(text)
    local tokens = tokenize_keyvalues(text or "")
    local root, _ = parse_keyvalues_object(tokens, 1)
    return root
end

local function collect_profiles(node, name, out)
    if type(node) ~= "table" then return end

    if type(node.Keys) == "table" then
        local profile_name = tostring(node.Name or name or ("profile_" .. tostring(#out + 1)))
        out[#out + 1] = { name = profile_name, data = node }
    end

    for k, v in pairs(node) do
        if type(v) == "table" then
            collect_profiles(v, k, out)
        end
    end
end

local function lower(s)
    return (s or ""):lower()
end

local function get_current_hero_candidates()
    local handle = Engine.GetLocalPlayerHandle()
    if not handle or handle < 0 then return nil, nil end

    local name = lower(Engine.GetEntityName(handle) or "")
    local slug = name:match("hero_([a-z0-9_]+)")
    if not slug then return nil, nil end

    return "hero_" .. slug, slug
end

local function pick_profile(root)
    local profiles = {}
    collect_profiles(root, nil, profiles)
    if #profiles == 0 then return nil end

    local hero_a, hero_b = get_current_hero_candidates()
    local hero_a_l = lower(hero_a)
    local hero_b_l = lower(hero_b)

    for i = 1, #profiles do
        local pname = lower(profiles[i].name)
        if hero_a_l ~= "" and pname == hero_a_l then
            return profiles[i]
        end
        if hero_b_l ~= "" and pname == hero_b_l then
            return profiles[i]
        end
    end

    for i = 1, #profiles do
        if lower(profiles[i].name) == "default" then
            return profiles[i]
        end
    end

    return profiles[1]
end

local function key_name_to_vk(name)
    local key = (name or ""):upper()
    if key == "" then return 0 end

    if VK_MAP[key] then return VK_MAP[key] end

    if #key == 1 then
        local byte = string.byte(key)
        if byte then
            return byte
        end
    end

    local fnum = key:match("^F(%d+)$")
    if fnum then
        local n = tonumber(fnum)
        if n and n >= 1 and n <= 24 then
            return 0x6F + n
        end
    end

    local np = key:match("^NUMPAD(%d)$")
    if np then
        return 0x60 + tonumber(np)
    end

    if key == "MULTIPLY" then return 0x6A end
    if key == "ADD" then return 0x6B end
    if key == "SUBTRACT" then return 0x6D end
    if key == "DECIMAL" then return 0x6E end
    if key == "DIVIDE" then return 0x6F end

    return 0
end

local function pretty_key_name(name)
    local key = (name or ""):upper()
    if key == "" then return "?" end
    if PRETTY_KEY[key] then return PRETTY_KEY[key] end
    return key
end

local function build_label(key, modifier)
    if not key or key == "" then return nil end
    local label = pretty_key_name(key)
    if modifier and modifier ~= "" then
        label = pretty_key_name(modifier) .. "+" .. label
    end
    return label
end

local function make_binding_from_names(primary, modifier, secondary)
    local label_a = build_label(primary, modifier)
    local label_b = build_label(secondary, nil)

    local label
    if label_a and label_b then
        label = label_a .. "/" .. label_b
    else
        label = label_a or label_b or "?"
    end

    return {
        primary = (primary or ""):upper(),
        modifier = (modifier or ""):upper(),
        secondary = (secondary or ""):upper(),
        label = label,
        primary_vk = key_name_to_vk(primary),
        modifier_vk = key_name_to_vk(modifier),
        secondary_vk = key_name_to_vk(secondary),
    }
end

local function fallback_binding(action)
    return make_binding_from_names(action.fallback, nil, nil)
end

local function get_action_table(keys, action)
    local node = keys and keys[action.id]
    if type(node) ~= "table" and action.alt_id then
        node = keys and keys[action.alt_id]
    end
    return node
end

local function rebuild_bind_state_from_profile(profile)
    local keys = profile and profile.data and profile.data.Keys or nil

    for i = 1, #ACTIONS do
        local action = ACTIONS[i]
        local old_anim = BIND_STATE[action.id] and BIND_STATE[action.id].anim or 0.0
        local fresh

        local node = get_action_table(keys, action)
        if type(node) == "table" then
            fresh = make_binding_from_names(node.Key, node.Modifier, node.Key2)
        else
            fresh = fallback_binding(action)
        end

        fresh.anim = old_anim
        BIND_STATE[action.id] = fresh
    end
end

local function load_bind_file_once(path)
    local raw = io_read_all(path)
    if not raw then return false end

    local parsed = parse_keyvalues(raw)
    local profile = pick_profile(parsed)
    if not profile then return false end

    rebuild_bind_state_from_profile(profile)
    PANEL_STATUS.source = profile.name
    PANEL_STATUS.path = path
    PANEL_STATUS.message = "binds: " .. profile.name
    return true
end

local function ensure_default_binds()
    for i = 1, #ACTIONS do
        local action = ACTIONS[i]
        local old_anim = BIND_STATE[action.id] and BIND_STATE[action.id].anim or 0.0
        BIND_STATE[action.id] = fallback_binding(action)
        BIND_STATE[action.id].anim = old_anim
    end
    PANEL_STATUS.source = "defaults"
    PANEL_STATUS.path = ""
    PANEL_STATUS.message = "using defaults"
end

local function refresh_bind_file(force)
    local now = Engine.GetCurTime()
    if not force and (now - last_bind_refresh) < 2.0 then
        return
    end
    last_bind_refresh = now
    requested_reload = false

    local paths = candidate_bind_paths()
    for i = 1, #paths do
        local p = normalize_path(paths[i])
        if io_file_exists(p) and load_bind_file_once(p) then
            return
        end
    end

    ensure_default_binds()
end

local function binding_is_down(binding)
    if not binding then return false end

    local function key_down(vk)
        if not vk or vk == 0 then return false end
        if vk == VK_WHEEL_UP then return input.get_scroll() > 0 end
        if vk == VK_WHEEL_DOWN then return input.get_scroll() < 0 end
        return input.is_key_down(vk)
    end

    local primary_down = key_down(binding.primary_vk)
    if binding.modifier_vk and binding.modifier_vk ~= 0 then
        primary_down = primary_down and key_down(binding.modifier_vk)
    end

    local secondary_down = key_down(binding.secondary_vk)
    return primary_down or secondary_down
end

local function measure_text_cached(text, size)
    local w, h = render.measure_text(text or "", size)
    return w or 0, h or 0
end

local function draw_centered_text(x, y, w, h, text, size, r, g, b, a)
    local tw, th = measure_text_cached(text, size)
    render.text(x + (w - tw) * 0.5, y + (h - th) * 0.5, r, g, b, a, text, size)
end

local function draw_key_box(x, y, w, h, title, binding, dt, sc)
    local target = binding_is_down(binding) and 1.0 or 0.0
    binding.anim = ease(binding.anim or 0.0, target, animate_speed:get_float(), dt)

    local anim = binding.anim or 0.0
    local yy = y - anim * (2.0 * sc)
    local rounding = 7.0 * sc

    local bg_a = bg_alpha:get_float()
    local accent_a = accent_alpha:get_float()
    local line_a = outline_alpha:get_float()

    render.filled_rect(x, yy + 2.0 * sc, w, h, 0.0, 0.0, 0.0, 0.12 + anim * 0.08, rounding)
    render.filled_rect(x, yy, w, h, 0.055, 0.060, 0.075, bg_a, rounding)
    render.filled_rect(x, yy, w, h, 0.15, 0.58, 1.00, anim * accent_a, rounding)
    render.rect(x, yy, w, h, 1.0, 1.0, 1.0, line_a + anim * 0.08, 1.0, rounding)
    render.filled_rect(x, yy + h - (2.0 * sc + anim * 2.0 * sc), w, 2.0 * sc + anim * 2.0 * sc,
        0.22, 0.68, 1.00, 0.10 + anim * 0.25, rounding)

    render.text(x + 6.0 * sc, yy + 4.0 * sc,
        1.0, 1.0, 1.0, 0.28 + anim * 0.18,
        title, 10.0 * sc)

    draw_centered_text(x, yy + 3.0 * sc, w, h - 3.0 * sc,
        binding.label or "?", 14.0 * sc,
        lerp(0.76, 1.00, anim),
        lerp(0.78, 1.00, anim),
        lerp(0.82, 1.00, anim),
        lerp(0.82, 1.00, anim))
end

local function binding_width(binding, min_w, size, pad)
    local tw = measure_text_cached(binding.label or "?", size)
    return math.max(min_w, tw + pad)
end

local function get_dt()
    local now = Engine.GetCurTime()
    if last_frame_time == 0.0 then
        last_frame_time = now
    end
    local dt = clamp(now - last_frame_time, 0.0, 0.10)
    last_frame_time = now
    return dt
end

callbacks.on_render(function()
    if not enabled:get_bool() then return end

    if requested_reload then
        refresh_bind_file(true)
    elseif last_bind_refresh == 0.0 then
        refresh_bind_file(true)
    else
        refresh_bind_file(false)
    end

    local dt = get_dt()
    local sc = scale:get_float()
    local gap = 6.0 * sc * gap_mul:get_float()
    local pad = 10.0 * sc
    local title_h = 14.0 * sc
    local box_h = 34.0 * sc
    local base_move_box = 38.0 * sc
    local mouse_h = 32.0 * sc

    local ab1 = BIND_STATE.Ability1 or fallback_binding(ACTIONS[1])
    local ab2 = BIND_STATE.Ability2 or fallback_binding(ACTIONS[2])
    local ab3 = BIND_STATE.Ability3 or fallback_binding(ACTIONS[3])
    local ab4 = BIND_STATE.Ability4 or fallback_binding(ACTIONS[4])
    local fw  = BIND_STATE.MoveForward or fallback_binding(ACTIONS[5])
    local lt  = BIND_STATE.MoveLeft or fallback_binding(ACTIONS[6])
    local bk  = BIND_STATE.MoveBackwards or fallback_binding(ACTIONS[7])
    local rt  = BIND_STATE.MoveRight or fallback_binding(ACTIONS[8])
    local lmb = BIND_STATE.Attack or fallback_binding(ACTIONS[9])
    local rmb = BIND_STATE.ADS or fallback_binding(ACTIONS[10])

    local ability_size = 14.0 * sc
    local move_size = 13.0 * sc
    local mouse_size = 13.0 * sc

    local aw1 = binding_width(ab1, 42.0 * sc, ability_size, 18.0 * sc)
    local aw2 = binding_width(ab2, 42.0 * sc, ability_size, 18.0 * sc)
    local aw3 = binding_width(ab3, 42.0 * sc, ability_size, 18.0 * sc)
    local aw4 = binding_width(ab4, 42.0 * sc, ability_size, 18.0 * sc)
    local ability_total = aw1 + aw2 + aw3 + aw4 + gap * 3.0

    local move_box = math.max(
        base_move_box,
        binding_width(fw, 0.0, move_size, 14.0 * sc),
        binding_width(lt, 0.0, move_size, 14.0 * sc),
        binding_width(bk, 0.0, move_size, 14.0 * sc),
        binding_width(rt, 0.0, move_size, 14.0 * sc)
    )
    local move_total = move_box * 3.0 + gap * 2.0

    local mw1 = binding_width(lmb, 62.0 * sc, mouse_size, 24.0 * sc)
    local mw2 = binding_width(rmb, 62.0 * sc, mouse_size, 24.0 * sc)
    local mouse_total = mw1 + mw2 + gap

    local inner_w = math.max(ability_total, move_total, mouse_total)
    if status_hint:get_bool() then
        local status_text = PANEL_STATUS.message
        if PANEL_STATUS.path ~= "" then
            status_text = status_text .. "  •  " .. PANEL_STATUS.path
        end
        local sw = measure_text_cached(status_text, 10.0 * sc)
        inner_w = math.max(inner_w, sw)
    end
    local panel_w = inner_w + pad * 2.0
    local panel_h = pad * 2.0 + title_h + box_h + gap + move_box * 2.0 + gap + mouse_h
    if status_hint:get_bool() then
        panel_h = panel_h + gap + 14.0 * sc
    end

    local screen = Engine.GetScreenSize()
    local x = clamp(pos_x:get_int(), 0, math.max(0, math.floor(screen.w - panel_w)))
    local y = clamp(pos_y:get_int(), 0, math.max(0, math.floor(screen.h - panel_h)))

    render.text(x + pad, y + pad - 1.0 * sc, 1.0, 1.0, 1.0, 0.34, "keybinds", 12.0 * sc)

    local cy = y + pad + title_h

    local ability_x = x + pad + (inner_w - ability_total) * 0.5
    draw_key_box(ability_x, cy, aw1, box_h, "A1", ab1, dt, sc)
    draw_key_box(ability_x + aw1 + gap, cy, aw2, box_h, "A2", ab2, dt, sc)
    draw_key_box(ability_x + aw1 + aw2 + gap * 2.0, cy, aw3, box_h, "A3", ab3, dt, sc)
    draw_key_box(ability_x + aw1 + aw2 + aw3 + gap * 3.0, cy, aw4, box_h, "A4", ab4, dt, sc)

    cy = cy + box_h + gap

    local move_x = x + pad + (inner_w - move_total) * 0.5
    draw_key_box(move_x + move_box + gap, cy, move_box, move_box, "↑", fw, dt, sc)

    cy = cy + move_box + gap
    draw_key_box(move_x, cy, move_box, move_box, "←", lt, dt, sc)
    draw_key_box(move_x + move_box + gap, cy, move_box, move_box, "↓", bk, dt, sc)
    draw_key_box(move_x + (move_box + gap) * 2.0, cy, move_box, move_box, "→", rt, dt, sc)

    cy = cy + move_box + gap

    local mouse_x = x + pad + (inner_w - mouse_total) * 0.5
    draw_key_box(mouse_x, cy, mw1, mouse_h, "ATK", lmb, dt, sc)
    draw_key_box(mouse_x + mw1 + gap, cy, mw2, mouse_h, "ADS", rmb, dt, sc)

    if status_hint:get_bool() then
        cy = cy + mouse_h + gap
        local text = PANEL_STATUS.message
        if PANEL_STATUS.path ~= "" then
            text = text .. "  •  " .. PANEL_STATUS.path
        end
        render.text(x + pad, cy, 1.0, 1.0, 1.0, 0.22, text, 10.0 * sc)
    end
end)
