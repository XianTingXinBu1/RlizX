local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

local WORK_MAX_MESSAGES = 10
local LONGTERM_MAX_ROUNDS = 1500

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

local function agent_longterm_path(base, agent_name)
  return agent_memory_dir(base, agent_name) .. "/long-term.db"
end

local function ensure_dir(path)
  os.execute("mkdir -p " .. path)
end

function M.ensure_longterm_file(base, agent_name)
  local dir = agent_memory_dir(base, agent_name)
  ensure_dir(dir)
  local path = agent_longterm_path(base, agent_name)
  if not U.read_file(path) then
    U.write_file(path, "[]")
  end
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

function M.read_longterm_list(base, agent_name)
  if not agent_name or agent_name == "" then return {} end
  local raw = U.read_file(agent_longterm_path(base, agent_name))
  if not raw or raw == "" then return {} end

  local list = {}
  for obj in raw:gmatch("%b{}") do
    local id = obj:match('"id"%s*:%s*(%d+)')
    local ts = obj:match('"ts"%s*:%s*(%d+)')
    local user = obj:match('"user"%s*:%s*"(.-)"')
    local assistant = obj:match('"assistant"%s*:%s*"(.-)"')
    local text = obj:match('"text"%s*:%s*"(.-)"')
    local segments = obj:match('"segments"%s*:%s*"(.-)"')
    local vectors = obj:match('"vectors"%s*:%s*"(.-)"')
    list[#list + 1] = {
      id = tonumber(id) or 0,
      ts = tonumber(ts) or 0,
      user = U.json_unescape(user or ""),
      assistant = U.json_unescape(assistant or ""),
      text = U.json_unescape(text or ""),
      segments = U.json_unescape(segments or ""),
      vectors = U.json_unescape(vectors or "")
    }
  end
  return list
end

function M.save_longterm_list(base, agent_name, list)
  local dir = agent_memory_dir(base, agent_name)
  ensure_dir(dir)
  local path = agent_longterm_path(base, agent_name)

  local items = {}
  for _, item in ipairs(list) do
    local id = tonumber(item.id) or 0
    local ts = tonumber(item.ts) or 0
    local user = U.json_escape(item.user or "")
    local assistant = U.json_escape(item.assistant or "")
    local text = U.json_escape(item.text or "")
    local segments = U.json_escape(item.segments or "")
    local vectors = U.json_escape(item.vectors or "")
    items[#items + 1] = string.format(
      '{"id":%d,"ts":%d,"user":"%s","assistant":"%s","text":"%s","segments":"%s","vectors":"%s"}',
      id, ts, user, assistant, text, segments, vectors
    )
  end

  local json = "[" .. table.concat(items, ",") .. "]"
  U.write_file(path, json)
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

local function next_round_id(list)
  local last = list[#list]
  if last and last.id then
    return last.id + 1
  end
  return 1
end

local function build_round_text(user_text, assistant_text)
  if user_text ~= "" and assistant_text ~= "" then
    return "user: " .. user_text .. "\nassistant: " .. assistant_text
  elseif user_text ~= "" then
    return "user: " .. user_text
  elseif assistant_text ~= "" then
    return "assistant: " .. assistant_text
  end
  return ""
end

local function archive_round(base, agent_name, user_item, assistant_item)
  local user_text = user_item and user_item.content or ""
  local assistant_text = assistant_item and assistant_item.content or ""
  if user_text == "" and assistant_text == "" then return end

  local list = M.read_longterm_list(base, agent_name)
  local entry = {
    id = next_round_id(list),
    ts = os.time(),
    user = user_text,
    assistant = assistant_text,
    text = build_round_text(user_text, assistant_text),
    segments = "",
    vectors = ""
  }

  list[#list + 1] = entry
  while #list > LONGTERM_MAX_ROUNDS do
    table.remove(list, 1)
  end

  M.save_longterm_list(base, agent_name, list)
end

function M.append_memory_entry(base, agent_name, role, content)
  if not agent_name or agent_name == "" then return end
  if content == nil then return end

  local list = load_memory_list(base, agent_name)
  list[#list + 1] = { role = role, content = content }

  while #list > WORK_MAX_MESSAGES do
    local user_item = table.remove(list, 1)
    local assistant_item = table.remove(list, 1)
    archive_round(base, agent_name, user_item, assistant_item)
  end

  M.save_memory_list(base, agent_name, list)
end

return M
