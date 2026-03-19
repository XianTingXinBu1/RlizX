#!/usr/bin/env lua
-- RlizX - 极简 AI 助手
-- 基于 nanobot 架构重构

local function get_script_dir()
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return src:match("^(.*)/") or "."
end

-- 添加模块路径
local base_dir = get_script_dir()
package.path = base_dir .. "/?.lua;" .. base_dir .. "/cli/?.lua;" .. base_dir .. "/agent/?.lua;" .. base_dir .. "/tools/?.lua;" .. base_dir .. "/scheduler/?.lua;" .. base_dir .. "/config/?.lua;" .. base_dir .. "/providers/?.lua;" .. base_dir .. "/bus/?.lua;" .. package.path

-- 主入口
local CLI = dofile(base_dir .. "/cli/main.lua")
CLI.main(arg)