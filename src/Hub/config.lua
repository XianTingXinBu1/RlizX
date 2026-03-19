local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

local function parse_tools_config(json)
  local tools = {}

  local tools_start = json:find('"tools"')
  if not tools_start then
    return tools
  end

  local obj_start = json:find('%{', tools_start)
  if not obj_start then
    return tools
  end

  local depth = 0
  local obj_end = obj_start

  for i = obj_start, #json do
    local c = json:sub(i, i)
    if c == '{' then
      depth = depth + 1
    elseif c == '}' then
      depth = depth - 1
      if depth == 0 then
        obj_end = i
        break
      end
    end
  end

  if depth ~= 0 then
    return tools
  end

  local tools_section = json:sub(obj_start + 1, obj_end - 1)

  for key in tools_section:gmatch('"(.-)"%s*:%s*true') do
    tools[key] = true
  end

  return tools
end

local function parse_openai_config(openai)
  local cfg = {}
  cfg.endpoint = U.json_get_string(openai, "endpoint")
  cfg.api_key = U.json_get_string(openai, "api_key")
  cfg.model = U.json_get_string(openai, "model")
  cfg.timeout = U.json_get_number(openai, "timeout")
  cfg.temperature = U.json_get_number(openai, "temperature")
  cfg.stream = U.json_get_bool(openai, "stream")
  cfg.ca_file = U.json_get_string(openai, "ca_file")
  cfg.verify_tls = U.json_get_bool(openai, "verify_tls")
  cfg.tools = parse_tools_config(openai)
  return cfg
end

local function parse_agent_config(raw)
  if not raw then return nil end
  local cfg = {}
  cfg.endpoint = U.json_get_string(raw, "endpoint")
  cfg.api_key = U.json_get_string(raw, "api_key")
  cfg.model = U.json_get_string(raw, "model")
  cfg.timeout = U.json_get_number(raw, "timeout")
  cfg.temperature = U.json_get_number(raw, "temperature")
  cfg.stream = U.json_get_bool(raw, "stream")
  cfg.ca_file = U.json_get_string(raw, "ca_file")
  cfg.verify_tls = U.json_get_bool(raw, "verify_tls")
  cfg.tools = parse_tools_config(raw)
  return cfg
end

local function merge_config(base, override)
  if not override then return base end

  local function apply_string(key)
    if override[key] and override[key] ~= "" then
      base[key] = override[key]
    end
  end

  local function apply_value(key)
    if override[key] ~= nil then
      base[key] = override[key]
    end
  end

  apply_string("endpoint")
  apply_string("api_key")
  apply_string("model")
  apply_string("ca_file")
  apply_value("timeout")
  apply_value("temperature")
  apply_value("stream")
  apply_value("verify_tls")

  if override.tools then
    base.tools = override.tools
  end

  return base
end

function M.load_config(agent_name)
  local base = U.script_dir()
  local path = base .. "/../../rlizx.config.json"
  local raw = U.read_file(path)
  if not raw then
    return nil, "配置文件不存在: " .. path
  end

  local openai_start = raw:find('"openai"%s*:%s*%{')
  if not openai_start then
    return nil, "配置缺少 openai 段"
  end

  local obj_start = raw:find('%{', openai_start)
  local depth = 0
  local obj_end = obj_start

  for i = obj_start, #raw do
    local c = raw:sub(i, i)
    if c == '{' then
      depth = depth + 1
    elseif c == '}' then
      depth = depth - 1
      if depth == 0 then
        obj_end = i
        break
      end
    end
  end

  if depth ~= 0 then
    return nil, "配置格式错误：openai 部分未正确闭合"
  end

  local openai = raw:sub(obj_start + 1, obj_end - 1)

  local cfg = parse_openai_config(openai)
  cfg.timeout = cfg.timeout or 60
  cfg.temperature = cfg.temperature or 0.2
  cfg.stream = cfg.stream == true
  cfg.verify_tls = cfg.verify_tls == true

  if agent_name and agent_name ~= "" then
    local agent_path = base .. "/../../agents/" .. agent_name .. "/.rlizx/config.json"
    local agent_raw = U.read_file(agent_path)
    if agent_raw then
      local agent_cfg = parse_agent_config(agent_raw)
      cfg = merge_config(cfg, agent_cfg)
    end
  end

  local env_file = base .. "/../../.env"
  local env_map = U.read_env(env_file)
  local file_endpoint = env_map.OPENAI_ENDPOINT
  if file_endpoint and file_endpoint ~= "" then
    cfg.endpoint = file_endpoint
  else
    local env_endpoint = os.getenv("OPENAI_ENDPOINT")
    if env_endpoint and env_endpoint ~= "" then
      cfg.endpoint = env_endpoint
    end
  end

  local file_api_key = env_map.OPENAI_API_KEY
  if file_api_key and file_api_key ~= "" then
    cfg.api_key = file_api_key
  else
    local env_api_key = os.getenv("OPENAI_API_KEY")
    if env_api_key and env_api_key ~= "" then
      cfg.api_key = env_api_key
    end
  end

  if not cfg.endpoint or cfg.endpoint == "" then
    return nil, "openai.endpoint 未配置"
  end
  if not cfg.api_key or cfg.api_key == "" then
    return nil, "openai.api_key 未配置"
  end
  if not cfg.model or cfg.model == "" then
    return nil, "openai.model 未配置"
  end

  return cfg
end

return M
