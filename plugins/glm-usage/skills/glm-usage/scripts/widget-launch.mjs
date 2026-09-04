#!/usr/bin/env node
/**
 * 跨平台悬浮窗启动器(插件 SessionStart hook 每会话调用一次)
 *
 * 按当前设备选择对应 UI 的悬浮窗:
 *   Windows → WPF 磨砂玻璃卡片(glm-usage-widget.ps1,经 widget-launch.vbs)
 *   macOS   → 原生 GLMUsageHUD.app(需先在 macos/ 目录执行一次 bash build.sh)
 *   其他    → 静默跳过
 *
 * 语义:已有实例在运行时不打扰、不抢焦点;没有则静默拉起。
 */
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));

if (process.platform === 'win32') {
  const vbs = path.join(dir, 'widget-launch.vbs');
  if (fs.existsSync(vbs)) {
    spawn('wscript.exe', [vbs], { detached: true, stdio: 'ignore', windowsHide: true }).unref();
  }
  process.exit(0);
}

if (process.platform === 'darwin') {
  // macOS:优先找已编译的 GLMUsageHUD.app(插件内 build 产物 → 用户/系统应用目录)
  const pluginRoot = path.resolve(dir, '..', '..', '..');
  const candidates = [
    path.join(pluginRoot, 'macos', 'GLMUsageHUD.app'),
    path.join(os.homedir(), 'Applications', 'GLMUsageHUD.app'),
    path.join('/Applications', 'GLMUsageHUD.app'),
  ];
  const app = candidates.find((p) => fs.existsSync(p));
  if (app) {
    // open -g:后台打开,不抢焦点;若已在运行则等价于唤起
    spawn('open', ['-g', app], { detached: true, stdio: 'ignore' }).unref();
  }
  // 未编译时静默跳过——见 macos/README.md,执行一次 bash build.sh 即可
  process.exit(0);
}

process.exit(0);
