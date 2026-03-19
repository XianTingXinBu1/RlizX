-- RlizX JSON Operations

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.json_ops"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")
  local PathUtils = dofile(get_script_dir() .. "/path_utils.lua")

  function M.encode_json(v)
    return U.json_encode(v)
  end

  function M.parse_key_path(key_path)
    if type(key_path) ~= "string" or key_path == "" then
      return nil
    end
    local keys = {}
    for part in key_path:gmatch("[^%.]+") do
      if part ~= "" then
        keys[#keys + 1] = part
      end
    end
    if #keys == 0 then
      return nil
    end
    return keys
  end

  function M.read_json(args, context)
    local path = args and args.path
    local key_path = args and args.key_path

    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end

    local safe, resolved = PathUtils.is_path_safe(path, context)
    if not safe then
      return { error = resolved }
    end

    local raw = U.read_file(resolved)
    if raw == nil then
      return { error = "文件不存在或不可读: " .. tostring(path) }
    end

    local ok, obj = pcall(U.json_parse, raw)
    if not ok or type(obj) ~= "table" then
      return { error = "JSON 解析失败" }
    end

    if not key_path or key_path == "" then
      return { result = obj }
    end

    local keys = M.parse_key_path(key_path)
    if not keys then
      return { error = "key_path 非法" }
    end

    local cur = obj
    for _, k in ipairs(keys) do
      if type(cur) ~= "table" then
        return { error = "key_path 不存在: " .. tostring(key_path) }
      end
      cur = cur[k]
      if cur == nil then
        return { error = "key_path 不存在: " .. tostring(key_path) }
      end
    end

    return { result = cur }
  end

  function M.write_json_key(args, context)
    local path = args and args.path
    local key_path = args and args.key_path
    local value = args and args.value
    local create_missing = args and args.create_missing == true

    if not path or path == "" then
      return { error = "缺少必需参数: path" }
    end
    if not key_path or key_path == "" then
      return { error = "缺少必需参数: key_path" }
    end

    local safe, resolved = PathUtils.is_path_safe(path, context)
    if not safe then
      return { error = resolved }
    end

    local raw = U.read_file(resolved)
    if raw == nil then
      return { error = "文件不存在或不可读: " .. tostring(path) }
    end

    local ok, obj = pcall(U.json_parse, raw)
    if not ok or type(obj) ~= "table" then
      return { error = "JSON 解析失败" }
    end

    local keys = M.parse_key_path(key_path)
    if not keys then
      return { error = "key_path 非法" }
    end

    local cur = obj
    for i = 1, #keys - 1 do
      local k = keys[i]
      if cur[k] == nil then
        if create_missing then
          cur[k] = {}
        else
          return { error = "key_path 不存在: " .. tostring(key_path) }
        end
      end
      if type(cur[k]) ~= "table" then
        return { error = "key_path 中间节点不是对象: " .. tostring(k) }
      end
      cur = cur[k]
    end

    cur[keys[#keys]] = value

    local encoded = M.encode_json(obj)
    local write_ok = U.write_file(resolved, encoded)
    if not write_ok then
      return { error = "写入失败: " .. tostring(path) }
    end

    return { result = { updated = true } }
  end

  function M.parse_write_json_value(raw_value)
    local parsed = raw_value
    if type(raw_value) ~= "string" then
      return parsed
    end

    local s = raw_value
    local ok, obj = pcall(U.json_parse, s)
    if ok and obj ~= nil then
      return obj
    end

    if s == "true" then
      return true
    end
    if s == "false" then
      return false
    end
    if s == "null" then
      return nil
    end

    local n = tonumber(s)
    if n ~= nil then
      return n
    end

    return parsed
  end

  package.loaded["rlizx.json_ops"] = M
end

return M