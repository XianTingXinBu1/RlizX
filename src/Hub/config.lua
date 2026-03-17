local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

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
  return cfg
end

local function parse_vector_config(vector)
  local cfg = {}
  cfg.endpoint = U.json_get_string(vector, "endpoint")
  cfg.api_key = U.json_get_string(vector, "api_key")
  cfg.model = U.json_get_string(vector, "model")
  cfg.timeout = U.json_get_number(vector, "timeout")
  cfg.ca_file = U.json_get_string(vector, "ca_file")
  cfg.verify_tls = U.json_get_bool(vector, "verify_tls")
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

  return base
end

function M.load_config(agent_name)
  local base = U.script_dir()
  local path = base .. "/../../rlizx.config.json"
  local raw = U.read_file(path)
  if not raw then
    return nil, "配置文件不存在: " .. path
  end

  local openai = raw:match('"openai"%s*:%s*%{(.-)%}')
  if not openai then
    return nil, "配置缺少 openai 段"
  end

  local vector = raw:match('"vector"%s*:%s*%{(.-)%}')

  local cfg = parse_openai_config(openai)
  cfg.timeout = cfg.timeout or 60
  cfg.temperature = cfg.temperature or 0.2
  cfg.stream = cfg.stream == true
  cfg.verify_tls = cfg.verify_tls == true

  cfg.vector = vector and parse_vector_config(vector) or {}
  cfg.vector.timeout = cfg.vector.timeout or 60
  cfg.vector.verify_tls = cfg.vector.verify_tls == true

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

  local v_file_endpoint = env_map.VECTOR_ENDPOINT
  if v_file_endpoint and v_file_endpoint ~= "" then
    cfg.vector.endpoint = v_file_endpoint
  else
    local v_env_endpoint = os.getenv("VECTOR_ENDPOINT")
    if v_env_endpoint and v_env_endpoint ~= "" then
      cfg.vector.endpoint = v_env_endpoint
    end
  end

  local v_file_api_key = env_map.VECTOR_API_KEY
  if v_file_api_key and v_file_api_key ~= "" then
    cfg.vector.api_key = v_file_api_key
  else
    local v_env_api_key = os.getenv("VECTOR_API_KEY")
    if v_env_api_key and v_env_api_key ~= "" then
      cfg.vector.api_key = v_env_api_key
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

  if cfg.vector.endpoint and cfg.vector.endpoint ~= "" then
    if not cfg.vector.api_key or cfg.vector.api_key == "" then
      return nil, "vector.api_key 未配置"
    end
    if not cfg.vector.model or cfg.vector.model == "" then
      return nil, "vector.model 未配置"
    end
  end

  return cfg
end

return M
