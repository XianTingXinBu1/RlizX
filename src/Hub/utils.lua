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

return M
