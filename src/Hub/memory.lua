local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

local WORK_MAX_MESSAGES = 10

local memory_cache = {}

local function agent_role_path(base, agent_name, file)
  return base .. "/../../agents/" .. agent_name .. "/.rlizx/role/" .. file
end

local function agent_memory_dir(base, agent_name)
  return base .. "/../../agents/" .. agent_name .. "/.rlizx/memory"
end

local function agent_memory_path(base, agent_name)
  return agent_memory_dir(base, agent_name) .. "/work-memory.json"
end

local function ensure_dir(path)
  os.execute("mkdir -p " .. path)
end

function M.read_role_text(base, agent_name)
  if not agent_name or agent_name == "" then return nil end
  local parts = {}

  local main = U.read_file(agent_role_path(base, agent_name, "main.md"))
  if main and main ~= "" then parts[#parts + 1] = main end

  local individuality = U.read_file(agent_role_path(base, agent_name, "individuality.md"))
  if individuality and individuality ~= "" then parts[#parts + 1] = individuality end

  local user = U.read_file(agent_role_path(base, agent_name, "user.md"))
  if user and user ~= "" then parts[#parts + 1] = user end

  if #parts == 0 then return nil end
  return table.concat(parts, "\n\n")
end

function M.read_memory_list(base, agent_name)
  if not agent_name or agent_name == "" then return {} end
  local raw = U.read_file(agent_memory_path(base, agent_name))
  if not raw or raw == "" then return {} end

  local list = {}
  for obj in raw:gmatch("%b{}") do
    local role = obj:match('"role"%s*:%s*"(.-)"')
    local content = obj:match('"content"%s*:%s*"(.-)"')
    if role and content then
      list[#list + 1] = {
        role = U.json_unescape(role),
        content = U.json_unescape(content)
      }
    end
  end
  return list
end

function M.save_memory_list(base, agent_name, list)
  local dir = agent_memory_dir(base, agent_name)
  ensure_dir(dir)
  local path = agent_memory_path(base, agent_name)

  local items = {}
  for _, item in ipairs(list) do
    local role = U.json_escape(item.role or "")
    local content = U.json_escape(item.content or "")
    items[#items + 1] = string.format('{"role":"%s","content":"%s"}', role, content)
  end

  local json = "[" .. table.concat(items, ",") .. "]"
  U.write_file(path, json)
end

local function load_memory_list(base, agent_name)
  if memory_cache[agent_name] then
    return memory_cache[agent_name]
  end

  local raw = U.read_file(agent_memory_path(base, agent_name))
  local list = {}
  if raw and raw ~= "" then
    for obj in raw:gmatch("%b{}") do
      local role = obj:match('"role"%s*:%s*"(.-)"')
      local content = obj:match('"content"%s*:%s*"(.-)"')
      if role and content then
        list[#list + 1] = {
          role = U.json_unescape(role),
          content = U.json_unescape(content)
        }
      end
    end
  end

  memory_cache[agent_name] = list
  return list
end

function M.append_memory_entry(base, agent_name, role, content)
  if not agent_name or agent_name == "" then return end
  if content == nil then return end

  local list = load_memory_list(base, agent_name)
  list[#list + 1] = { role = role, content = content }

  while #list > WORK_MAX_MESSAGES do
    table.remove(list, 1)
  end

  M.save_memory_list(base, agent_name, list)
end

return M
