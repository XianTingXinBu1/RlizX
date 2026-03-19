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
  local path = root .. "/rlizx.config.json"
  local raw = U.read_file(path)
  if not raw then return nil end

  local openai_start = raw:find('"openai"%s*:%s*%{')
  if not openai_start then return nil end

  local obj_start = raw:find('%{', openai_start)
  if not obj_start then return nil end

  local depth = 0
  local obj_end = obj_start
  for i = obj_start, #raw do
    local c = raw:sub(i, i)
    if c == '{' then
      depth = depth + 1
    elseif c == '}' then
      depth = depth - 1
      if depth == 0 then
        obj_end = i
        break
      end
    end
  end

  if depth ~= 0 then return nil end

  local openai_obj = raw:sub(obj_start, obj_end)
  return openai_obj
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

local function agent_role_dir(agents_root, name)
  return agent_cfg_dir(agents_root, name) .. "/role"
end

local function agent_role_file_path(agents_root, name, file)
  return agent_role_dir(agents_root, name) .. "/" .. file
end

local function ensure_default_role_templates(agents_root, name)
  ensure_dir(agent_role_dir(agents_root, name))

  local templates = {
    ["memorandum.md"] = "备忘录\n*在此文件记录重要信息，并按需更新*\n\n1.index\n  通过多轮问答逐步了解用户信息\n  每轮只问少量关键问题，避免一次性列出很多问题\n  将确认后的信息写入 role，并持续修订\n",
    ["main.md"] = "主设定 - 我是谁？\n*在此文件持久化我的主要设定*\n\n\n1.我的名称：\n\n2.我的设定：\n\n3.\n",
    ["individuality.md"] = "个性设定 - 我的个性如何？\n*在此文件持久化我的个性设定*\n\n1.我的性别：\n\n2.我的个性：\n\n3.我的口头禅:\n\n4.我的风格：\n\n5.\n",
    ["agent.md"] = "工作设定 - 我该如何工作？\n*此文件持久化工作类设定*\n\n1.我的主要提示词由memorandum、main、individuality、agent.md、user.md等role提示词构成\n\n2.我应该在需要时修订role提示词\n\n3.我应该尽可能的避免高危命令\n",
    ["user.md"] = "用户个性化记录 - 用户是怎样的？\n*在此文件持久化用户的画像*\n\n1.用户名称：\n\n2.用户的时区：\n\n3.用户的所在地：\n\n4.用户偏好：\n\n5.\n",
  }

  local order = { "memorandum.md", "main.md", "individuality.md", "agent.md", "user.md" }
  for _, file in ipairs(order) do
    local path = agent_role_file_path(agents_root, name, file)
    if not path_exists(path) then
      U.write_file(path, templates[file])
    end
  end
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

    ensure_default_role_templates(agents_root, name)

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
