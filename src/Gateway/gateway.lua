-- RlizX Gateway layer
local M = {}

local function script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function load_hub()
  local base = script_dir()
  return dofile(base .. "/../Hub/hub.lua")
end

function M.handle_input(input, agent_name)
  local hub = load_hub()
  return hub.handle_request(input, agent_name)
end

function M.append_memory(agent_name, role, content)
  local hub = load_hub()
  return hub.append_memory(agent_name, role, content)
end

return M
