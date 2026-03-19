-- RlizX Tool Call Parser

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

local M = package.loaded["rlizx.tool_call_parser"]

if not M then
  M = {}

  local U = dofile(get_script_dir() .. "/../Hub/utils.lua")

  function M.parse_response_json(response_body)
    local ok, data = pcall(U.json_parse, response_body)
    if not ok or type(data) ~= "table" then
      return nil, "响应不是合法 JSON"
    end
    return data
  end

  function M.get_assistant_message_from_body(response_body)
    local data, err = M.parse_response_json(response_body)
    if not data then
      return nil, err
    end

    local choices = data.choices
    if type(choices) ~= "table" or #choices == 0 then
      return nil, "响应缺少 choices"
    end

    local first = choices[1]
    if type(first) ~= "table" then
      return nil, "响应 choices[1] 非对象"
    end

    local message = first.message
    if type(message) ~= "table" then
      return nil, "响应缺少 message"
    end

    return message
  end

  function M.normalize_tool_calls(calls)
    if type(calls) ~= "table" then
      return {}
    end

    local tool_calls = {}
    for i, item in ipairs(calls) do
      if type(item) == "table" then
        if item.name and item.arguments ~= nil then
          tool_calls[#tool_calls + 1] = {
            id = tostring(item.id or ("tool_call_" .. tostring(i))),
            name = tostring(item.name),
            arguments = tostring(item.arguments),
          }
        else
          local id = tostring(item.id or ("tool_call_" .. tostring(i)))
          local func = item["function"]
          if type(func) == "table" then
            local name = func.name
            if type(name) == "string" and name ~= "" then
              local raw_args = func.arguments
              local args_str
              if type(raw_args) == "string" then
                args_str = raw_args
              elseif type(raw_args) == "table" then
                local JsonEncoder = dofile(get_script_dir() .. "/json_encoder.lua")
                args_str = JsonEncoder.encode_json(raw_args)
              else
                args_str = "{}"
              end

              tool_calls[#tool_calls + 1] = {
                id = id,
                name = name,
                arguments = args_str,
              }
            end
          end
        end
      end
    end

    return tool_calls
  end

  function M.parse_tool_calls(response_body)
    local message = M.get_assistant_message_from_body(response_body)
    if not message then
      return {}
    end
    return M.normalize_tool_calls(message.tool_calls)
  end

  function M.detect_tool_calls(response_body)
    local message = M.get_assistant_message_from_body(response_body)
    if not message then
      return false
    end

    local calls = M.normalize_tool_calls(message.tool_calls)
    return #calls > 0
  end

  package.loaded["rlizx.tool_call_parser"] = M
end

return M