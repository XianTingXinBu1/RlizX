local M = {}

function M.script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

function M.read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local c = f:read("*a")
  f:close()
  return c
end

function M.write_file(path, content)
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.parse_env_line(line)
  local s = M.trim(line)
  if s == "" or s:sub(1, 1) == "#" then return nil end
  if s:sub(1, 7) == "export " then
    s = M.trim(s:sub(8))
  end
  local key, val = s:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$")
  if not key then return nil end
  val = M.trim(val)
  if val:sub(1, 1) == "\"" and val:sub(-1) == "\"" then
    val = val:sub(2, -2)
  elseif val:sub(1, 1) == "'" and val:sub(-1) == "'" then
    val = val:sub(2, -2)
  end
  return key, val
end

function M.read_env(path)
  local raw = M.read_file(path)
  if not raw then return {} end
  local env = {}
  for line in raw:gmatch("[^\r\n]+") do
    local key, val = M.parse_env_line(line)
    if key then
      env[key] = val
    end
  end
  return env
end

function M.json_escape(s)
  return (tostring(s)
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t"))
end

function M.json_unescape(s)
  return (tostring(s):gsub("\\n", "\n")
                     :gsub("\\r", "\r")
                     :gsub("\\t", "\t")
                     :gsub('\\"', '"')
                     :gsub("\\\\", "\\"))
end

function M.json_get_string(json, key)
  local pat = '"' .. key .. '"%s*:%s*"(.-)"'
  return json:match(pat)
end

function M.json_get_number(json, key)
  local pat = '"' .. key .. '"%s*:%s*([%d%.]+)'
  local v = json:match(pat)
  return v and tonumber(v) or nil
end

function M.json_get_bool(json, key)
  local true_pat = '"' .. key .. '"%s*:%s*true'
  if json:match(true_pat) then
    return true
  end

  local false_pat = '"' .. key .. '"%s*:%s*false'
  if json:match(false_pat) then
    return false
  end

  return nil
end

function M.json_parse(json_str)
  local result = {}

  local function parse_string(s, pos)
    local s_pos = s:find('"', pos)
    if not s_pos then return nil, pos end
    local e_pos = s_pos
    while true do
      e_pos = s:find('"', e_pos + 1)
      if not e_pos then return nil, pos end
      local bs_count = 0
      local i = e_pos - 1
      while i >= s_pos and s:sub(i, i) == "\\" do
        bs_count = bs_count + 1
        i = i - 1
      end
      if bs_count % 2 == 0 then
        break
      end
    end
    local str = s:sub(s_pos + 1, e_pos - 1)
    str = str:gsub('\\"', '"'):gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t"):gsub("\\\\", "\\")
    return str, e_pos + 1
  end

  local function parse_number(s, pos)
    local num_str = s:match("^[%d%.%+%-eE]+", pos)
    if not num_str then return nil, pos end
    return tonumber(num_str), pos + #num_str
  end

  local function parse_literal(s, pos)
    if s:sub(pos, pos + 3) == "true" then
      return true, pos + 4
    elseif s:sub(pos, pos + 4) == "false" then
      return false, pos + 5
    elseif s:sub(pos, pos + 3) == "null" then
      return nil, pos + 4
    end
    return nil, pos
  end

  local function skip_ws(s, pos)
    while pos <= #s and s:sub(pos, pos):match("%s") do
      pos = pos + 1
    end
    return pos
  end

  local function parse_value(s, pos)
    pos = skip_ws(s, pos)
    if pos > #s then return nil, pos end

    local c = s:sub(pos, pos)
    if c == '"' then
      return parse_string(s, pos)
    elseif c == "{" then
      local obj = {}
      pos = pos + 1
      pos = skip_ws(s, pos)
      if s:sub(pos, pos) == "}" then
        return obj, pos + 1
      end
      while true do
        pos = skip_ws(s, pos)
        if s:sub(pos, pos) ~= '"' then return nil, pos end
        local key, new_pos = parse_string(s, pos)
        if not key then return nil, pos end
        pos = skip_ws(s, new_pos)
        if s:sub(pos, pos) ~= ":" then return nil, pos end
        pos = pos + 1
        local val, new_pos2 = parse_value(s, pos)
        if val == nil and new_pos2 == pos then return nil, pos end
        obj[key] = val
        pos = skip_ws(s, new_pos2)
        if s:sub(pos, pos) == "}" then
          return obj, pos + 1
        end
        if s:sub(pos, pos) ~= "," then return nil, pos end
        pos = pos + 1
      end
    elseif c == "[" then
      local arr = {}
      pos = pos + 1
      pos = skip_ws(s, pos)
      if s:sub(pos, pos) == "]" then
        return arr, pos + 1
      end
      while true do
        local val, new_pos = parse_value(s, pos)
        if val == nil and new_pos == pos then return nil, pos end
        arr[#arr + 1] = val
        pos = skip_ws(s, new_pos)
        if s:sub(pos, pos) == "]" then
          return arr, pos + 1
        end
        if s:sub(pos, pos) ~= "," then return nil, pos end
        pos = pos + 1
      end
    elseif c:match("[%d%.%+%-]") then
      return parse_number(s, pos)
    else
      return parse_literal(s, pos)
    end
  end

  local value, end_pos = parse_value(json_str, 1)
  return value
end

return M
