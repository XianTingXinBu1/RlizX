-- RlizX JSON Encoder
-- 使用成熟的 cjson 库进行 JSON 编码

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

  -- JSON 编码：Lua 表 -> JSON 字符串
  -- 使用 cjson 库，支持完整的 JSON 标准和 Unicode
  function M.encode_json(v)
    return U.json_encode(v)
  end

  package.loaded["rlizx.json_encoder"] = M
end

return M