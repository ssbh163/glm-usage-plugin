#!/usr/bin/env node
/**
 * GLM / 智谱 Coding Plan 用量查询(零依赖,需 Node >= 18)
 *
 * 数据来源与官方 glm-plan-usage 插件相同:
 *   GET {domain}/api/monitor/usage/quota/limit   —— 5 小时池 / 每周额度 / MCP 每月额度
 *   GET {domain}/api/monitor/usage/model-usage   —— 模型 token 用量(当日)
 *   GET {domain}/api/monitor/usage/tool-usage    —— MCP 工具调用(当日)
 * domain 取自 baseURL:open.bigmodel.cn(智谱)或 api.z.ai(国际)。
 *
 * API Key 自动读取顺序:
 *   1. 环境变量 ANTHROPIC_AUTH_TOKEN + ANTHROPIC_BASE_URL
 *   2. ZCode 配置 ~/.zcode/v2/config.json 中已启用的 coding-plan provider
 * 也可用 --key <apiKey> --base <baseURL> 显式指定。
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
const asJson = argv.includes('--json');
const asHook = argv.includes('--hook');
const flagValue = (name) => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
};

// ---------- 自安装:node zcode-usage.mjs --install ----------
const COMMAND_MD = `---
description: 查询智谱 GLM Coding Plan 的 5 小时/每周/每月额度与用量
---

运行以下命令查询 Coding Plan 用量:

\`\`\`bash
node ~/.zcode/scripts/zcode-usage.mjs
\`\`\`

(若 ~ 无法展开,改用: node "$HOME/.zcode/scripts/zcode-usage.mjs")

然后将输出用简洁的中文表格汇报给用户,必须包含:

1. **5 小时 Prompt 池**:已用百分比、重置时间(倒计时)
2. **每周额度**:已用百分比、重置时间
3. **MCP 工具调用(每月)**:已用/总量、剩余次数、重置时间、各工具明细
4. **当日模型用量**:调用次数、token 消耗、高峰期(工作日 14–18 时)/非高峰期拆分、按模型汇总(如有)

如果命令执行失败,原样展示错误信息,并提示用户:API Key 存放在 ~/.zcode/v2/config.json,
可在 ZCode 的模型设置中重新配置,或去智谱开放平台「个人编程套餐 > 用量统计」网页版查看。

不要改写或猜测数字,一切以脚本输出为准;如需原始 JSON,可运行带 --json 参数的同一命令。
`;

if (argv.includes('--install')) {
  const home = os.homedir();
  const scriptDest = path.join(home, '.zcode', 'scripts', 'zcode-usage.mjs');
  const commandDest = path.join(home, '.zcode', 'commands', 'usage.md');
  fs.mkdirSync(path.dirname(scriptDest), { recursive: true });
  fs.mkdirSync(path.dirname(commandDest), { recursive: true });
  const selfPath = fileURLToPath(import.meta.url);
  if (path.resolve(selfPath) !== path.resolve(scriptDest)) {
    fs.copyFileSync(selfPath, scriptDest);
  }
  fs.writeFileSync(commandDest, COMMAND_MD, 'utf8');
  console.log('安装完成:');
  console.log(`  脚本   -> ${scriptDest}`);
  console.log(`  命令   -> ${commandDest}(ZCode 新开对话输入 /usage)`);

  // 悬浮窗(仅 Windows,且安装目录里带有 widget 脚本)
  const selfDir = path.dirname(selfPath);
  const widgetSrc = path.join(selfDir, 'zcode-usage-widget.ps1');
  if (process.platform === 'win32' && fs.existsSync(widgetSrc)) {
    const widgetDest = path.join(home, '.zcode', 'scripts', 'zcode-usage-widget.ps1');
    fs.copyFileSync(widgetSrc, widgetDest);
    const winPath = widgetDest.replace(/\//g, '\\');
    const vbs = `CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""${winPath}""", 0, False\r\n`;
    const launchVbs = path.join(home, '.zcode', 'scripts', 'zcode-usage-widget-launch.vbs');
    fs.writeFileSync(launchVbs, vbs, 'ascii');
    // 开机自启
    const startupDir = path.join(home, 'AppData', 'Roaming', 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup');
    fs.mkdirSync(startupDir, { recursive: true });
    fs.writeFileSync(path.join(startupDir, 'zcode-usage-widget.vbs'), vbs, 'ascii');
    // 立即弹出悬浮窗(已有实例在运行时,会自动唤起到前台)
    spawn('wscript.exe', [launchVbs], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
    console.log('  悬浮窗 -> 已安装并启动(置顶显示,每 10 分钟刷新)');
    console.log('           隐藏/唤回:Ctrl+G 全局快捷键;启动 ZCode 时也会自动唤起');
    console.log('           开机自启已开启(悬浮窗右键菜单可关闭)');
  } else if (process.platform === 'win32') {
    console.log('  悬浮窗 -> 未安装(当前目录没有 zcode-usage-widget.ps1;从完整 zip 安装可获得)');
  }
  process.exit(0);
}

// ---------- 凭据与域名 ----------
function fromArgs() {
  const key = flagValue('--key'), base = flagValue('--base');
  return key && base ? { token: key, base, from: 'args' } : null;
}
function fromEnv() {
  const token = process.env.ANTHROPIC_AUTH_TOKEN || process.env.ZAI_API_KEY || '';
  const base = process.env.ANTHROPIC_BASE_URL || '';
  return token && base ? { token, base, from: 'env' } : null;
}
function fromZcodeConfig() {
  const file = path.join(os.homedir(), '.zcode', 'v2', 'config.json');
  if (!fs.existsSync(file)) return null;
  try {
    const cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
    const providers = cfg.provider || {};
    const order = [
      'builtin:bigmodel-coding-plan', 'builtin:zai-coding-plan',
      'builtin:bigmodel', 'builtin:zai',
    ];
    for (const name of order) {
      const pv = providers[name];
      const key = pv?.options?.apiKey, base = pv?.options?.baseURL;
      if (pv?.enabled !== false && key && base) {
        return { token: key, base, from: `zcode:${name}` };
      }
    }
  } catch { /* 配置损坏时走报错分支 */ }
  return null;
}

const cred = fromArgs() || fromEnv() || fromZcodeConfig();
if (!cred) {
  console.error('未找到 Coding Plan API Key。请任选其一:');
  console.error('  1. 在 ZCode 中配置 Coding Plan API Key(~/.zcode/v2/config.json)');
  console.error('  2. 设置环境变量 ANTHROPIC_AUTH_TOKEN 和 ANTHROPIC_BASE_URL');
  console.error('  3. 运行时传参: --key <apiKey> --base https://open.bigmodel.cn/api/anthropic');
  process.exit(1);
}

const origin = new URL(cred.base).origin;

// ---------- 请求 ----------
// 常规查询 10s、hook 模式 5s,防止网络悬挂时阻塞悬浮窗 UI 或会话启动
const FETCH_TIMEOUT = asHook ? 5000 : 10000;
let bearerTried = false;
async function get(p) {
  let res;
  try {
    res = await fetch(origin + p, {
      headers: {
        Authorization: cred.token,
        'Accept-Language': 'zh-CN,zh',
        'Content-Type': 'application/json',
      },
      signal: AbortSignal.timeout(FETCH_TIMEOUT),
    });
  } catch (e) {
    throw new Error(e.name === 'TimeoutError' || e.name === 'AbortError'
      ? `请求超时(${FETCH_TIMEOUT / 1000}s):${origin} 无响应,请检查网络`
      : `网络错误,无法连接 ${origin}:${e.message}`);
  }
  if (res.status === 401 && !bearerTried && !cred.token.startsWith('Bearer ')) {
    bearerTried = true;
    cred.token = `Bearer ${cred.token}`;
    return get(p);
  }
  if (!res.ok) throw new Error(`${p} -> HTTP ${res.status}`);
  const body = await res.json();
  if (body.code !== undefined && body.code !== 200 && body.code !== 0) {
    throw new Error(`${p} -> ${body.msg || body.code}`);
  }
  return body.data ?? body;
}

// ---------- 颜色与排版 ----------
// 仅在真终端且明确支持 ANSI 时着色(Git Bash 有 TERM,Windows Terminal 有 WT_SESSION);
// 管道/重定向/老式 cmd 下自动输出纯文本,避免乱码。NO_COLOR 可强制关闭。
const supportsAnsi = process.platform !== 'win32'
  || !!process.env.TERM
  || !!process.env.WT_SESSION
  || process.env.ConEmuANSI === 'ON';
const useColor = !process.env.NO_COLOR && process.stdout.isTTY && supportsAnsi;
const c = (code, s) => (useColor ? `\x1b[${code}m${s}\x1b[0m` : s);
const bold = (s) => c('1', s);
const dim = (s) => c('2', s);
// 用量越高越醒目:<50% 绿,50-80% 黄,>=80% 红加粗
const rateStyle = (p) => (p >= 80 ? '1;31' : p >= 50 ? '33' : '32');

// 显示宽度:中日韩全角/emoji 按 2 列计,用于对齐
function dw(s) {
  let w = 0;
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    const wide = (cp >= 0x1100 && cp <= 0x115f) || (cp >= 0x2e80 && cp <= 0xa4cf)
      || (cp >= 0xac00 && cp <= 0xd7a3) || (cp >= 0xf900 && cp <= 0xfaff)
      || (cp >= 0xfe30 && cp <= 0xfe6f) || (cp >= 0xff00 && cp <= 0xff60)
      || (cp >= 0xffe0 && cp <= 0xffe6) || (cp >= 0x1f300 && cp <= 0x1faff)
      || (cp >= 0x20000 && cp <= 0x3fffd);
    w += wide ? 2 : 1;
  }
  return w;
}
const padEndW = (s, width) => s + ' '.repeat(Math.max(0, width - dw(s)));

// ---------- 展示辅助 ----------
const UNIT_NAME = { 3: '小时', 5: '个月', 6: '周' }; // 接口实测:unit 3/5/6 对应时/月/周
const periodText = (u, n) => (UNIT_NAME[u] ? `${n}${UNIT_NAME[u]}` : `${n}×unit${u}`);
const fmtTs = (ts) => ts > 0
  ? new Date(ts).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
  : '—';
function countdown(ms) {
  if (!ms || ms <= 0) return '';
  const min = Math.round(ms / 60000);
  const d = Math.floor(min / 1440), h = Math.floor((min % 1440) / 60), m = min % 60;
  const parts = [];
  if (d) parts.push(`${d} 天`);
  if (h) parts.push(`${h} 小时`);
  if (m || (!d && !h)) parts.push(`${m} 分钟`);
  return parts.join(' ') + '后';
}
const fmtNum = (n) => Number(n || 0).toLocaleString('zh-CN');
const fmtTokens = (n) => {
  const v = Number(n || 0);
  return v >= 1e8 ? (v / 1e8).toFixed(2) + ' 亿'
    : v >= 1e4 ? (v / 1e4).toFixed(1) + ' 万'
    : fmtNum(v);
};
function bar(pct, width = 18) {
  const p = Math.max(0, Math.min(100, Number(pct) || 0));
  const filled = Math.round((p / 100) * width);
  const style = rateStyle(p);
  return c(style, '▰'.repeat(filled) + '▱'.repeat(width - filled)) + '  ' + c(style, `${p.toFixed(1)}%`);
}

function labelFor(limit) {
  const period = periodText(limit.unit, limit.number);
  if (limit.type === 'TIME_LIMIT') return `MCP 工具调用(${period})`;
  if (period.includes('小时')) return '5 小时 Prompt 池';
  if (period.includes('周')) return '每周额度';
  return `Prompt 额度(${period})`;
}
const iconFor = (limit) => {
  if (limit.type === 'TIME_LIMIT') return '🔧';
  return periodText(limit.unit, limit.number).includes('小时') ? '🕐' : '📅';
};

const LABEL_W = 22; // 标签列显示宽度,保证进度条对齐
const rule = (ch) => c('2;36', ch.repeat(50));

// ---------- 主流程 ----------
async function main() {
  const quota = await get('/api/monitor/usage/quota/limit');

  // SessionStart hook 模式:只查额度,输出 additionalContext JSON,注入会话上下文
  if (asHook) {
    const parts = [];
    for (const l of quota.limits || []) {
      const p = Number(l.percentage) || 0;
      const name = l.type === 'TIME_LIMIT' ? 'MCP'
        : periodText(l.unit, l.number).includes('小时') ? '5小时池' : '每周';
      const reset = l.nextResetTime > 0 ? `,${countdown(l.nextResetTime - Date.now())}重置` : '';
      parts.push(`${name} ${p.toFixed(0)}%${reset}`);
    }
    const line = `【GLM Coding Plan 用量】${parts.join(' · ')}(如需详情运行 node ~/.zcode/scripts/zcode-usage.mjs)`;
    console.log(JSON.stringify({
      hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: line },
    }));
    return;
  }

  // 当日用量(失败不影响额度展示);高峰期 = 工作日(周一至周五)14:00–18:00
  const now = new Date();
  const z = (n) => String(n).padStart(2, '0');
  const fmt = (d) => `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())} ${z(d.getHours())}:${z(d.getMinutes())}:${z(d.getSeconds())}`;
  const qs = (start, end) => `?startTime=${encodeURIComponent(fmt(start))}&endTime=${encodeURIComponent(fmt(end))}`;
  const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
  // 当日高峰时段与 [当天零点, 现在] 的交集;周末或未到 14 点为 null(此时高峰用量恒为 0)
  const peakWindow = (() => {
    const dow = now.getDay();
    if (dow === 0 || dow === 6) return null;
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 14, 0, 0);
    if (now.getTime() <= start.getTime()) return null;
    return { start, end: new Date(Math.min(now.getTime(), start.getTime() + 4 * 3600 * 1000)) };
  })();
  const [modelUsage, toolUsage, peakUsage] = await Promise.all([
    get('/api/monitor/usage/model-usage' + qs(dayStart, now)).catch(() => null),
    get('/api/monitor/usage/tool-usage' + qs(dayStart, now)).catch(() => null),
    peakWindow
      ? get('/api/monitor/usage/model-usage' + qs(peakWindow.start, peakWindow.end)).catch(() => null)
      : null,
  ]);
  // 高峰/非高峰拆分:非高峰 = 当日总量 - 高峰;高峰窗口存在但查询失败时不拆分(只显示当日总量)
  let usageSplit = null;
  const total = modelUsage?.totalUsage;
  if (total) {
    const peakT = peakWindow === null
      ? { totalModelCallCount: 0, totalTokensUsage: 0 }
      : peakUsage?.totalUsage;
    if (peakT) {
      const pc = Number(peakT.totalModelCallCount) || 0;
      const pt = Number(peakT.totalTokensUsage) || 0;
      usageSplit = {
        peak: { calls: pc, tokens: pt },
        offPeak: {
          calls: Math.max(0, (Number(total.totalModelCallCount) || 0) - pc),
          tokens: Math.max(0, (Number(total.totalTokensUsage) || 0) - pt),
        },
      };
    }
  }

  if (asJson) {
    console.log(JSON.stringify({ quota, modelUsage, toolUsage, usageSplit }, null, 2));
    return;
  }

  const host = new URL(origin).host;
  const level = (quota.level || 'unknown').toUpperCase();
  console.log(rule('━'));
  console.log(bold(' ⚡ GLM Coding Plan 用量'));
  console.log(dim(`    ${level} 套餐 · ${host} · ${now.toLocaleString('zh-CN')}`));
  console.log(rule('━'));

  for (const l of quota.limits || []) {
    const p = Number(l.percentage) || 0;
    console.log('');
    console.log(` ${iconFor(l)}  ${bold(padEndW(labelFor(l), LABEL_W))}${bar(p)}`);
    if (l.type === 'TIME_LIMIT') {
      console.log(dim(`      已用 ${fmtNum(l.currentValue)} / ${fmtNum(l.usage)} 次 · 剩余 ${fmtNum(l.remaining)}`));
    } else {
      console.log(dim(`      剩余 ${(100 - p).toFixed(1)}%`));
    }
    if (l.nextResetTime > 0) {
      console.log(dim(`      ↻ ${fmtTs(l.nextResetTime)} 重置(${countdown(l.nextResetTime - now.getTime())})`));
    }
    const details = l.usageDetails || [];
    if (details.length) {
      console.log(dim(`      ${details.map((d) => `${d.modelCode} ${fmtNum(d.usage)}`).join(' · ')}`));
    }
  }

  if (modelUsage?.totalUsage) {
    const t = modelUsage.totalUsage;
    console.log('');
    console.log(` 📊  ${bold(padEndW('当日模型用量', LABEL_W))}`
      + `${fmtNum(t.totalModelCallCount)} 次 · ${fmtTokens(t.totalTokensUsage)} tokens`);
    if (usageSplit) {
      const splitLine = (label, v) => dim(`      ${padEndW(label, 26)}${fmtNum(v.calls)} 次 · ${fmtTokens(v.tokens)} tokens`);
      console.log(splitLine('高峰期(工作日 14–18 时)', usageSplit.peak));
      console.log(splitLine('非高峰期', usageSplit.offPeak));
    }
    const models = t.modelSummaryList || [];
    if (models.length) {
      console.log(dim(`      ${models.map((m) => `${m.modelName} ${fmtTokens(m.totalTokens)}`).join(' · ')}`));
    }
  }

  if (toolUsage?.totalUsage) {
    const t = toolUsage.totalUsage;
    const parts = [];
    if (t.totalSearchMcpCount) parts.push(`联网搜索 ${fmtNum(t.totalSearchMcpCount)}`);
    if (t.totalWebReadMcpCount) parts.push(`网页读取 ${fmtNum(t.totalWebReadMcpCount)}`);
    if (t.totalZreadMcpCount) parts.push(`Zread ${fmtNum(t.totalZreadMcpCount)}`);
    if (parts.length) {
      console.log('');
      console.log(` 🔌  ${bold(padEndW('当日 MCP 调用', LABEL_W))}${parts.join(' · ')}`);
    }
  }

  console.log('');
  console.log(rule('━'));
  console.log(dim(`    凭据来源 ${cred.from} · 加 --json 看原始数据`));
}

main().catch((e) => {
  console.error('查询失败:', e.message);
  if (String(e.message).includes('HTTP 401')) {
    console.error('该 API Key 可能:1) 已失效或被更换;2) 不是 Coding Plan 专用 Key(普通按量付费 Key 无法查询套餐额度)。');
    console.error('请在 ZCode 的模型设置中检查 Key,或到智谱开放平台「个人编程套餐」重新获取。');
  }
  process.exit(1);
});
