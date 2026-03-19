-- RlizX Message Handler

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.message_handler"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")

  function M.message_to_text(message)
    if not message then
      return ""
    end

    local content = message.content
    if type(content) == "string" then
      return content
    end

    if type(content) == "table" then
      local parts = {}
      for _, item in ipairs(content) do
        if type(item) == "table" then
          if type(item.text) == "string" then
            parts[#parts + 1] = item.text
          elseif type(item.output_text) == "string" then
            parts[#parts + 1] = item.output_text
          end
        elseif type(item) == "string" then
          parts[#parts + 1] = item
        end
      end
      return table.concat(parts, "")
    end

    return ""
  end

  function M.build_payload_with_tools(messages, cfg)
    local Registry = dofile(get_script_dir() .. "/tool_registry.lua")

    local enabled_tools = Registry.get_enabled_tools(cfg)
    local all_defs = Registry.get_all_tools_definitions()

    local enabled_set = {}
    for _, name in ipairs(enabled_tools) do
      enabled_set[name] = true
    end

    local active_tools = {}
    for _, def in ipairs(all_defs) do
      local f = def and def["function"]
      local name = f and f.name
      if enabled_set[name] then
        active_tools[#active_tools + 1] = def
      end
    end

    local msg_parts = {}
    for _, msg in ipairs(messages or {}) do
      if msg.tool_calls then
        local call_parts = {}
        for _, tc in ipairs(msg.tool_calls) do
          call_parts[#call_parts + 1] = string.format(
            '{"id":"%s","type":"function","function":{"name":"%s","arguments":"%s"}}',
            U.json_escape(tostring(tc.id or "")),
            U.json_escape(tostring(tc.name or "")),
            U.json_escape(tostring(tc.arguments or "{}"))
          )
        end
        msg_parts[#msg_parts + 1] = string.format(
          '{"role":"assistant","tool_calls":[%s]}',
          table.concat(call_parts, ",")
        )
      elseif msg.role == "tool" then
        msg_parts[#msg_parts + 1] = string.format(
          '{"tool_call_id":"%s","role":"tool","content":"%s"}',
          U.json_escape(tostring(msg.tool_call_id or "")),
          U.json_escape(tostring(msg.content or ""))
        )
      else
        msg_parts[#msg_parts + 1] = string.format(
          '{"role":"%s","content":"%s"}',
          U.json_escape(tostring(msg.role or "user")),
          U.json_escape(tostring(msg.content or ""))
        )
      end
    end

    local tool_parts = {}
    for _, def in ipairs(active_tools) do
      local f = def["function"] or {}
      local params = f.parameters or { type = "object", properties = {}, required = {} }
      local properties = params.properties or {}
      local required = params.required or {}

      local prop_keys = {}
      for k, _ in pairs(properties) do
        prop_keys[#prop_keys + 1] = k
      end
      table.sort(prop_keys)

      local prop_parts = {}
      for _, key in ipairs(prop_keys) do
        local p = properties[key] or {}
        prop_parts[#prop_parts + 1] = string.format(
          '"%s":{"type":"%s","description":"%s"}',
          U.json_escape(tostring(key)),
          U.json_escape(tostring(p.type or "string")),
          U.json_escape(tostring(p.description or ""))
        )
      end

      local req_parts = {}
      for _, name in ipairs(required) do
        req_parts[#req_parts + 1] = string.format('"%s"', U.json_escape(tostring(name)))
      end

      local params_json = string.format(
        '{"type":"%s","properties":{%s},"required":[%s]}',
        U.json_escape(tostring(params.type or "object")),
        table.concat(prop_parts, ","),
        table.concat(req_parts, ",")
      )

      tool_parts[#tool_parts + 1] = string.format(
        '{"type":"function","function":{"name":"%s","description":"%s","parameters":%s}}',
        U.json_escape(tostring(f.name or "")),
        U.json_escape(tostring(f.description or "")),
        params_json
      )
    end

    local tools_json = "[" .. table.concat(tool_parts, ",") .. "]"

    return string.format(
      '{"model":"%s","temperature":%s,"stream":%s,"messages":[%s],"tools":%s}',
      U.json_escape(tostring(cfg.model or "")),
      tostring(cfg.temperature or 0),
      (cfg.stream and "true" or "false"),
      table.concat(msg_parts, ","),
      tools_json
    )
  end

  package.loaded["rlizx.message_handler"] = M
end

return M