-- RlizX Check module (extensible)
local M = {}

local function script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local c = f:read("*a")
  f:close()
  return c
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_env_line(line)
  local s = trim(line)
  if s == "" or s:sub(1, 1) == "#" then return nil end
  if s:sub(1, 7) == "export " then
    s = trim(s:sub(8))
  end
  local key, val = s:match("^([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.*)$")
  if not key then return nil end
  val = trim(val)
  if val:sub(1, 1) == "\"" and val:sub(-1) == "\"" then
    val = val:sub(2, -2)
  elseif val:sub(1, 1) == "'" and val:sub(-1) == "'" then
    val = val:sub(2, -2)
  end
  return key, val
end

local function read_env(path)
  local raw = read_file(path)
  if not raw then return {} end
  local env = {}
  for line in raw:gmatch("[^\r\n]+") do
    local key, val = parse_env_line(line)
    if key then
      env[key] = val
    end
  end
  return env
end

local function json_get_string(json, key)
  local pat = '"' .. key .. '"%s*:%s*"(.-)"'
  return json:match(pat)
end

local function json_get_number(json, key)
  local pat = '"' .. key .. '"%s*:%s*([%d%.]+)'
  local v = json:match(pat)
  return v and tonumber(v) or nil
end

local function load_config()
  local base = script_dir()
  local path = base .. "/../../rlizx.config.json"
  local raw = read_file(path)
  if not raw then
    return nil, "配置文件不存在: " .. path
  end

  local openai = raw:match('"openai"%s*:%s*%{(.-)%}')
  if not openai then
    return nil, "配置缺少 openai 段"
  end

  local cfg = {}
  cfg.endpoint = json_get_string(openai, "endpoint")
  cfg.api_key = json_get_string(openai, "api_key")
  cfg.model = json_get_string(openai, "model")
  cfg.timeout = json_get_number(openai, "timeout") or 60
  cfg.temperature = json_get_number(openai, "temperature") or 0.2
  cfg.ca_file = json_get_string(openai, "ca_file")
  cfg.verify_tls = openai:match('"verify_tls"%s*:%s*(true)') ~= nil

  local base = script_dir()
  local env_file = base .. "/../../.env"
  local env_map = read_env(env_file)
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

local function load_tls()
  local base = script_dir()
  local loader = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
  if not loader then
    return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
  end
  return loader()
end

local checks = {}

function M.register(name, fn)
  checks[#checks + 1] = { name = name, fn = fn }
end

function M.run_all()
  local ok_all = true
  for _, item in ipairs(checks) do
    local ok, msg = item.fn()
    if ok then
      io.stdout:write(string.format("[OK] %s\n", item.name))
      if msg and msg ~= "" then
        io.stdout:write("     " .. msg .. "\n")
      end
    else
      ok_all = false
      io.stdout:write(string.format("[FAIL] %s\n", item.name))
      if msg and msg ~= "" then
        io.stdout:write("       " .. msg .. "\n")
      end
    end
  end
  return ok_all
end

-- 默认检查项
M.register("config", function()
  local cfg, err = load_config()
  if not cfg then
    return false, err
  end
  return true, string.format("endpoint=%s", cfg.endpoint)
end)

M.register("tls_module", function()
  local tls, err = load_tls()
  if not tls then
    return false, err
  end
  return true, "tls.so loaded"
end)

return M
