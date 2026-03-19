local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

local function parse_tools_config(obj)
  local tools = {}
  if type(obj) ~= "table" then
    return tools
  end

  for key, value in pairs(obj) do
    if type(key) == "string" and value == true then
      tools[key] = true
    end
  end

  return tools
end

local function parse_tool_permissions(obj)
  local permissions = {
    read = true,
    write = true,
    git = true,
  }

  if type(obj) ~= "table" then
    return permissions
  end

  if obj.read ~= nil then
    permissions.read = obj.read == true
  end
  if obj.write ~= nil then
    permissions.write = obj.write == true
  end
  if obj.git ~= nil then
    permissions.git = obj.git == true
  end

  return permissions
end

local function parse_openai_config(openai)
  local cfg = {}
  if type(openai) ~= "table" then
    return cfg
  end

  cfg.endpoint = openai.endpoint
  cfg.api_key = openai.api_key
  cfg.model = openai.model
  cfg.timeout = openai.timeout
  cfg.temperature = openai.temperature
  cfg.stream = openai.stream
  cfg.ca_file = openai.ca_file
  cfg.verify_tls = openai.verify_tls
  cfg.tools = parse_tools_config(openai.tools)
  cfg.tool_permissions = parse_tool_permissions(openai.tool_permissions)
  return cfg
end

local function parse_agent_config(raw)
  if type(raw) ~= "table" then
    return nil
  end

  local cfg = {}
  cfg.endpoint = raw.endpoint
  cfg.api_key = raw.api_key
  cfg.model = raw.model
  cfg.timeout = raw.timeout
  cfg.temperature = raw.temperature
  cfg.stream = raw.stream
  cfg.ca_file = raw.ca_file
  cfg.verify_tls = raw.verify_tls
  cfg.tools = parse_tools_config(raw.tools)
  cfg.tool_permissions = parse_tool_permissions(raw.tool_permissions)
  return cfg
end

local function merge_config(base, override)
  if not override then return base end

  local function apply_string(key)
    if type(override[key]) == "string" and override[key] ~= "" then
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

  if type(override.tools) == "table" then
    base.tools = override.tools
  end

  if type(override.tool_permissions) == "table" then
    base.tool_permissions = override.tool_permissions
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

  local ok_parse, parsed = pcall(U.json_parse, raw)
  if not ok_parse or type(parsed) ~= "table" then
    return nil, "配置文件 JSON 解析失败"
  end

  local openai = parsed.openai
  if type(openai) ~= "table" then
    return nil, "配置缺少 openai 段"
  end

  local cfg = parse_openai_config(openai)
  cfg.timeout = tonumber(cfg.timeout) or 60
  cfg.temperature = tonumber(cfg.temperature) or 0.2
  cfg.stream = cfg.stream == true
  cfg.verify_tls = cfg.verify_tls == true
  if type(cfg.tool_permissions) ~= "table" then
    cfg.tool_permissions = parse_tool_permissions(nil)
  end

  if agent_name and agent_name ~= "" then
    local agent_path = base .. "/../../agents/" .. agent_name .. "/.rlizx/config.json"
    local agent_raw = U.read_file(agent_path)
    if agent_raw then
      local ok_agent_parse, agent_parsed = pcall(U.json_parse, agent_raw)
      if ok_agent_parse and type(agent_parsed) == "table" then
        local agent_cfg = parse_agent_config(agent_parsed)
        cfg = merge_config(cfg, agent_cfg)
      end
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

  if type(cfg.endpoint) ~= "string" or cfg.endpoint == "" then
    return nil, "openai.endpoint 未配置"
  end
  if type(cfg.api_key) ~= "string" or cfg.api_key == "" then
    return nil, "openai.api_key 未配置"
  end
  if type(cfg.model) ~= "string" or cfg.model == "" then
    return nil, "openai.model 未配置"
  end

  return cfg
end

return M