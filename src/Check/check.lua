-- RlizX Check module (extensible)
local M = {}

local function script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local function load_config()
  local base = script_dir()
  local cfg_mod = dofile(base .. "/../Hub/config.lua")
  return cfg_mod.load_config(nil)
end

local function load_tls()
  local base = script_dir()
  local loader = package.loadlib(base .. "/../TLS/tls.so", "luaopen_tls")
  if not loader then
    return nil, "TLS 模块未编译: 请先在 src/TLS 目录下执行 make"
  end
  return loader()
end

local checks = {}

function M.register(name, fn)
  checks[#checks + 1] = { name = name, fn = fn }
end

function M.run_all()
  local ok_all = true
  for _, item in ipairs(checks) do
    local ok, msg = item.fn()
    if ok then
      io.stdout:write(string.format("[OK] %s\n", item.name))
      if msg and msg ~= "" then
        io.stdout:write("     " .. msg .. "\n")
      end
    else
      ok_all = false
      io.stdout:write(string.format("[FAIL] %s\n", item.name))
      if msg and msg ~= "" then
        io.stdout:write("       " .. msg .. "\n")
      end
    end
  end
  return ok_all
end

-- 默认检查项
M.register("config", function()
  local cfg, err = load_config()
  if not cfg then
    return false, err
  end
  return true, string.format("endpoint=%s", cfg.endpoint)
end)

M.register("tls_module", function()
  local tls, err = load_tls()
  if not tls then
    return false, err
  end
  return true, "tls.so loaded"
end)

return M
