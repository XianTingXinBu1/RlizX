local U = dofile(require("debug").getinfo(1, "S").source:sub(2):match("^(.*)/") .. "/utils.lua")

local M = {}

local function quote_path(path)
  return string.format('%q', path)
end

local function ensure_dir(path)
  os.execute("mkdir -p " .. quote_path(path))
end

local function remove_dir(path)
  os.execute("rm -rf " .. quote_path(path))
end

local function path_exists(path)
  local ok = os.execute("test -e " .. quote_path(path) .. " >/dev/null 2>&1")
  return ok == true or ok == 0
end

local function dir_exists(path)
  local ok = os.execute("test -d " .. quote_path(path) .. " >/dev/null 2>&1")
  return ok == true or ok == 0
end

local function list_dir(path)
  local p = io.popen("ls -1 " .. quote_path(path) .. " 2>/dev/null")
  if not p then return {} end

  local t = {}
  for line in p:lines() do
    if line ~= "." and line ~= ".." then
      t[#t + 1] = line
    end
  end
  p:close()
  table.sort(t)
  return t
end

local function is_valid_agent_name(name)
  return name and name:match("^[%w%-%_]+$") ~= nil
end

local function read_default_agent_config(root)
  local path = root .. "/../rlizx.config.json"
  local raw = U.read_file(path)
  if not raw then return nil end

  local openai = raw:match('"openai"%s*:%s*%{(.-)%}')
  if not openai then return nil end

  local model = U.json_get_string(openai, "model") or ""
  return string.format('{"model":"%s"}', U.json_escape(model))
end

local function agent_dir(agents_root, name)
  return agents_root .. "/" .. name
end

local function agent_cfg_dir(agents_root, name)
  return agent_dir(agents_root, name) .. "/.rlizx"
end

local function agent_cfg_path(agents_root, name)
  return agent_cfg_dir(agents_root, name) .. "/config.json"
end

local function agent_memory_dir(agents_root, name)
  return agent_cfg_dir(agents_root, name) .. "/memory"
end

function M.create_manager(base)
  local project_root = base .. "/../.."
  local agents_root = project_root .. "/agents"

  ensure_dir(agents_root)

  local manager = {
    agents_root = agents_root,
    current_agent = nil,
  }

  function manager.is_valid_name(name)
    return is_valid_agent_name(name)
  end

  function manager.init_agent(name)
    if not is_valid_agent_name(name) then
      return false, "非法名称，仅允许字母/数字/下划线/短横线"
    end

    local cfg_dir = agent_cfg_dir(agents_root, name)
    local cfg_path = agent_cfg_path(agents_root, name)

    ensure_dir(cfg_dir)
    ensure_dir(agent_memory_dir(agents_root, name))

    if not path_exists(cfg_path) then
      local default_cfg = read_default_agent_config(project_root) or "{}"
      if not U.write_file(cfg_path, default_cfg) then
        return false, "写入配置失败: " .. cfg_path
      end
    end

    return true
  end

  function manager.delete_agent(name)
    if not is_valid_agent_name(name) then
      return false, "非法名称，仅允许字母/数字/下划线/短横线"
    end

    local path = agent_dir(agents_root, name)
    if not dir_exists(path) then
      return false, "agent 不存在: " .. name
    end

    remove_dir(path)
    if manager.current_agent == name then
      manager.current_agent = nil
    end
    return true
  end

  function manager.list_agents()
    return list_dir(agents_root)
  end

  function manager.switch_agent(name)
    if not is_valid_agent_name(name) then
      return false, "非法名称，仅允许字母/数字/下划线/短横线"
    end

    local path = agent_dir(agents_root, name)
    if not dir_exists(path) then
      local ok, err = manager.init_agent(name)
      if not ok then
        return false, err
      end
    end

    manager.current_agent = name
    return true
  end

  return manager
end

return M
