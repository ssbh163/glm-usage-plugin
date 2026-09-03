#!/usr/bin/env node
/**
 * GLM / 智谱 Coding Plan 用量查询(零依赖,需 Node >= 18)
 *
 * 数据来源与官方 glm-plan-usage 插件相同:
 *   GET {domain}/api/monitor/usage/quota/limit   —— 5 小时池 / 每周额度 / MCP 每月额度
 *   GET {domain}/api/monitor/usage/model-usage   —— 模型 token 用量(近 24 小时)
 *   GET {domain}/api/monitor/usage/tool-usage    —— MCP 工具调用(近 24 小时)
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
import { fileURLToPath } from 'node:url';

const argv = process.argv.slice(2);
const asJson = argv.includes('--json');
const flagValue = (name) => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
};

// ---------- 自安装:node glm-usage.mjs --install ----------
const COMMAND_MD = `---
description: 查询智谱 GLM Coding Plan 的 5 小时/每周/每月额度与用量
---

运行以下命令查询 Coding Plan 用量:

\`\`\`bash
node ~/.zcode/scripts/glm-usage.mjs
\`\`\`

(若 ~ 无法展开,改用: node "$HOME/.zcode/scripts/glm-usage.mjs")

然后将输出用简洁的中文表格汇报给用户,必须包含:

1. **5 小时 Prompt 池**:已用百分比、重置时间(倒计时)
2. **每周额度**:已用百分比、重置时间
3. **MCP 工具调用(每月)**:已用/总量、剩余次数、重置时间、各工具明细
4. **近 24 小时模型用量**:调用次数、token 消耗、按模型汇总(如有)

如果命令执行失败,原样展示错误信息,并提示用户:API Key 存放在 ~/.zcode/v2/config.json,
可在 ZCode 的模型设置中重新配置,或去智谱开放平台「个人编程套餐 > 用量统计」网页版查看。

不要改写或猜测数字,一切以脚本输出为准;如需原始 JSON,可运行带 --json 参数的同一命令。
`;

if (argv.includes('--install')) {
  const home = os.homedir();
  const scriptDest = path.join(home, '.zcode', 'scripts', 'glm-usage.mjs');
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
  console.log(`  命令   -> ${commandDest}`);
  console.log('');
  console.log('使用方式:');
  console.log('  1. ZCode 里新开对话,输入 /usage');
  console.log('  2. 或在终端运行: node ~/.zcode/scripts/glm-usage.mjs');
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
let bearerTried = false;
async function get(p) {
  const res = await fetch(origin + p, {
    headers: {
      Authorization: cred.token,
      'Accept-Language': 'zh-CN,zh',
      'Content-Type': 'application/json',
    },
  });
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
  return (d ? `${d}天` : '') + (h ? `${h}小时` : '') + `${m}分后重置`;
}
const fmtNum = (n) => Number(n || 0).toLocaleString('zh-CN');
function bar(pct) {
  const p = Math.max(0, Math.min(100, Number(pct) || 0));
  return '█'.repeat(Math.round(p / 5)).padEnd(20, '░') + ` ${p.toFixed(1)}%`;
}
const fmtTokens = (n) => {
  const v = Number(n || 0);
  return v >= 1e8 ? (v / 1e8).toFixed(2) + '亿'
    : v >= 1e4 ? (v / 1e4).toFixed(1) + '万'
    : fmtNum(v);
};

// ---------- 主流程 ----------
const pad = (s) => '  ' + s;

function labelFor(limit) {
  const period = periodText(limit.unit, limit.number);
  if (limit.type === 'TIME_LIMIT') return `MCP 工具调用(${period})`;
  if (period.includes('小时')) return `5 小时 Prompt 池`;
  if (period.includes('周')) return `每周额度`;
  return `Prompt 额度(${period})`;
}

async function main() {
  const quota = await get('/api/monitor/usage/quota/limit');

  // 近 24 小时用量(失败不影响额度展示)
  const now = new Date();
  const z = (n) => String(n).padStart(2, '0');
  const fmt = (d) => `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())} ${z(d.getHours())}:${z(d.getMinutes())}:${z(d.getSeconds())}`;
  const qs = `?startTime=${encodeURIComponent(fmt(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1, now.getHours(), 0, 0)))}`
    + `&endTime=${encodeURIComponent(fmt(new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours(), 59, 59)))}`;
  const [modelUsage, toolUsage] = await Promise.all([
    get('/api/monitor/usage/model-usage' + qs).catch(() => null),
    get('/api/monitor/usage/tool-usage' + qs).catch(() => null),
  ]);

  if (asJson) {
    console.log(JSON.stringify({ quota, modelUsage, toolUsage }, null, 2));
    return;
  }

  const limits = quota.limits || [];
  console.log(`GLM Coding Plan 用量  |  套餐等级: ${(quota.level || 'unknown').toUpperCase()}  |  ${origin}`);
  console.log(`数据时间: ${now.toLocaleString('zh-CN')}  (凭据来源: ${cred.from})`);
  console.log('');

  console.log('== 额度 ==');
  for (const l of limits) {
    console.log(pad(`${labelFor(l)}  ${bar(l.percentage)}`));
    const reset = l.nextResetTime > 0 ? `${fmtTs(l.nextResetTime)}(${countdown(l.nextResetTime - now.getTime())})` : '—';
    if (l.type === 'TIME_LIMIT') {
      console.log(pad(`已用 ${fmtNum(l.currentValue)} / ${fmtNum(l.usage)} 次,剩余 ${fmtNum(l.remaining)},重置: ${reset}`));
      const details = l.usageDetails || [];
      if (details.length) {
        console.log(pad('明细: ' + details.map((d) => `${d.modelCode} ${fmtNum(d.usage)}`).join('、')));
      }
    } else {
      console.log(pad(`重置: ${reset}`));
    }
  }

  if (modelUsage?.totalUsage) {
    const t = modelUsage.totalUsage;
    console.log('');
    console.log('== 近 24 小时模型用量 ==');
    console.log(pad(`调用 ${fmtNum(t.totalModelCallCount)} 次,消耗 ${fmtTokens(t.totalTokensUsage)} tokens`));
    const models = t.modelSummaryList || [];
    if (models.length) {
      console.log(pad('按模型: ' + models.map((m) => `${m.modelName} ${fmtTokens(m.totalTokens)}`).join('、')));
    }
  }

  if (toolUsage?.totalUsage) {
    const t = toolUsage.totalUsage;
    const parts = [];
    if (t.totalSearchMcpCount) parts.push(`联网搜索 ${fmtNum(t.totalSearchMcpCount)} 次`);
    if (t.totalWebReadMcpCount) parts.push(`网页读取 ${fmtNum(t.totalWebReadMcpCount)} 次`);
    if (t.totalZreadMcpCount) parts.push(`Zread ${fmtNum(t.totalZreadMcpCount)} 次`);
    if (parts.length) {
      console.log('');
      console.log('== 近 24 小时 MCP 调用 ==');
      console.log(pad(parts.join(', ')));
    }
  }
}

main().catch((e) => {
  console.error('查询失败:', e.message);
  if (String(e.message).includes('HTTP 401')) {
    console.error('API Key 可能无效或已过期,请在 ZCode 设置或智谱开放平台检查。');
  }
  process.exit(1);
});
