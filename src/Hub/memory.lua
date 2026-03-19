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

local function decode_memory_list(raw)
  if not raw or raw == "" then
    return {}
  end

  local ok, parsed = pcall(U.json_parse, raw)
  if not ok or type(parsed) ~= "table" then
    return {}
  end

  local list = {}
  for _, item in ipairs(parsed) do
    if type(item) == "table" then
      local role = item.role
      local content = item.content
      if type(role) == "string" and type(content) == "string" then
        list[#list + 1] = {
          role = role,
          content = content,
        }
      end
    end
  end

  return list
end

function M.read_role_text(base, agent_name)
  if not agent_name or agent_name == "" then return nil end
  local parts = {}

  local ordered_files = {
    "memorandum.md",
    "main.md",
    "individuality.md",
    "agent.md",
    "user.md",
  }

  for _, file in ipairs(ordered_files) do
    local text = U.read_file(agent_role_path(base, agent_name, file))
    if text and text ~= "" then
      parts[#parts + 1] = text
    end
  end

  if #parts == 0 then return nil end
  return table.concat(parts, "\n\n")
end

function M.read_memory_list(base, agent_name)
  if not agent_name or agent_name == "" then return {} end
  local raw = U.read_file(agent_memory_path(base, agent_name))
  return decode_memory_list(raw)
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
  local list = decode_memory_list(raw)

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