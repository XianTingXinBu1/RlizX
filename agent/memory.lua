-- RlizX Memory
-- 简单的记忆管理

local M = {}

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function shell_quote(s)
  return string.format("%q", tostring(s or ""))
end

local function ensure_dir(path)
  os.execute("mkdir -p " .. shell_quote(path))
end

local function get_memory_dir(agent_name)
  local base = get_script_dir()
  base = base:gsub("/agent$", "")
  local dir = base .. "/agents/" .. agent_name .. "/.rlizx/memory"
  ensure_dir(dir)
  return dir
end

-- 添加对话到记忆
function M.add(agent_name, conversation)
  local dir = get_memory_dir(agent_name)
  local timestamp = os.time()
  local filename = dir .. "/" .. timestamp .. ".json"
  
  local json_str = require("rlizx.tools.registry").encode_json(conversation)
  
  local f = io.open(filename, "w")
  if not f then return false end
  f:write(json_str)
  f:close()
  
  -- 只保留最近的 50 条记录
  M.cleanup(agent_name, 50)
  
  return true
end

-- 获取最近的对话
function M.get_recent(agent_name, limit)
  limit = limit or 10
  local dir = get_memory_dir(agent_name)
  
  local p = io.popen("ls -1t " .. shell_quote(dir) .. " 2>/dev/null | head -n " .. limit)
  if not p then return {} end
  
  local conversations = {}
  for filename in p:lines() do
    local full_path = dir .. "/" .. filename
    local f = io.open(full_path, "r")
    if f then
      local content = f:read("*a")
      f:close()
      local ok, data = pcall(require("rlizx.tools.registry").decode_json, content)
      if ok and data then
        conversations[#conversations + 1] = data
      end
    end
  end
  p:close()
  
  return conversations
end

-- 清理旧记录
function M.cleanup(agent_name, keep_count)
  keep_count = keep_count or 50
  local dir = get_memory_dir(agent_name)
  
  local p = io.popen("ls -1t " .. shell_quote(dir) .. " 2>/dev/null | tail -n +" .. (keep_count + 1))
  if not p then return end
  
  for filename in p:lines() do
    os.remove(dir .. "/" .. filename)
  end
  p:close()
end

return M