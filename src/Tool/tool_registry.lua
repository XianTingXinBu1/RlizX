-- RlizX Tool Registry

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.tool_registry"]

if not M then
  M = {}

  dofile(get_script_dir() .. "/../Hub/utils.lua")

  M.tools = {}

  function M.register_tool(name, definition, handler)
    if type(name) ~= "string" or name == "" then
      return false, "invalid tool name"
    end
    if type(definition) ~= "table" then
      return false, "invalid tool definition"
    end
    if type(handler) ~= "function" then
      return false, "invalid tool handler"
    end

    M.tools[name] = {
      definition = definition,
      handler = handler,
    }
    return true
  end

  function M.get_all_tools_definitions()
    local defs = {}
    local names = {}
    for name, _ in pairs(M.tools) do
      names[#names + 1] = name
    end
    table.sort(names)

    for _, name in ipairs(names) do
      defs[#defs + 1] = M.tools[name].definition
    end
    return defs
  end

  function M.get_tool_function(name)
    local tool = M.tools[name]
    return tool and tool.handler or nil
  end

  function M.execute_tool(name, arguments)
    local handler = M.get_tool_function(name)
    if not handler then
      return { error = "Tool not found: " .. tostring(name) }
    end

    local ok, result = pcall(handler, arguments or {})
    if not ok then
      return { error = "Tool execution failed: " .. tostring(result) }
    end

    if type(result) == "table" then
      return result
    end

    if result == nil then
      return { result = "" }
    end

    return { result = tostring(result) }
  end

  function M.is_tool_enabled(tool_name, config)
    if not config or type(config) ~= "table" then
      return false
    end
    if not config.tools or type(config.tools) ~= "table" then
      return false
    end
    return config.tools[tool_name] == true
  end

  function M.get_enabled_tools(config)
    local enabled = {}
    for name, _ in pairs(M.tools) do
      if M.is_tool_enabled(name, config) then
        enabled[#enabled + 1] = name
      end
    end
    table.sort(enabled)
    return enabled
  end

  package.loaded["rlizx.tool_registry"] = M
end

return M
