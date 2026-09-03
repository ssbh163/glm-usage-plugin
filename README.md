# glm-usage —— ZCode 插件:查询智谱 Coding Plan 额度

在 ZCode 中用智谱(Coding Plan)**API Key 登录**时,端内看不到 5 小时池和每周额度。本插件通过智谱官方监控接口(`/api/monitor/usage/*`,与官方 glm-plan-usage 插件同源)查询并展示全部额度:

- **5 小时 Prompt 池**:已用百分比、重置倒计时
- **每周额度**:已用百分比、重置时间
- **MCP 工具调用(每月)**:已用/总量、明细
- **近 24 小时模型用量**:调用次数、token 消耗、按模型汇总

**隐私**:插件不含任何密钥,脚本运行时才从你本机 ZCode 配置(`~/.zcode/v2/config.json`)读取你自己的 API Key,只发往智谱官方域名(open.bigmodel.cn / api.z.ai)。

## 安装

### 方式 A:从本地目录安装

1. ZCode → 设置 → 插件管理 → 发现(Discover)页
2. 点 **+** 添加市场,选择"本地目录",选中本仓库根目录
3. 在市场列表中找到 **glm-usage**,点击安装

### 方式 B:从 GitHub 安装(推荐分享方式)

把本仓库推到 GitHub 后:

1. ZCode → 设置 → 插件管理 → 发现 → **+** 添加市场
2. 选择 GitHub 仓库,填入仓库地址(如 `你的用户名/glm-usage-plugin`)
3. 安装 **glm-usage**

## 使用

安装后**新开一个对话**:

- 输入 `/glm-usage:usage`,或直接问"查一下 Coding Plan 用量/还剩多少额度"
- 也可以在终端直接运行脚本:

```bash
node "$(ls -d "$HOME/.zcode/cli/plugins/cache"/*/glm-usage/*/skills/glm-usage/scripts/glm-usage.mjs | sort -V | tail -1)"
```

脚本可独立使用(不需要装插件),支持 `--json`、`--key`、`--base`、`--install` 参数,详见脚本头部注释。

## 常驻显示(不用每次对话调用)

1. **桌面悬浮窗(Windows)**:运行 `scripts/glm-usage-widget.ps1`(`powershell -ExecutionPolicy Bypass -File ...`)。
   置顶小窗显示全部额度,每 5 分钟自动刷新,可拖动;右键菜单可"立即刷新 / 开机自启 / 退出"。零依赖(系统自带 PowerShell)。
2. **会话自动注入**:脚本带 `--hook` 模式,输出 SessionStart hook 的 `additionalContext` JSON,
   在 `~/.zcode/cli/config.json` 配置 hooks 后,每个新会话自动带上一行额度摘要。

## 前提条件

- Node.js >= 18
- ZCode 中已配置智谱 Coding Plan 的 API Key(自动读取,无需手动填)
- 不用 ZCode 的场景:设置 `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` 环境变量,或用 `--key`/`--base` 传参

## 说明

- 额度字段按接口实测解读:`TOKENS_LIMIT`(5 小时/每周)、`TIME_LIMIT`(MCP 每月)
- 走的是智谱未公开文档的监控接口,官方若调整接口,更新 `scripts/glm-usage.mjs` 中的字段映射即可
- 兼容 `.claude-plugin` 清单格式,理论上也可被 Claude Code 类工具识别

## 目录结构

```
glm-usage-plugin/                       ← 市场仓库根目录
├── .zcode-plugin/marketplace.json      ← 市场清单
└── plugins/glm-usage/                  ← 插件本体
    ├── .zcode-plugin/plugin.json
    ├── commands/usage.md               ← /glm-usage:usage 命令
    └── skills/glm-usage/
        ├── SKILL.md
        └── scripts/glm-usage.mjs       ← 查询脚本(零依赖)
```
