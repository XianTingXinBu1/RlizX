-- RlizX Hub layer (OpenAI compatible via TLS module)
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

local function json_escape(s)
  return (s:gsub("\\", "\\\\")
           :gsub("\"", "\\\"")
           :gsub("\n", "\\n")
           :gsub("\r", "\\r")
           :gsub("\t", "\\t"))
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

local function json_get_bool(json, key)
  local pat = '"' .. key .. '"%s*:%s*(true|false)'
  local v = json:match(pat)
  if v == "true" then return true end
  if v == "false" then return false end
  return nil
end

local function parse_openai_config(openai)
  local cfg = {}
  cfg.endpoint = json_get_string(openai, "endpoint")
  cfg.api_key = json_get_string(openai, "api_key")
  cfg.model = json_get_string(openai, "model")
  cfg.timeout = json_get_number(openai, "timeout")
  cfg.temperature = json_get_number(openai, "temperature")
  cfg.stream = json_get_bool(openai, "stream")
  cfg.ca_file = json_get_string(openai, "ca_file")
  cfg.verify_tls = json_get_bool(openai, "verify_tls")
  return cfg
end

local function parse_agent_config(raw)
  if not raw then return nil end
  local cfg = {}
  cfg.endpoint = json_get_string(raw, "endpoint")
  cfg.api_key = json_get_string(raw, "api_key")
  cfg.model = json_get_string(raw, "model")
  cfg.timeout = json_get_number(raw, "timeout")
  cfg.temperature = json_get_number(raw, "temperature")
  cfg.stream = json_get_bool(raw, "stream")
  cfg.ca_file = json_get_string(raw, "ca_file")
  cfg.verify_tls = json_get_bool(raw, "verify_tls")
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

local function load_config(agent_name)
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

  local cfg = parse_openai_config(openai)
  cfg.timeout = cfg.timeout or 60
  cfg.temperature = cfg.temperature or 0.2
  cfg.stream = cfg.stream == true
  cfg.verify_tls = cfg.verify_tls == true

  if agent_name and agent_name ~= "" then
    local agent_path = base .. "/../../agents/" .. agent_name .. "/.rlizx/config.json"
    local agent_raw = read_file(agent_path)
    if agent_raw then
      local agent_cfg = parse_agent_config(agent_raw)
      cfg = merge_config(cfg, agent_cfg)
    end
  end

  local env_endpoint = os.getenv("OPENAI_ENDPOINT")
  if env_endpoint and env_endpoint ~= "" then
    cfg.endpoint = env_endpoint
  end

  local env_api_key = os.getenv("OPENAI_API_KEY")
  if env_api_key and env_api_key ~= "" then
    cfg.api_key = env_api_key
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

local function parse_url(url)
  local scheme, rest = url:match("^(https?)://(.+)$")
  if not scheme then
    return nil, nil, nil, "endpoint 必须以 http:// 或 https:// 开头"
  end
  local host, port, path = rest:match("^([^:/]+):?(%d*)(/.*)$")
  if not host then
    host, port = rest:match("^([^:/]+):?(%d*)")
    path = "/"
  end
  port = (port and port ~= "") and tonumber(port) or (scheme == "https" and 443 or 80)
  return scheme, host, port, path
end

local function json_unescape(s)
  return (s:gsub("\\n", "\n")
           :gsub("\\r", "\r")
           :gsub("\\t", "\t")
           :gsub('\\"', '"')
           :gsub("\\\\", "\\"))
end

local function agent_role_path(base, agent_name, file)
  return base .. "/../../agents/" .. agent_name .. "/.rlizx/role/" .. file
end

local function agent_memory_path(base, agent_name)
  return base .. "/../../agents/" .. agent_name .. "/.rlizx/memory/work-memory.json"
end

local function read_role_text(base, agent_name)
  if not agent_name or agent_name == "" then return nil end
  local parts = {}

  local main = read_file(agent_role_path(base, agent_name, "main.md"))
  if main and main ~= "" then parts[#parts + 1] = main end

  local individuality = read_file(agent_role_path(base, agent_name, "individuality.md"))
  if individuality and individuality ~= "" then parts[#parts + 1] = individuality end

  local user = read_file(agent_role_path(base, agent_name, "user.md"))
  if user and user ~= "" then parts[#parts + 1] = user end

  if #parts == 0 then return nil end
  return table.concat(parts, "\n\n")
end

local function read_memory_list(base, agent_name)
  if not agent_name or agent_name == "" then return {} end
  local raw = read_file(agent_memory_path(base, agent_name))
  if not raw or raw == "" then return {} end

  local list = {}
  for obj in raw:gmatch("%b{}") do
    local role = obj:match('"role"%s*:%s*"(.-)"')
    local content = obj:match('"content"%s*:%s*"(.-)"')
    if role and content then
      list[#list + 1] = {
        role = json_unescape(role),
        content = json_unescape(content)
      }
    end
  end
  return list
end

local function build_system_text(base, agent_name)
  local parts = {}

  local role_text = read_role_text(base, agent_name)
  if role_text and role_text ~= "" then
    parts[#parts + 1] = role_text
  end

  local memory = read_memory_list(base, agent_name)
  if #memory > 0 then
    local lines = { "工作记忆:" }
    for _, item in ipairs(memory) do
      local role = item.role or ""
      local content = item.content or ""
      lines[#lines + 1] = role .. ": " .. content
    end
    parts[#parts + 1] = table.concat(lines, "\n")
  end

  if #parts == 0 then return nil end
  return table.concat(parts, "\n\n")
end

local function build_messages(base, agent_name, input)
  local messages = {}
  local system_text = build_system_text(base, agent_name)
  if system_text and system_text ~= "" then
    messages[#messages + 1] = { role = "system", content = system_text }
  end
  messages[#messages + 1] = { role = "user", content = tostring(input) }
  return messages
end

local function build_payload(model, messages, temperature, stream)
  local stream_val = stream and "true" or "false"

  local parts = {}
  for _, msg in ipairs(messages) do
    local role = json_escape(tostring(msg.role or "user"))
    local content = json_escape(tostring(msg.content or ""))
    parts[#parts + 1] = string.format('{"role":"%s","content":"%s"}', role, content)
  end

  return string.format(
    '{"model":"%s","temperature":%s,"stream":%s,"messages":[%s]}',
    json_escape(model), tostring(temperature), stream_val, table.concat(parts, ",")
  )
end

local function http_request(cfg, payload)
  local scheme, host, port, path, perr = parse_url(cfg.endpoint)
  if not scheme then
    return nil, perr
  end

  local req = table.concat({
    "POST ", path, " HTTP/1.1\r\n",
    "Host: ", host, "\r\n",
    "Content-Type: application/json\r\n",
    "Authorization: Bearer ", cfg.api_key, "\r\n",
    "Content-Length: ", tostring(#payload), "\r\n",
    "Connection: close\r\n\r\n",
    payload
  })

  local base = script_dir()
  local tls = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
  if not tls then
    return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
  end
  tls = tls()

  if scheme == "https" then
    local resp, err = tls.request(host, port, req, cfg.ca_file, cfg.timeout, cfg.verify_tls)
    if not resp then
      return nil, err
    end
    return resp
  end

  local resp, err = tls.tcp_request(host, port, req, cfg.timeout)
  if not resp then
    return nil, err
  end
  return resp
end

local function parse_http_body(resp)
  local body = resp:match("\r\n\r\n(.*)")
  return body or ""
end

local function parse_response(json)
  local content = json:match('"content"%s*:%s*"(.-)"')
  if content then
    return content:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t")
  end
  local err = json:match('"message"%s*:%s*"(.-)"')
  if err then
    return nil, err
  end
  return nil, "无法解析响应"
end

local function stream_request(cfg, payload)
  local scheme, host, port, path, perr = parse_url(cfg.endpoint)
  if not scheme then
    return nil, perr
  end

  local req = table.concat({
    "POST ", path, " HTTP/1.1\r\n",
    "Host: ", host, "\r\n",
    "Content-Type: application/json\r\n",
    "Authorization: Bearer ", cfg.api_key, "\r\n",
    "Content-Length: ", tostring(#payload), "\r\n",
    "Connection: close\r\n\r\n",
    payload
  })

  local base = script_dir()
  local tls = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
  if not tls then
    return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
  end
  tls = tls()

  local buffer = ""
  local in_body = false

  local function on_chunk(chunk)
    buffer = buffer .. chunk
    if not in_body then
      local idx = buffer:find("\r\n\r\n", 1, true)
      if not idx then
        return true
      end
      buffer = buffer:sub(idx + 4)
      in_body = true
    end

    while true do
      local s, e, line = buffer:find("data:%s*(.-)\r\n")
      if not s then
        break
      end
      buffer = buffer:sub(e + 1)
      if line == "[DONE]" then
        return false
      end
      local delta = line:match('"delta"%s*:%s*%{.-"content"%s*:%s*"(.-)"')
      if delta then
        local text = delta:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t")
        text = text:gsub("\\u0000", ""):gsub("%z", "")
        io.stdout:write(text)
        io.stdout:flush()
      end
    end

    return true
  end

  if scheme == "https" then
    local ok, err = tls.request_stream(host, port, req, cfg.ca_file, cfg.timeout, cfg.verify_tls, on_chunk)
    if not ok then
      return nil, err
    end
  else
    local ok, err = tls.tcp_request_stream(host, port, req, cfg.timeout, on_chunk)
    if not ok then
      return nil, err
    end
  end

  io.stdout:write("\n")
  return ""
end

function M.handle_request(input, agent_name)
  local cfg, err = load_config(agent_name)
  if not cfg then
    return "[Hub Config Error] " .. tostring(err)
  end

  local base = script_dir()
  local messages = build_messages(base, agent_name, input)
  local payload = build_payload(cfg.model, messages, cfg.temperature, cfg.stream)

  if cfg.stream then
    local _, err2 = stream_request(cfg, payload)
    if err2 then
      return "[Hub Stream Error] " .. tostring(err2)
    end
    return ""
  end

  local raw, err2 = http_request(cfg, payload)
  if not raw then
    return "[Hub Request Error] " .. tostring(err2)
  end

  local body = parse_http_body(raw)
  local text, err3 = parse_response(body)
  if not text then
    return "[Hub Response Error] " .. tostring(err3)
  end

  return text
end

return M
