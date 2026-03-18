-- RlizX Hub layer (OpenAI compatible via TLS module)
local M = {}

local BASE_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/") or ".")
local U = dofile(BASE_DIR .. "/utils.lua")
local Cfg = dofile(BASE_DIR .. "/config.lua")
local Http = dofile(BASE_DIR .. "/http.lua")
local Mem = dofile(BASE_DIR .. "/memory.lua")

local function build_system_text(base, agent_name, input, cfg)
  local parts = {}

  local role_text = Mem.read_role_text(base, agent_name)
  if role_text and role_text ~= "" then
    parts[#parts + 1] = role_text
  end

  local memory = Mem.read_memory_list(base, agent_name)
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

local function build_messages(base, agent_name, input, cfg)
  local messages = {}
  local system_text = build_system_text(base, agent_name, input, cfg)
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
    local role = U.json_escape(tostring(msg.role or "user"))
    local content = U.json_escape(tostring(msg.content or ""))
    parts[#parts + 1] = string.format('{"role":"%s","content":"%s"}', role, content)
  end

  return string.format(
    '{"model":"%s","temperature":%s,"stream":%s,"messages":[%s]}',
    U.json_escape(model), tostring(temperature), stream_val, table.concat(parts, ",")
  )
end

function M.append_memory(agent_name, role, content)
  if not agent_name or agent_name == "" then
    return false, "agent_name 为空"
  end
  local base = U.script_dir()
  Mem.append_memory_entry(base, agent_name, role, content)
  return true
end

function M.handle_request(input, agent_name)
  local cfg, err = Cfg.load_config(agent_name)
  if not cfg then
    return "[Hub Config Error] " .. tostring(err)
  end

  local base = U.script_dir()
  local messages = build_messages(base, agent_name, input, cfg)
  local payload = build_payload(cfg.model, messages, cfg.temperature, cfg.stream)

  if cfg.stream then
    local text, err2 = Http.stream_request(cfg, payload)
    if err2 then
      return "[Hub Stream Error] " .. tostring(err2)
    end
    return text
  end

  local raw, err2 = Http.http_request(cfg, payload)
  if not raw then
    return "[Hub Request Error] " .. tostring(err2)
  end

  local body = Http.parse_http_body(raw)
  local text, err3 = Http.parse_response(body)
  if not text then
    return "[Hub Response Error] " .. tostring(err3)
  end

  return text
end

return M
