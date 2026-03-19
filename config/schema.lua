-- RlizX Config Schema
-- 简化的配置系统

local M = {}

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function get_config_file()
  local base = get_script_dir()
  base = base:gsub("/config$", "")
  return base .. "/rlizx.config.json"
end

local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
end

local Registry = dofile(get_script_dir() .. "/../tools/registry.lua")

-- 读取配置
function M.load()
  local file = get_config_file()
  local f = io.open(file, "r")
  if not f then return nil end
  
  local content = f:read("*a")
  f:close()
  
  local ok, data = pcall(Registry.decode_json, content)
  if not ok or not data then return nil end
  
  return data
end

-- 保存配置
function M.save(config)
  local file = get_config_file()
  local f = io.open(file, "w")
  if not f then return false end
  
  f:write(Registry.encode_json(config))
  f:close()
  
  return true
end

-- 获取默认配置
function M.get_default()
  return {
    provider = "openai",
    model = "gpt-4",
    temperature = 0.7,
    api_key = "",
    endpoint = "https://api.openai.com/v1/chat/completions"
  }
end

-- 获取当前配置
function M.get_current()
  local config = M.load()
  if not config then
    return M.get_default()
  end
  return config
end

return M