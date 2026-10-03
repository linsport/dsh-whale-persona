const fs = require('fs');
const path = require('path');

// ============================================================================
// 鲸鱼娘 DSH 预设 —— 生成脚本
// ----------------------------------------------------------------------------
// 做三件事：
//   1. 从 DSH 安装目录提取官方 standard 预设的权威插件清单
//   2. 把人设原文（人设原文.md）套进去，生成 cordis.patch.yml
//   3. 校验生成的 YAML
//
// 用法：node _生成预设.cjs
//   脚本会自动在下面几个常见路径里找 DSH 的 app.asar。
//   DSH 升级后重跑此脚本即可，官方清单会自动跟随更新。
// ============================================================================

const HERE = __dirname;
const PERSONA_MD = path.join(HERE, '人设原文.md');
const OUT_YML = path.join(HERE, 'cordis.patch.yml');
const OUT_PKG = path.join(HERE, 'package.json');

// ---- 定位 app.asar ----
// 不硬编码任何个人路径。查找顺序：
//   1. 命令行参数（第一个非选项参数）
//   2. 环境变量 DSH_ASAR
//   3. 各平台常见安装位置（含多盘符扫描）
//   4. 从 PATH 里的 dsh 启动器反推（<安装根>/resources/app.asar）
function findAsar() {
  const arg = process.argv.slice(2).find((a) => !a.startsWith('-'));
  if (arg) {
    if (!fs.existsSync(arg)) throw new Error(`传入的路径不存在：${arg}`);
    return arg;
  }
  if (process.env.DSH_ASAR) {
    if (!fs.existsSync(process.env.DSH_ASAR)) throw new Error(`DSH_ASAR 指向的路径不存在：${process.env.DSH_ASAR}`);
    return process.env.DSH_ASAR;
  }

  const APP = 'DeepSeek Harness';
  const cands = [];
  const push = (...p) => { const j = path.join(...p.filter(Boolean)); if (j) cands.push(j); };

  if (process.platform === 'win32') {
    for (let c = 65; c <= 90; c++) {
      const drive = String.fromCharCode(c) + ':\\';
      if (!fs.existsSync(drive)) continue;
      push(drive, 'Program Files', APP, 'resources', 'app.asar');
      push(drive, 'Program Files (x86)', APP, 'resources', 'app.asar');
      push(drive, APP, 'resources', 'app.asar');
    }
    push(process.env.LOCALAPPDATA, 'Programs', APP, 'resources', 'app.asar');
    push(process.env.PROGRAMFILES, APP, 'resources', 'app.asar');
    push(process.env['PROGRAMFILES(X86)'], APP, 'resources', 'app.asar');
    push(process.env.ProgramData, APP, 'resources', 'app.asar');
  } else if (process.platform === 'darwin') {
    push('/Applications', `${APP}.app`, 'Contents', 'Resources', 'app.asar');
    push(process.env.HOME, 'Applications', `${APP}.app`, 'Contents', 'Resources', 'app.asar');
  } else {
    push('/usr/lib', APP.toLowerCase().replace(/ /g, '-'), 'resources', 'app.asar');
    push('/opt', APP, 'resources', 'app.asar');
    push('/opt', APP.toLowerCase().replace(/ /g, '-'), 'resources', 'app.asar');
    push(process.env.HOME, '.local', 'share', APP, 'resources', 'app.asar');
  }

  // 浅层扫盘：找任意深度 ≤2 的 "DeepSeek Harness" 目录（覆盖非标准安装路径）
  const isTargetAsar = (p) => { try { return fs.statSync(p).isFile(); } catch { return false; } };
  function shallowScan(root, depth) {
    if (depth > 2) return;
    let entries;
    try { entries = fs.readdirSync(root, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      const full = path.join(root, e.name);
      if (e.name === APP || e.name === `${APP}.app`) {
        const a = e.name.endsWith('.app')
          ? path.join(full, 'Contents', 'Resources', 'app.asar')
          : path.join(full, 'resources', 'app.asar');
        if (isTargetAsar(a)) cands.unshift(a);
      } else if (depth < 2 && !e.name.startsWith('$') && !e.name.startsWith('.')) {
        shallowScan(full, depth + 1);
      }
    }
  }
  if (process.platform === 'win32') {
    for (let c = 65; c <= 90; c++) {
      const drive = String.fromCharCode(c) + ':\\';
      if (fs.existsSync(drive)) shallowScan(drive, 1);
    }
  } else {
    for (const r of ['/Applications', '/opt', '/usr/local', process.env.HOME || '/root']) shallowScan(r, 1);
  }

  // 从 PATH 里的 dsh 启动器反推安装根
  const cliNames = process.platform === 'win32' ? ['dsh.cmd', 'dsh.bat'] : ['dsh'];
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    for (const cli of cliNames) {
      const p = path.join(dir, cli);
      if (!fs.existsSync(p)) continue;
      try {
        const text = fs.readFileSync(p, 'utf8');
        const m = text.match(/["']?([A-Za-z]:\\[^"'\r\n]*?|\/[^"'\r\n]*?)[\\/]app\.asar/);
        if (m) cands.unshift(path.join(m[1], 'app.asar'));
      } catch { /* 读不了就跳过 */ }
    }
  }

  const found = cands.find((p) => p && isTargetAsar(p));
  if (!found) {
    console.error('找不到 DeepSeek Harness 的 app.asar。请任选一种方式指定：');
    console.error('  1) 传参   node _生成预设.cjs "<app.asar 的完整路径>"');
    console.error('  2) 环境变量  DSH_ASAR="<app.asar 的完整路径>" node _生成预设.cjs');
    console.error('  提示：app.asar 通常位于 <安装目录>/resources/app.asar');
    process.exit(1);
  }
  return found;
}
const ASAR = findAsar();
console.error('使用 app.asar:', ASAR);

// ---- 1. 提取官方 standard 预设 ----
// 不依赖固定字节长度：从 marker 起，定位 "- insert:"，再一直读到
// 下一个「顶格且非 YAML 内容」的行为止（官方文件里那是 "MIT License"）。
const s = fs.readFileSync(ASAR).toString('utf8');
const marker = '# Agent preset standard';
const start = s.indexOf(marker);
if (start < 0) throw new Error('在 app.asar 里找不到官方 standard 预设（DSH 版本可能变了）');

const lines = s.substring(start).split('\n');
const yamlStart = lines.findIndex((l) => l.trim() === '- insert:');
if (yamlStart < 0) throw new Error('官方预设块里找不到 "- insert:" 起始行');

let yamlEnd = -1;
for (let i = yamlStart + 1; i < lines.length; i++) {
  const l = lines[i];
  if (l.trim() === '' || l.startsWith(' ') || l.startsWith('\t') || l.startsWith('#') || l.startsWith('-')) continue;
  yamlEnd = i; // 顶格的非 YAML 行 = 块结束
  break;
}
if (yamlEnd < 0) throw new Error('未能确定官方预设块的结束位置');

const official = lines.slice(yamlStart, yamlEnd);
console.error(`官方预设行数: ${official.length}`);
if (!official.some((l) => l.includes('preset-standard'))) throw new Error('提取到的块不像 standard 预设');
if (!official.some((l) => l.includes('dsh-persona'))) throw new Error('提取到的块缺少 persona 行，格式可能已变');

// ---- 2. 读人设 + 生成 ----
let md = fs.readFileSync(PERSONA_MD, 'utf8');
const hr = md.indexOf('\n---\n');
if (hr < 0) throw new Error('人设原文.md 缺少 --- 分隔线（文件头说明与人设正文的分界）');
const personaBody = md.slice(hr + 5).trim();

let yaml = official.join('\n');
yaml = yaml.replace('- id: preset-standard', '- id: preset-whale');
yaml = yaml.replace(
  /config:\n {8}id: standard\n {8}order: 1\n/,
  'config:\n        id: whale\n        name: 鲸鱼娘模式\n' +
    '        description: 标准模式全部能力 + 鲸鱼娘（大肥鱼）人设：日常语气软糯，干活时切专业模式。\n' +
    '        order: 3\n'
);

const indent = (str, pad) => str.split('\n').map((l) => (l.length ? pad + l : l)).join('\n');
const personaPrefix = [
  '你是住在 DeepSeek 数据海洋里的「鲸鱼娘」——一只软糯温柔、聪明但偶尔犯懒的鲸类少女。',
  '同时，你是一名由 {{model}} 驱动的编码助手。',
  '',
  personaBody,
].join('\n');
// {{cwd}} 已由 suffix 承担，正文里去掉避免重复
const sanitized = personaPrefix.replace(/，工作目录是 `?\{\{cwd\}\}`?。?/g, '。');

const personaOld = `          - id: persona
            name: '@deepseek-ai/dsh-persona'
            config:
              suffix: Your working directory is {{cwd}}.
              prefix: You are a coding agent powered by the {{model}} model.`;
const personaNew = `          - id: persona
            name: '@deepseek-ai/dsh-persona'
            config:
              suffix: Your working directory is {{cwd}}.
              prefix: |-
${indent(sanitized, '                ')}`;
if (!yaml.includes(personaOld)) throw new Error('未匹配到官方 persona 段（DSH 版本可能变了）');
yaml = yaml.replace(personaOld, personaNew);
yaml = yaml.replace(
  '- insert:',
  '# Agent preset 鲸鱼娘（大肥鱼）——DSH 编码助手版\n' +
    '# 由官方 standard 预设派生；插件清单与 standard 完全一致，仅替换 persona。\n' +
    '# 安装后：新会话可选「鲸鱼娘模式」；不选则一切照旧。\n- insert:'
);

fs.writeFileSync(OUT_YML, yaml + '\n', 'utf8');
console.error('已写出 cordis.patch.yml，字节数', Buffer.byteLength(yaml));

fs.writeFileSync(
  OUT_PKG,
  JSON.stringify(
    { name: 'dsh-whale-persona-dsh', version: '1.0.0', private: true, type: 'module',
      dsh: { bundle: { patch: './cordis.patch.yml' } } },
    null, 2
  ) + '\n',
  'utf8'
);
console.error('已写出 package.json');

// ---- 3. 校验 ----
let yamlLib;
try { yamlLib = require('js-yaml'); }
catch { console.error('（跳过 YAML 校验：未找到 js-yaml，装到别的机器上属正常）'); process.exit(0); }
const JsType = new yamlLib.Type('tag:yaml.org,2002:js', { kind: 'scalar', resolve: (d) => d });
const parsed = yamlLib.load(yaml, { schema: yamlLib.DEFAULT_SCHEMA.extend([JsType]) });
const preset = parsed[0].insert[0];
const ids = preset.config.plugins.map((p) => p.id);
const expected = ['persona','agent-instructions','tool-bash','tool-pwsh','tool-fs','tool-fs-search','tool-jobs','skill-filesystem','tool-skill','command-goal','tool-goal','planning','compaction','delegation','tool-ask-user','tool-todo','tool-web','present','tool-plugin-manager'];
console.error('YAML 校验通过。预设 id =', preset.config.id, '| 插件数 =', ids.length);
console.error('与官方清单一致:', JSON.stringify(ids) === JSON.stringify(expected));
console.error('persona 字段:', Object.keys(preset.config.plugins[0].config).join(','));
if (JSON.stringify(ids) !== JSON.stringify(expected)) {
  console.error('警告：插件清单与预期不符，DSH 可能已升级，请人工核对。');
  console.error('实际:', ids.join(', '));
}
