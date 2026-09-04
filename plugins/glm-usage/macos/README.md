# GLM 用量悬浮窗

一个 macOS 桌面小工具：把智谱 GLM Coding Plan 的额度用量做成一个常驻悬浮窗，
随时看到「5 小时池 / 每周额度 / MCP 月度调用」还剩多少、什么时候重置。

- 无边框圆角面板，始终悬浮在其他窗口上面，按住面板任意位置即可拖动
- 全局快捷键 **Ctrl + G** 随时唤出 / 收起（可改）
- 面板位置自动记忆，下次出现在你拖到的位置
- 菜单栏多一个 ⚡ 图标兜底，快捷键被占用时也能操作
- 数据每 5 分钟自动刷新一次（可改），也可点面板右上角 ↻ 手动刷新
- 不占 Dock、不抢焦点，纯粹的悬浮小组件

数据来源：调用智谱开放平台的用量查询接口（`scripts/glm-usage.mjs` 负责请求和汇总），
显示口径和 ZCode 里的 glm-usage 插件完全一致。

---

## 一、安装（3 步）

### 前提条件

| 需要 | 检查命令 | 没有的话 |
|---|---|---|
| macOS 12+ | 左上角  → 关于本机 | — |
| Xcode 命令行工具 | `xcode-select -p` | 终端执行 `xcode-select --install`，装完重开终端 |
| Node.js 18+ | `node -v` | `brew install node`，或去 https://nodejs.org 下载 |

### 第 1 步：编译

把整个文件夹放到任意位置（桌面也行），在终端里执行：

```bash
cd ~/Desktop/GLM用量悬浮窗     # 换成你实际放的路径
bash build.sh
```

成功后当前文件夹里会多出一个 `GLMUsageHUD.app`，这就是应用本体。

### 第 2 步：启动

```bash
open GLMUsageHUD.app
```

面板会自动弹出在屏幕右上角。第一次启动会请求网络访问（查询用量接口），允许即可。

### 第 3 步：配置凭据（二选一）

**方式 A：你也在用 ZCode 并登录了 GLM Coding Plan**
什么都不用做，直接就能用。工具会自动读取 ZCode 里已登录的账号。

**方式 B：不用 ZCode，只想看自己的 API Key 额度**
先启动一次应用让它生成配置文件，然后编辑：

```bash
open ~/.zcode/glm-usage-hud/
```

编辑里面的 `config.json`，加上两行（填你自己的 Key）：

```json
{
  "apiKey": "你的智谱 API Key",
  "apiBase": "https://open.bigmodel.cn/api/anthropic"
}
```

保存后点面板右上角 ↻ 刷新即可。

> ⚠️ `config.json` 里有你的 API Key，不要把这个文件发给别人。
> 国际站用户 `apiBase` 填 `https://api.z.ai/api/anthropic`。

---

## 二、日常使用

| 操作 | 方式 |
|---|---|
| 唤出 / 收起 | `Ctrl + G`（全局快捷键，任何应用里都生效） |
| 移动位置 | 按住面板任意空白处拖动，位置自动记忆 |
| 手动刷新 | 点面板右上角 ↻ |
| 退出 | 点菜单栏 ⚡ 图标 → 退出 |

面板上三行分别是：

- 🕐 **5 小时 Prompt 池**：短期滚动窗口的用量，重置倒计时
- 📅 **每周额度**：一周总额度
- 🔧 **MCP 工具调用**：search-prime / web-reader / zread 的月度调用次数

底部一行是近 24 小时模型调用次数和 token 消耗。

进度条颜色随用量变化：绿色（充足）→ 橙色（60% 以上）→ 红色（85% 以上）。

---

## 三、可选配置

配置文件：`~/.zcode/glm-usage-hud/config.json`（改完退出应用重开生效）

| 字段 | 默认值 | 说明 |
|---|---|---|
| `hotkey` | `"ctrl+g"` | 快捷键，支持 `ctrl/cmd/shift/alt` 组合，如 `"cmd+shift+u"` |
| `refreshIntervalMinutes` | `5` | 自动刷新间隔（分钟） |
| `autoShowOnStart` | `true` | 启动时是否自动弹出面板 |

### 让它开机自启（可选）

系统设置 → 通用 → 登录项与扩展 → 添加「GLMUsageHUD.app」即可。

### 让 ZCode 启动时自动弹出（可选）

如果你也用 ZCode，可以把 `launch.sh` 挂到 ZCode 的 SessionStart 钩子上，
效果是每次打开 ZCode 面板自动弹出来（已打开则只是前置显示，不会重复开）。

---

## 四、常见问题

**Q：提示「找不到 glm-usage.mjs」？**
`scripts/glm-usage.mjs` 必须和 `GLMUsageHUD.app` 放在同一个文件夹里
（本来的目录结构就是这样，别单独把 .app 拖走就行）。

**Q：提示「找不到 node」？**
装好 Node.js 后重开应用；还不行就在 `config.json` 里手工加
`"nodePath": "/opt/homebrew/bin/node"`（换成你 `which node` 的输出）。

**Q：快捷键 Ctrl+G 没反应？**
可能被其他应用占用了。换一个，比如在 `config.json` 里改 `"hotkey": "ctrl+shift+g"`，
重开应用生效；期间可用菜单栏 ⚡ 图标操作。

**Q：换了新电脑 / 应用没有签名，打不开？**
本工具编译产物是本地 ad-hoc 签名，自己 build 的不存在这个问题；
如果直接拷贝别人编译好的 .app 被拦，右键 → 打开 一次即可。

---

## 五、文件夹内容

| 文件 | 作用 |
|---|---|
| `GLMUsageHUD.swift` | 主程序源码（Swift + AppKit，单文件，约 700 行，零第三方依赖） |
| `build.sh` | 一键编译打包脚本 |
| `launch.sh` | ZCode 钩子用的幂等启动器（可选） |
| `scripts/glm-usage.mjs` | 用量查询脚本（来自 glm-usage 插件，负责调接口和汇总） |

想改外观（尺寸、配色、显示项）直接看 `GLMUsageHUD.swift`，每个区块都有中文注释，
改完重新 `bash build.sh` 即可。
