-- RlizX JSON Encoder

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.json_encoder"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")

  local function is_array(t)
    if type(t) ~= "table" then
      return false
    end
    local max = 0
    local count = 0
    for k, _ in pairs(t) do
      if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
        return false
      end
      if k > max then
        max = k
      end
      count = count + 1
    end
    return max == count
  end

  function M.encode_json(v)
    local tv = type(v)
    if tv == "nil" then
      return "null"
    elseif tv == "boolean" then
      return v and "true" or "false"
    elseif tv == "number" then
      return tostring(v)
    elseif tv == "string" then
      return '"' .. U.json_escape(v) .. '"'
    elseif tv == "table" then
      if is_array(v) then
        local parts = {}
        for i = 1, #v do
          parts[#parts + 1] = M.encode_json(v[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
      end

      local keys = {}
      for k, _ in pairs(v) do
        keys[#keys + 1] = tostring(k)
      end
      table.sort(keys)

      local parts = {}
      for _, k in ipairs(keys) do
        parts[#parts + 1] = string.format('"%s":%s', U.json_escape(k), M.encode_json(v[k]))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end

    return '""'
  end

  package.loaded["rlizx.json_encoder"] = M
end

return M