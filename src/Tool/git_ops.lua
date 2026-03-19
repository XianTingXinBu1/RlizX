-- RlizX Git Operations

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.git_ops"]

if not M then
  M = {}

  local PathUtils = dofile(get_script_dir() .. "/path_utils.lua")

  local function shell_quote(s)
    return string.format("%q", tostring(s or ""))
  end

  local function run_capture(cmd)
    local p = io.popen(cmd .. " 2>&1")
    if not p then
      return nil, "命令执行失败"
    end
    local out = p:read("*a") or ""
    p:close()
    return out
  end

  function M.git_status(args, _context)
    local short = not (args and args.short == false)
    local root = PathUtils.get_workspace_root()
    local cmd

    if short then
      cmd = "cd " .. shell_quote(root) .. " && git status --porcelain"
    else
      cmd = "cd " .. shell_quote(root) .. " && git status"
    end

    local out, err = run_capture(cmd)
    if not out then
      return { error = err or "git status 执行失败" }
    end

    return { result = out }
  end

  function M.git_diff(args, context)
    local staged = args and args.staged == true
    local path = args and args.path
    local root = PathUtils.get_workspace_root()

    local cmd = "cd " .. shell_quote(root) .. " && git diff"
    if staged then
      cmd = cmd .. " --staged"
    end

    if path and path ~= "" then
      local safe, resolved = PathUtils.is_path_safe(path, context)
      if not safe then
        return { error = resolved }
      end
      local rel = PathUtils.to_relative(resolved, context)
      if rel ~= "." then
        cmd = cmd .. " -- " .. shell_quote(rel)
      end
    end

    local out, err = run_capture(cmd)
    if not out then
      return { error = err or "git diff 执行失败" }
    end

    return { result = out }
  end

  package.loaded["rlizx.git_ops"] = M
end

return M