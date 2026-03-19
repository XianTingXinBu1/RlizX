-- RlizX Providers Registry
-- LLM 提供商注册表

local M = {}

M.providers = {}

-- 注册提供商
function M.register(name, handler)
  M.providers[name] = handler
end

-- HTTP 请求
function M.request(config, system_prompt, messages)
  local provider = M.providers[config.provider or "openai"]
  if not provider then
    return nil, "Provider not found: " .. (config.provider or "openai")
  end
  
  return provider.request(config, system_prompt, messages)
end

-- OpenAI 提供商
local function openai_request(config, system_prompt, messages)
  local function get_script_dir()
    local info = debug.getinfo(1, "S")
    local src = info and info.source or ""
    if src:sub(1, 1) == "@" then
      src = src:sub(2)
    end
    return src:match("^(.*)/") or "."
  end
  
  local Registry
  if not Registry then
    local base = get_script_dir()
    base = base:gsub("/providers$", "")
    Registry = dofile(base .. "/tools/registry.lua")
  end
  
  local curl_cmd = string.format(
    'curl -s -X POST "%s" ',
    config.endpoint or "https://api.openai.com/v1/chat/completions"
  )
  
  curl_cmd = curl_cmd .. string.format(
    '-H "Content-Type: application/json" '
  )
  
  curl_cmd = curl_cmd .. string.format(
    '-H "Authorization: Bearer %s" ',
    config.api_key
  )
  
  local messages_json = Registry.encode_json(messages)
  local body = string.format(
    '{"model":"%s","messages":%s,"temperature":%s}',
    config.model or "gpt-4",
    messages_json,
    config.temperature or 0.7
  )
  
  curl_cmd = curl_cmd .. string.format(' -d \'%s\'', body)
  
  local p = io.popen(curl_cmd)
  if not p then return nil end
  
  local response = p:read("*a")
  p:close()
  
  local ok, data = pcall(Registry.decode_json, response)
  if not ok or not data or not data.choices then
    return nil, "Failed to parse response"
  end
  
  return data.choices[1].message.content
end

-- 注册默认提供商
M.register("openai", { request = openai_request })

return M