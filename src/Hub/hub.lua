-- RlizX Hub layer (OpenAI compatible via TLS module)
local M = {}

local BASE_DIR = (debug.getinfo(1, "S").source:sub(2):match("^(.*)/") or ".")
local U = dofile(BASE_DIR .. "/utils.lua")
local Cfg = dofile(BASE_DIR .. "/config.lua")
local Http = dofile(BASE_DIR .. "/http.lua")
local Mem = dofile(BASE_DIR .. "/memory.lua")

local ToolExecutor = dofile(BASE_DIR .. "/../Tool/tool_executor.lua")
local FileManager = dofile(BASE_DIR .. "/../Tool/file_manager.lua")

FileManager.register()

local function make_error(code, message, detail)
  return {
    ok = false,
    code = tostring(code or "UNKNOWN"),
    message = tostring(message or "unknown error"),
    detail = detail,
  }
end

local function ok_result(data)
  return {
    ok = true,
    data = data,
  }
end

local function normalize_abs(path)
  local p = tostring(path or ""):gsub("\\", "/")
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then
      if #parts > 0 then
        table.remove(parts)
      end
    elseif seg ~= "." and seg ~= "" then
      parts[#parts + 1] = seg
    end
  end
  return "/" .. table.concat(parts, "/")
end

local function get_cwd()
  local p = io.popen("pwd 2>/dev/null")
  if not p then return "/" end
  local line = p:read("*l")
  p:close()
  if not line or line == "" then return "/" end
  return line
end

local function to_absolute(path)
  local p = tostring(path or ""):gsub("\\", "/")
  if p:sub(1, 1) == "/" then
    return normalize_abs(p)
  end
  return normalize_abs(get_cwd() .. "/" .. p)
end

local function get_workspace_root(base, agent_name)
  local base_abs = to_absolute(base)
  local project_root = normalize_abs(base_abs .. "/../..")
  if not agent_name or agent_name == "" then
    return project_root
  end
  return normalize_abs(project_root .. "/agents/" .. tostring(agent_name))
end

local function build_system_text(base, agent_name, _input, _cfg)
  local parts = {}

  local role_text = Mem.read_role_text(base, agent_name)
  if role_text and role_text ~= "" then
    parts[#parts + 1] = role_text
  end

  local workspace_root = get_workspace_root(base, agent_name)
  local structure_hint = table.concat({
    "路径与文件架构提示:",
    "- 当前工作区根目录: " .. workspace_root,
    "- 关键目录:",
    "  - .rlizx/config.json",
    "  - .rlizx/role/ (memorandum.md, main.md, individuality.md, agent.md, user.md)",
    "  - .rlizx/memory/",
    "- 读取 role 文件请使用 .rlizx/role/*.md 相对路径，不要省略目录。",
  }, "\n")
  parts[#parts + 1] = structure_hint

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

function M.append_memory(agent_name, role, content)
  if not agent_name or agent_name == "" then
    return false, "agent_name 为空"
  end
  local base = U.script_dir()
  Mem.append_memory_entry(base, agent_name, role, content)
  return true
end

function M.handle_request_result(input, agent_name, on_progress)
  local cfg, err = Cfg.load_config(agent_name)
  if not cfg then
    return make_error("CONFIG_ERROR", "配置加载失败", err)
  end

  local base = U.script_dir()
  local workspace_root = get_workspace_root(base, agent_name)
  cfg.workspace_root = workspace_root
  FileManager.set_workspace_root(workspace_root)
  local initial_messages = build_messages(base, agent_name, input, cfg)

  local text, err2 = ToolExecutor.handle_tool_loop(
    initial_messages,
    Http.http_request,
    cfg,
    on_progress
  )

  if not text then
    return make_error("TOOL_LOOP_ERROR", "工具调用失败", err2)
  end

  return ok_result(text)
end

function M.handle_request(input, agent_name, on_progress)
  local result = M.handle_request_result(input, agent_name, on_progress)
  if result.ok then
    return tostring(result.data or "")
  end

  local code = tostring(result.code or "UNKNOWN")
  local message = tostring(result.message or "unknown error")
  local detail = tostring(result.detail or "")
  if detail ~= "" then
    return string.format("[Hub Error][%s] %s: %s", code, message, detail)
  end
  return string.format("[Hub Error][%s] %s", code, message)
end

return M