-- minimal_keybinds.lua
-- VITTLOCK Lua API
-- Minimalistic animated keybind overlay.
-- Highlights use actual game actions from CUserCmd, so it reacts to your real binds.
-- Labels are loaded from bind files when possible, and can also self-learn from pressed keys.
-- Overlay position is controlled with X/Y sliders.

local m = ui.script()
m:category("Visuals")

local enabled = m:switch("Minimal Keybinds", true)

m:separator()
m:group("Layout")
local pos_x         = m:slider_int("Position X", 0, 3840, 40)
local pos_y         = m:slider_int("Position Y", 0, 2160, 420)
local scale         = m:slider_float("Scale", 0.70, 1.80, 1.00)
local gap_mul       = m:slider_float("Spacing", 0.60, 1.60, 1.00)
local animate_speed = m:slider_float("Animation speed", 4.0, 20.0, 10.0)

m:separator()
m:group("Style")
local theme_mode    = m:combo("Theme", {"Dark", "Light"}, 0)
local accent_color  = m:color("Accent color", {0.22, 0.68, 1.0, 1.0})
local box_alpha     = m:slider_float("Box alpha", 0.08, 1.00, 0.72)
local accent_alpha  = m:slider_float("Accent alpha", 0.05, 1.00, 0.25)
local outline_alpha = m:slider_float("Outline alpha", 0.02, 0.50, 0.09)

m:separator()
m:group("Bind source")
local auto_detect   = m:switch("Auto detect bind file", true)
local bind_path     = m:input_text("Manual bind file path", 260, "")
local auto_learn    = m:switch("Auto learn pressed keys", true)
local show_status   = m:switch("Show status text", false)

m:separator()
m:group("Ability overrides")
local override_a1   = m:keybind("Ability 1 override", 0)
local override_a2   = m:keybind("Ability 2 override", 0)
local override_a3   = m:keybind("Ability 3 override", 0)
local override_a4   = m:keybind("Ability 4 override", 0)

local want_reload_binds = false
local want_reset_pos = false
local want_reset_learned = false

m:button("Reload bind file", function()
    want_reload_binds = true
end)

m:button("Reset learned binds", function()
    want_reset_learned = true
end)

m:button("Reset position", function()
    want_reset_pos = true
end)

local STATE_PATH = "_agent/minimal_keybinds_state.json"

local ACTIONS = {
    { id = "Ability1", label = "A1", fallback = "1", button = InputBitMask_t.IN_ABILITY1 },
    { id = "Ability2", label = "A2", fallback = "2", button = InputBitMask_t.IN_ABILITY2 },
    { id = "Ability3", label = "A3", fallback = "3", button = InputBitMask_t.IN_ABILITY3 },
    { id = "Ability4", label = "A4", fallback = "4", button = InputBitMask_t.IN_ABILITY4 },
    { id = "MoveForward", label = "↑", fallback = "W", button = InputBitMask_t.IN_FORWARD },
    { id = "MoveLeft", label = "←", fallback = "A", button = InputBitMask_t.IN_MOVELEFT },
    { id = "MoveBackwards", label = "↓", fallback = "S", button = InputBitMask_t.IN_BACK },
    { id = "MoveRight", label = "→", fallback = "D", button = InputBitMask_t.IN_MOVERIGHT },
    { id = "Attack", label = "ATK", fallback = "MOUSE1", button = InputBitMask_t.IN_ATTACK },
    { id = "ADS", label = "ADS", fallback = "MOUSE2", button = InputBitMask_t.IN_ATTACK2, alt_id = "Attack2" },
}

local ACTION_INDEX = {}
for i = 1, #ACTIONS do
    ACTION_INDEX[ACTIONS[i].id] = ACTIONS[i]
end

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
    ["`"] = "`",
}

local VK_WHEEL_UP = -1001
local VK_WHEEL_DOWN = -1002

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

local VK_TO_NAME = {}
for name, vk in pairs(VK_MAP) do
    if VK_TO_NAME[vk] == nil then
        VK_TO_NAME[vk] = name
    end
end

local panel_x = 40
local panel_y = 420

local recent_keys = {}
local action_down = {}
local action_anim = {}
local learned_vks = {}
local bind_file_bindings = {}
local panel_status = "defaults"
local panel_path = ""
local last_bind_refresh = 0.0
local last_frame_time = 0.0

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

local function maybe_add(tbl, value)
    if not value or value == "" then return end
    for i = 1, #tbl do
        if tbl[i] == value then return end
    end
    tbl[#tbl + 1] = value
end

local function key_name_to_vk(name)
    local key = (name or ""):upper()
    if key == "" then return 0 end

    if VK_MAP[key] then return VK_MAP[key] end

    if #key == 1 then
        return string.byte(key) or 0
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

local function vk_to_key_name(vk)
    if not vk or vk == 0 then return "" end
    if VK_TO_NAME[vk] then return VK_TO_NAME[vk] end

    if vk >= 0x30 and vk <= 0x39 then
        return string.char(vk)
    end

    if vk >= 0x41 and vk <= 0x5A then
        return string.char(vk)
    end

    if vk >= 0x70 and vk <= 0x87 then
        return "F" .. tostring(vk - 0x6F)
    end

    if vk >= 0x60 and vk <= 0x69 then
        return "NUMPAD" .. tostring(vk - 0x60)
    end

    return tostring(vk)
end

local function pretty_key_name(name)
    local key = (name or ""):upper()
    if key == "" then return "?" end
    if PRETTY_KEY[key] then return PRETTY_KEY[key] end
    return key
end

local function pretty_vk(vk)
    return pretty_key_name(vk_to_key_name(vk))
end

local function build_label(key, modifier, secondary)
    local a = nil
    local b = nil

    if key and key ~= "" then
        a = pretty_key_name(key)
        if modifier and modifier ~= "" then
            a = pretty_key_name(modifier) .. "+" .. a
        end
    end

    if secondary and secondary ~= "" then
        b = pretty_key_name(secondary)
    end

    if a and b then return a .. "/" .. b end
    return a or b or "?"
end

local function make_binding_from_names(primary, modifier, secondary)
    return {
        primary = (primary or ""):upper(),
        modifier = (modifier or ""):upper(),
        secondary = (secondary or ""):upper(),
        label = build_label(primary, modifier, secondary),
        anim = 0.0,
    }
end

local function make_binding_from_vk(vk)
    local name = vk_to_key_name(vk)
    return make_binding_from_names(name, nil, nil)
end

local function fallback_binding(action)
    return make_binding_from_names(action.fallback, nil, nil)
end

local function safe_json_decode(raw)
    if not raw or raw == "" or not json or not json.decode then return nil end
    local ok, data = pcall(json.decode, raw)
    if ok then return data end
    return nil
end

local function save_state()
    if not fs or not json or not json.encode then return end
    fs.mkdir("_agent")

    local payload = {
        learned = learned_vks,
    }

    fs.write(STATE_PATH, json.encode(payload))
end

local function load_state()
    if not fs or not fs.exists or not fs.read then return end
    if not fs.exists(STATE_PATH) then return end

    local data = safe_json_decode(fs.read(STATE_PATH))
    if type(data) ~= "table" then return end
    if type(data.learned) == "table" then learned_vks = data.learned end
end

local parse_keyvalues

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
    local raw = io_read_all(normalize_path(steam_root .. "/config/loginusers.vdf"))
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
    if custom ~= "" then maybe_add(paths, custom) end

    if auto_detect:get_bool() then
        local roots = candidate_steam_roots()
        for i = 1, #roots do
            local root = roots[i]
            add_loginusers_bind_paths(paths, root)
            maybe_add(paths, normalize_path(root .. "/steamapps/common/Deadlock/game/citadel/cfg/user_keys_0_slot0.vcfg"))
            maybe_add(paths, normalize_path(root .. "/steamapps/common/Project8/game/citadel/cfg/user_keys_0_slot0.vcfg"))
            maybe_add(paths, normalize_path(root .. "/steamapps/common/Project8Staging/game/citadel/cfg/user_keys_0_slot0.vcfg"))
        end
    end

    return paths
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
    local hero_a_l = lower(hero_a or "")
    local hero_b_l = lower(hero_b or "")

    for i = 1, #profiles do
        local pname = lower(profiles[i].name)
        if hero_a_l ~= "" and pname == hero_a_l then return profiles[i] end
        if hero_b_l ~= "" and pname == hero_b_l then return profiles[i] end
    end

    for i = 1, #profiles do
        if lower(profiles[i].name) == "default" then return profiles[i] end
    end

    return profiles[1]
end

local function load_bind_file_once(path)
    local raw = io_read_all(path)
    if not raw then return false end

    local parsed = parse_keyvalues(raw)
    local profile = pick_profile(parsed)
    if not profile or type(profile.data.Keys) ~= "table" then return false end

    bind_file_bindings = {}
    for i = 1, #ACTIONS do
        local action = ACTIONS[i]
        local node = profile.data.Keys[action.id]
        if type(node) ~= "table" and action.alt_id then
            node = profile.data.Keys[action.alt_id]
        end

        if type(node) == "table" then
            bind_file_bindings[action.id] = make_binding_from_names(node.Key, node.Modifier, node.Key2)
        end
    end

    panel_status = "file: " .. tostring(profile.name)
    panel_path = path
    return true
end

local function refresh_bind_file(force)
    local now = Engine.GetCurTime()
    if not force and (now - last_bind_refresh) < 2.0 then return end
    last_bind_refresh = now
    want_reload_binds = false
    bind_file_bindings = {}

    local paths = candidate_bind_paths()
    for i = 1, #paths do
        if load_bind_file_once(paths[i]) then
            return
        end
    end

    panel_status = auto_learn:get_bool() and "learning keys" or "defaults"
    panel_path = ""
end

local function override_vk_for(action_id)
    if action_id == "Ability1" then return override_a1:get_int() end
    if action_id == "Ability2" then return override_a2:get_int() end
    if action_id == "Ability3" then return override_a3:get_int() end
    if action_id == "Ability4" then return override_a4:get_int() end
    return 0
end

local function get_binding_for_action(action)
    local manual_vk = override_vk_for(action.id)
    if manual_vk and manual_vk > 0 then
        local b = make_binding_from_vk(manual_vk)
        b.source = "manual"
        return b
    end

    local learned_vk = tonumber(learned_vks[action.id] or 0) or 0
    if learned_vk > 0 then
        local b = make_binding_from_vk(learned_vk)
        b.source = "learned"
        return b
    end

    if bind_file_bindings[action.id] then
        local b = bind_file_bindings[action.id]
        b.source = "file"
        if b.anim == nil then b.anim = 0.0 end
        return b
    end

    local b = fallback_binding(action)
    b.source = "fallback"
    return b
end

local function trim_recent_keys(now)
    local keep = {}
    for i = 1, #recent_keys do
        local e = recent_keys[i]
        if now - e.time <= 0.35 then
            keep[#keep + 1] = e
        end
    end
    recent_keys = keep
end

local function learn_action_key(action_id)
    if not auto_learn:get_bool() then return end

    local manual_vk = override_vk_for(action_id)
    if manual_vk and manual_vk > 0 then return end

    local now = Engine.GetCurTime()
    trim_recent_keys(now)

    for i = #recent_keys, 1, -1 do
        local vk = recent_keys[i].vk
        if vk and vk > 0 then
            learned_vks[action_id] = vk
            save_state()
            panel_status = "learned: " .. action_id
            return
        end
    end
end

local function measure_text_size(text, size)
    local w, h = render.measure_text(text or "", size)
    return w or 0, h or 0
end

local function draw_centered_text(x, y, w, h, text, size, r, g, b, a)
    local tw, th = measure_text_size(text, size)
    render.text(x + (w - tw) * 0.5, y + (h - th) * 0.5, r, g, b, a, text, size)
end

local function binding_width(binding, min_w, size, pad)
    local tw = measure_text_size(binding.label or "?", size)
    return math.max(min_w, tw + pad)
end

local function get_dt()
    local now = Engine.GetCurTime()
    if last_frame_time == 0.0 then last_frame_time = now end
    local dt = clamp(now - last_frame_time, 0.0, 0.10)
    last_frame_time = now
    return dt
end

local function get_theme_colors()
    local accent = accent_color:get_color()
    local theme = theme_mode:get_int()

    if theme == 1 then
        return {
            bg = {0.96, 0.96, 0.96, box_alpha:get_float()},
            shadow = {0.00, 0.00, 0.00, 0.05},
            outline = {0.00, 0.00, 0.00, outline_alpha:get_float() + 0.03},
            text = {0.08, 0.08, 0.08, 0.96},
            label = {0.35, 0.35, 0.35, 0.62},
            accent = {accent[1], accent[2], accent[3], accent_alpha:get_float()},
            accent_line = {accent[1], accent[2], accent[3], 0.45},
        }
    end

    return {
        bg = {0.055, 0.060, 0.075, box_alpha:get_float()},
        shadow = {0.00, 0.00, 0.00, 0.11},
        outline = {1.00, 1.00, 1.00, outline_alpha:get_float()},
        text = {0.96, 0.96, 0.96, 0.96},
        label = {1.00, 1.00, 1.00, 0.28},
        accent = {accent[1], accent[2], accent[3], accent_alpha:get_float()},
        accent_line = {accent[1], accent[2], accent[3], 0.55},
    }
end

local function draw_key_box(action_id, x, y, w, h, title, binding, is_down, dt, sc)
    action_anim[action_id] = ease(action_anim[action_id] or 0.0, is_down and 1.0 or 0.0, animate_speed:get_float(), dt)

    local anim = action_anim[action_id] or 0.0
    local yy = y - anim * (1.5 * sc)
    local rounding = 6.0 * sc
    local theme = get_theme_colors()

    render.filled_rect(x, yy + 1.0 * sc, w, h, theme.shadow[1], theme.shadow[2], theme.shadow[3], theme.shadow[4] + anim * 0.03, rounding)
    render.filled_rect(x, yy, w, h, theme.bg[1], theme.bg[2], theme.bg[3], theme.bg[4], rounding)
    render.filled_rect(x, yy, w, h, theme.accent[1], theme.accent[2], theme.accent[3], anim * theme.accent[4], rounding)
    render.rect(x, yy, w, h, theme.outline[1], theme.outline[2], theme.outline[3], theme.outline[4] + anim * 0.06, 1.0, rounding)

    render.line(x + 6.0 * sc, yy + h - 3.0 * sc, x + w - 6.0 * sc, yy + h - 3.0 * sc,
        theme.accent_line[1], theme.accent_line[2], theme.accent_line[3], 0.10 + anim * theme.accent_line[4], 1.2 * sc)

    render.text(x + 6.0 * sc, yy + 4.0 * sc,
        theme.label[1], theme.label[2], theme.label[3], theme.label[4] + anim * 0.10,
        title, 10.0 * sc)

    draw_centered_text(
        x, yy + 2.0 * sc, w, h - 2.0 * sc,
        binding.label or "?", 14.0 * sc,
        lerp(theme.text[1] * 0.92, theme.text[1], anim),
        lerp(theme.text[2] * 0.92, theme.text[2], anim),
        lerp(theme.text[3] * 0.92, theme.text[3], anim),
        lerp(0.82, theme.text[4], anim)
    )
end

local function is_action_active(cmd, action_id)
    if action_id == "MoveForward" then
        return cmd:HasButtonState(InputBitMask_t.IN_FORWARD) or cmd:GetForwardMove() > 0.01
    end
    if action_id == "MoveBackwards" then
        return cmd:HasButtonState(InputBitMask_t.IN_BACK) or cmd:GetForwardMove() < -0.01
    end
    if action_id == "MoveLeft" then
        return cmd:HasButtonState(InputBitMask_t.IN_MOVELEFT) or cmd:GetSideMove() < -0.01
    end
    if action_id == "MoveRight" then
        return cmd:HasButtonState(InputBitMask_t.IN_MOVERIGHT) or cmd:GetSideMove() > 0.01
    end

    local action = ACTION_INDEX[action_id]
    if not action then return false end
    return cmd:HasButtonState(action.button)
end

local function apply_slider_position(screen, panel_w, panel_h)
    if want_reset_pos then
        pos_x:set_int(math.floor(screen.w * 0.04))
        pos_y:set_int(math.floor(screen.h * 0.42))
        want_reset_pos = false
    end

    panel_x = clamp(pos_x:get_int(), 0, math.max(0, math.floor(screen.w - panel_w)))
    panel_y = clamp(pos_y:get_int(), 0, math.max(0, math.floor(screen.h - panel_h)))
end

callbacks.on_key_pressed(function(vk)
    recent_keys[#recent_keys + 1] = { vk = vk, time = Engine.GetCurTime() }
    if #recent_keys > 48 then
        table.remove(recent_keys, 1)
    end
end)

callbacks.on_pre_createmove(function(cmd)
    if not enabled:get_bool() then return end

    for i = 1, #ACTIONS do
        local action = ACTIONS[i]
        local active = is_action_active(cmd, action.id)
        if active and not action_down[action.id] then
            learn_action_key(action.id)
        end
        action_down[action.id] = active
    end
end)

callbacks.on_local_spawn(function()
    last_bind_refresh = 0.0
end)

callbacks.on_frame(function()
    if not enabled:get_bool() then return end

    if want_reset_learned then
        learned_vks = {}
        want_reset_learned = false
        save_state()
    end

    if want_reload_binds or last_bind_refresh == 0.0 then
        refresh_bind_file(true)
    else
        refresh_bind_file(false)
    end
end)

callbacks.on_render(function()
    if not enabled:get_bool() then return end

    local dt = get_dt()
    local sc = scale:get_float()
    local gap = 6.0 * sc * gap_mul:get_float()
    local pad = 10.0 * sc
    local title_h = 14.0 * sc
    local box_h = 34.0 * sc
    local base_move_box = 38.0 * sc
    local mouse_h = 32.0 * sc

    local ab1 = get_binding_for_action(ACTION_INDEX.Ability1)
    local ab2 = get_binding_for_action(ACTION_INDEX.Ability2)
    local ab3 = get_binding_for_action(ACTION_INDEX.Ability3)
    local ab4 = get_binding_for_action(ACTION_INDEX.Ability4)
    local fw  = get_binding_for_action(ACTION_INDEX.MoveForward)
    local lt  = get_binding_for_action(ACTION_INDEX.MoveLeft)
    local bk  = get_binding_for_action(ACTION_INDEX.MoveBackwards)
    local rt  = get_binding_for_action(ACTION_INDEX.MoveRight)
    local lmb = get_binding_for_action(ACTION_INDEX.Attack)
    local rmb = get_binding_for_action(ACTION_INDEX.ADS)

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
    if show_status:get_bool() then
        local status_text = panel_status
        if panel_path ~= "" then status_text = status_text .. "  •  " .. panel_path end
        local sw = measure_text_size(status_text, 10.0 * sc)
        inner_w = math.max(inner_w, sw)
    end

    local panel_w = inner_w + pad * 2.0
    local panel_h = pad * 2.0 + title_h + box_h + gap + move_box * 2.0 + gap + mouse_h
    if show_status:get_bool() then
        panel_h = panel_h + gap + 14.0 * sc
    end

    local screen = Engine.GetScreenSize()
    apply_slider_position(screen, panel_w, panel_h)

    local theme = get_theme_colors()
    render.text(panel_x + pad, panel_y + pad - 1.0 * sc, theme.label[1], theme.label[2], theme.label[3], 0.34, "keybinds", 12.0 * sc)

    local cy = panel_y + pad + title_h
    local ability_x = panel_x + pad + (inner_w - ability_total) * 0.5
    draw_key_box("Ability1", ability_x, cy, aw1, box_h, "A1", ab1, action_down.Ability1, dt, sc)
    draw_key_box("Ability2", ability_x + aw1 + gap, cy, aw2, box_h, "A2", ab2, action_down.Ability2, dt, sc)
    draw_key_box("Ability3", ability_x + aw1 + aw2 + gap * 2.0, cy, aw3, box_h, "A3", ab3, action_down.Ability3, dt, sc)
    draw_key_box("Ability4", ability_x + aw1 + aw2 + aw3 + gap * 3.0, cy, aw4, box_h, "A4", ab4, action_down.Ability4, dt, sc)

    cy = cy + box_h + gap
    local move_x = panel_x + pad + (inner_w - move_total) * 0.5
    draw_key_box("MoveForward", move_x + move_box + gap, cy, move_box, move_box, "↑", fw, action_down.MoveForward, dt, sc)

    cy = cy + move_box + gap
    draw_key_box("MoveLeft", move_x, cy, move_box, move_box, "←", lt, action_down.MoveLeft, dt, sc)
    draw_key_box("MoveBackwards", move_x + move_box + gap, cy, move_box, move_box, "↓", bk, action_down.MoveBackwards, dt, sc)
    draw_key_box("MoveRight", move_x + (move_box + gap) * 2.0, cy, move_box, move_box, "→", rt, action_down.MoveRight, dt, sc)

    cy = cy + move_box + gap
    local mouse_x = panel_x + pad + (inner_w - mouse_total) * 0.5
    draw_key_box("Attack", mouse_x, cy, mw1, mouse_h, "ATK", lmb, action_down.Attack, dt, sc)
    draw_key_box("ADS", mouse_x + mw1 + gap, cy, mw2, mouse_h, "ADS", rmb, action_down.ADS, dt, sc)

    if show_status:get_bool() then
        cy = cy + mouse_h + gap
        local status_text = panel_status
        if panel_path ~= "" then status_text = status_text .. "  •  " .. panel_path end
        render.text(panel_x + pad, cy, theme.label[1], theme.label[2], theme.label[3], 0.22, status_text, 10.0 * sc)
    end
end)

load_state()
