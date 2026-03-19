-- RlizX Path Utilities

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.path_utils"]

if not M then
  M = {}

  local active_root

  local function get_cwd()
    local p = io.popen("pwd 2>/dev/null")
    if not p then
      return "."
    end
    local line = p:read("*l")
    p:close()
    if not line or line == "" then
      return "."
    end
    return line
  end

  local function default_project_root()
    local here = M.to_absolute(get_script_dir())
    return M.collapse_path(here .. "/../..")
  end

  function M.collapse_path(path)
    local p = tostring(path or "")
    p = p:gsub("\\", "/")

    if p == "" then
      p = "."
    end

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

  function M.to_absolute(path)
    local p = tostring(path or "")
    p = p:gsub("\\", "/")

    if p == "" then
      p = "."
    end

    if p:sub(1, 1) == "/" then
      return M.collapse_path(p)
    end

    return M.collapse_path(get_cwd() .. "/" .. p)
  end

  function M.get_workspace_root()
    if not active_root then
      active_root = default_project_root()
    end
    return active_root
  end

  function M.set_workspace_root(path)
    if type(path) ~= "string" or path == "" then
      active_root = default_project_root()
      return false, "invalid workspace root"
    end

    active_root = M.collapse_path(path)
    return true
  end

  local function get_project_root(context)
    if type(context) == "table" and type(context.workspace_root) == "string" and context.workspace_root ~= "" then
      return M.collapse_path(context.workspace_root)
    end
    return active_root or default_project_root()
  end

  function M.normalize_path(path, context)
    local p = tostring(path or "")
    p = p:gsub("\\", "/")

    if p == "" then
      p = "."
    end

    if p:sub(1, 1) == "/" then
      return M.collapse_path(p)
    end

    return M.collapse_path(get_project_root(context) .. "/" .. p)
  end

  local function shell_quote(s)
    return string.format("%q", tostring(s or ""))
  end

  local resolve_realpath
  local is_within_root

  resolve_realpath = function(path)
    local quoted = shell_quote(path)
    local p = io.popen("readlink -f " .. quoted .. " 2>/dev/null")
    if p then
      local out = p:read("*l")
      p:close()
      if out and out ~= "" then
        return M.collapse_path(out)
      end
    end

    local cmd = "python3 -c "
      .. shell_quote("import os,sys; print(os.path.realpath(sys.argv[1]))")
      .. " " .. quoted .. " 2>/dev/null"
    local p2 = io.popen(cmd)
    if not p2 then
      return nil
    end
    local out2 = p2:read("*l")
    p2:close()
    if out2 and out2 ~= "" then
      return M.collapse_path(out2)
    end

    return nil
  end

  is_within_root = function(real_root, real_path)
    if not real_root or not real_path then
      return false
    end
    if real_path == real_root then
      return true
    end
    return real_path:sub(1, #real_root + 1) == (real_root .. "/")
  end

  function M.is_path_safe(path, context)
    if type(path) ~= "string" then
      return false, "路径必须是字符串"
    end
    if path:find("\0", 1, true) then
      return false, "路径包含非法字符"
    end

    local root = get_project_root(context)
    local resolved = M.normalize_path(path, context)

    if not (resolved == root or resolved:sub(1, #root + 1) == (root .. "/")) then
      return false, "路径超出项目根目录"
    end

    local real_root = resolve_realpath(root) or root
    local real_target = resolve_realpath(resolved)

    if not real_target then
      local parent = resolved:match("^(.*)/")
      if parent and parent ~= "" then
        local real_parent = resolve_realpath(parent)
        if real_parent and not is_within_root(real_root, real_parent) then
          return false, "路径超出项目根目录(软链接)"
        end
      end
      return true, resolved
    end

    if not is_within_root(real_root, real_target) then
      return false, "路径超出项目根目录(软链接)"
    end

    return true, resolved
  end

  function M.to_relative(abs_path, context)
    local root = get_project_root(context)
    if abs_path == root then
      return "."
    end
    if abs_path:sub(1, #root + 1) == (root .. "/") then
      return abs_path:sub(#root + 2)
    end
    return abs_path
  end

  package.loaded["rlizx.path_utils"] = M
end

return M