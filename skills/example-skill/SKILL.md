# Example Skill

## 元数据
- Version: 1.0.0
- Author: RlizX Team
- Category: example
- Triggers: example, demo, test

## 描述
这是一个示例技能，用于演示 RlizX 技能系统的基本功能和使用方法。

## 使用场景
- 学习如何创建自定义技能
- 测试技能系统的加载和执行
- 作为开发新技能的参考模板

## 使用方法
1. 通过 scan_available_skills 工具查看可用技能
2. 当检测到触发关键词时，使用 load_skill_info 工具加载完整技能信息
3. 根据需要使用 read_skill_resource 工具读取额外的资源文件

## 依赖资源
- scripts: example-script.lua
- references: example-guide.md
- assets: example-template.txt

## 注意事项
- SKILL.md 文件必须位于技能目录的根目录
- 元数据部分必须包含 Version、Author、Category 字段
- Triggers 字段是可选的，用于智能触发