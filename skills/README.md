# RlizX 技能系统

## 概述

RlizX 技能系统是一个三层渐进式披露的技能管理框架，允许 Agent 按需加载和使用自定义技能。

## 目录结构

```
skills/
├── example-skill/              # 示例技能
│   ├── SKILL.md               # 技能说明书（必需）
│   ├── scripts/               # 可执行脚本（可选）
│   │   └── example-script.lua
│   ├── references/            # 参考文档（可选）
│   │   └── example-guide.md
│   └── assets/                # 资源文件（可选）
│       └── example-template.txt
└── .skills_index.json         # 技能索引缓存（自动生成）
```

## SKILL.md 格式

每个技能必须包含 `SKILL.md` 文件，格式如下：

```markdown
# 技能名称

## 元数据
- Version: 1.0.0
- Author: 作者名
- Category: 分类标签
- Triggers: 关键词1, 关键词2  (可选)

## 描述
技能的详细描述和说明

## 使用场景
- 场景1：描述
- 场景2：描述

## 使用方法
详细的使用步骤和说明

## 依赖资源
- scripts: script1.lua, script2.lua
- references: doc1.md, doc2.md
- assets: template.txt, config.json

## 注意事项
使用时需要注意的事项
```

## 可用工具

技能系统提供了以下工具：

1. **`scan_available_skills`** - 扫描并列出所有可用的技能及其元数据
2. **`load_skill_info`** - 加载指定技能的完整详细信息
3. **`read_skill_resource`** - 读取指定技能的资源文件内容
4. **`search_skills`** - 根据关键词搜索技能
5. **`refresh_skills`** - 刷新技能注册表

## 工作流程

### 第一层：技能注册表
- 系统启动时自动扫描 `skills/` 目录
- 解析每个技能的 `SKILL.md` 元数据
- 构建轻量级技能注册表
- 将注册表注入系统提示词

### 第二层：按需加载
- 当 Agent 检测到需要使用某个技能时
- 调用 `load_skill_info` 工具
- 加载完整的技能文档和使用说明

### 第三层：资源访问
- 根据需要使用 `read_skill_resource` 工具
- 选择性读取脚本、参考文档或资源文件

## 配置

在 `rlizx.config.json` 中配置技能系统：

```json
{
  "openai": {
    "skills_enabled": true  // 启用技能系统（默认为 true）
  }
}
```

## 创建新技能

1. 在 `skills/` 目录下创建新目录，如 `my-skill/`
2. 创建必需的 `SKILL.md` 文件
3. 根据需要创建 `scripts/`、`references/`、`assets/` 目录
4. 刷新技能注册表：Agent 会自动检测新技能

## 示例

参考 `example-skill/` 目录中的示例技能了解最佳实践。

## 注意事项

- 技能名称只能包含字母、数字和连字符
- SKILL.md 必须使用 UTF-8 编码
- 元数据部分的字段名称必须使用英文
- 触发关键词用于智能触发，可选配置