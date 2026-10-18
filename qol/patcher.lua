-- GDPatch patcher: press latching for Player2 input and tick-exact timer strings.

local MOD_ID = "qol"

local present = {}
for _, f in ipairs(GDPatch.get_pack().files) do present[f] = true end

local function replace_plain(s, old, new)
  local out, n, i = {}, 0, 1
  while true do
    local a, b = s:find(old, i, true)
    if not a then break end
    table.insert(out, s:sub(i, a - 1))
    table.insert(out, new)
    i = b + 1
    n = n + 1
  end
  table.insert(out, s:sub(i))
  return table.concat(out), n
end

local function indent_unit(src)
  return src:match("\nfunc [^\n]*\n([ \t]+)%S") or "\t"
end


local PLAYER = "Scripts/Player/Player2.gdc"

local READY = {
  stomp = { "!esperflight and onfloor == false and stomp == false and stomp_timer <= 0 and spawncooldown <= 0",
            { "esperflight", "onfloor", "stomp", "stomp_timer", "spawncooldown" } },
  shoot = { "(_reload == 0 and !unarmed) or endtrigger",
            { "_reload", "unarmed", "endtrigger" } },
  jump  = { "(slopecoyote > 0 and slopecooldown == 0) or (!stomp and !esperflight and jump_amnt < 3.0 and (can_multijump == true or (jump_missed == false and coyotetime > 0)))",
            { "slopecoyote", "slopecooldown", "stomp", "esperflight", "jump_amnt", "can_multijump", "jump_missed", "coyotetime" } },
  dash  = { "!esperflight and dash_timer <= 0 and spawncooldown <= 0",
            { "esperflight", "dash_timer", "spawncooldown" } },
  aim     = { "true", {} },
  restart = { "true", {} },
}

local HELPER = [==[

func _qol_just(action: StringName, can: bool = true) -> bool:
 if Engine.has_meta("qol_input"):
  return Engine.get_meta("qol_input").just(action, can)
 return Input.is_action_just_pressed(action)
]==]

if present[PLAYER] then
  GDPatch.patch_script_as_text(PLAYER, function(ctx, src)
    local a = src:find("\nfunc _physics_process(", 1, true)
    if not a then
      print("[qol] input: _physics_process not found in this game version, skipped")
      return src
    end
    local b = src:find("\nfunc ", a + 1, true) or (#src + 1)
    local body = src:sub(a, b - 1)

    local function declared(name)
      return src:find("[\n ]var " .. name .. "[%s:=]") ~= nil
    end

    local total = 0
    for action, spec in pairs(READY) do
      local expr = spec[1]
      for _, name in ipairs(spec[2]) do
        if not declared(name) then
          print("[qol] input: '" .. name .. "' missing, buffering off for " .. action)
          expr = "true"
          break
        end
      end
      local n
      body, n = replace_plain(body, 'Input.is_action_just_pressed("' .. action .. '")',
                              '_qol_just("' .. action .. '", ' .. expr .. ')')
      total = total + n
    end
    if total == 0 then
      print("[qol] input: no reads found in this game version, skipped")
      return src
    end

    local unit = indent_unit(src)
    local helper = HELPER:gsub("\n( +)", function(lead) return "\n" .. unit:rep(#lead) end)
    print("[qol] input: " .. total .. " reads in Player2._physics_process latched")
    return src:sub(1, a - 1) .. body .. src:sub(b) .. helper
  end)
else
  print("[qol] input: " .. PLAYER .. " not in pack, skipped")
end


local GLOBAL = "Scripts/System/global.gdc"
local tick_fix = GDPatch.get_config_option(MOD_ID, "timer", "tick_accurate")

local function insert_after_header(src, signature, line)
  local a = src:find(signature, 1, true)
  if not a then return src, false end
  local eol = src:find("\n", a, true)
  return src:sub(1, eol) .. line .. src:sub(eol + 1), true
end

if present[GLOBAL] then
  GDPatch.patch_script_as_text(GLOBAL, function(ctx, src)
    local unit = indent_unit(src)
    local ok
    src, ok = insert_after_header(src, "func _stat(statstring",
      unit .. "if Engine.has_meta(\"qol_ghost\"): Engine.get_meta(\"qol_ghost\").on_stat(statstring)\n")
    print("[qol] ghosts: stat events " .. (ok and "hooked" or "not found in this game version, timeline events limited"))
    src, ok = insert_after_header(src, "func check_player_entry(",
      unit .. "if Engine.get_meta(\"qol_practice\", false): return\n")
    print("[qol] practice: upload guard " .. (ok and "hooked" or "NOT FOUND"))
    if tick_fix == nil or tick_fix == true then
      src, ok = insert_after_header(src, "func _timestring(_t):",
        unit .. "if (_t is float or _t is int) and _t >= 0: _t = (float((roundi(_t * Engine.get_physics_ticks_per_second()) * 1000) / Engine.get_physics_ticks_per_second()) + 0.5) / 1000.0\n")
      print("[qol] timer: " .. (ok and "tick-exact _timestring" or "_timestring not found in this game version, skipped"))
    end
    return src
  end)
end


local POS_HOOKS = {
  { "Scripts/Stage Elements/core.gdc", 'global._stat("stCore")', "core" },
}

for _, hook in ipairs(POS_HOOKS) do
  local file, call, kind = hook[1], hook[2], hook[3]
  if present[file] then
    GDPatch.patch_script_as_text(file, function(ctx, src)
      local a, b = src:find(call, 1, true)
      if not a then
        print("[qol] ghosts: " .. kind .. " position not found in this game version, skipped")
        return src
      end
      local line_start = a
      while line_start > 1 and src:sub(line_start - 1, line_start - 1) ~= "\n" do
        line_start = line_start - 1
      end
      local indent = src:sub(line_start, a - 1):match("^([ \t]*)") or ""
      local eol = src:find("\n", b, true) or #src
      local line = indent .. 'if Engine.has_meta("qol_ghost"): Engine.get_meta("qol_ghost").on_event_pos("' .. kind .. '", global_position)\n'
      print("[qol] ghosts: " .. kind .. " positions hooked")
      return src:sub(1, eol) .. line .. src:sub(eol + 1)
    end)
  end
end


local function insert_after_line(src, needle, text)
  local a, b = src:find(needle, 1, true)
  if not a then return src, false end
  local line_start = a
  while line_start > 1 and src:sub(line_start - 1, line_start - 1) ~= "\n" do
    line_start = line_start - 1
  end
  local indent = src:sub(line_start, a - 1):match("^([ \t]*)") or ""
  local eol = src:find("\n", b, true) or #src
  return src:sub(1, eol) .. indent .. text .. "\n" .. src:sub(eol + 1), true
end

local ENEMY = "Scripts/Enemy/enemy.gdc"
if present[ENEMY] then
  GDPatch.patch_script_as_text(ENEMY, function(ctx, src)
    local ok
    src, ok = insert_after_line(src, 'global._stat("stEnemyKills")',
      'if Engine.has_meta("qol_ghost"): Engine.get_meta("qol_ghost").on_event_pos("kill", global_position)')
    print("[qol] ghosts: kill positions " .. (ok and "hooked" or "not found in this game version, skipped"))
    src, ok = insert_after_line(src, "energie -= _dmg",
      'if Engine.has_meta("qol_ghost"): Engine.get_meta("qol_ghost").on_enemy_hit(global_position, energie, _bar.max_value)')
    print("[qol] ghosts: enemy hits " .. (ok and "hooked" or "not found in this game version, skipped"))
    return src
  end)
end


local LC = "Scripts/UI/level_complete.gdc"
local PRACTICE = 'Engine.get_meta("qol_practice", false)'
if present[LC] then
  GDPatch.patch_script_as_text(LC, function(ctx, src)
    local unit = indent_unit(src)
    local n1, ok
    local n2
    src, n1 = replace_plain(src, "saves._savescore(global.currentlevel,", "if !" .. PRACTICE .. ": saves._savescore(global.currentlevel,")
    src, n2 = replace_plain(src, "_stop_record(saveghost)", "_stop_record(saveghost and !" .. PRACTICE .. ")")
    if n2 ~= 1 then n1 = 0 end
    src, ok = insert_after_header(src, "func _leaderboardstart(",
      unit .. "if " .. PRACTICE .. ": return\n")
    print("[qol] practice: score guard " .. (n1 == 1 and "hooked" or "NOT FOUND") .. ", leaderboard guard " .. (ok and "hooked" or "NOT FOUND"))
    return src
  end)
end
