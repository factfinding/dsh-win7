# DSH Win7 适配：交接文档

写于 2026-10-15。新对话先读完本文件，再动手。

## 目标

让 DeepSeek Harness 桌面版（Electron 应用）在 **Windows 7 x64** 上运行。这是个人 fork / 实验，不打算提交到上游。

本目录 `D:\Documents\2026\dsh-win7` 用来放第三方源码、补丁、构建脚本和产物。

**2026-10-16 决定：不再使用 `D:\Documents\2026\deepseek-harness` 那份 checkout，所有代码（包括主仓库）都 clone 到本目录。** **同日决定：主仓库以 tag `dsh-v0.2.0-rc.2` 为基础**，这是官网能下载到的最新 desktop 版本。下文"主仓库关键事实"已按这个 tag 重新核对。

## 已做的决定

1. **Electron：** 使用社区补丁 [e3kskoy7wqk/Electron-for-windows-7](https://github.com/e3kskoy7wqk/Electron-for-windows-7) 的 `v44.2.0`。它只提供补丁，没有二进制，需要自己编译 Chromium + Electron。`dsh-v0.2.0-rc.2` 的 `apps/desktop/package.json` 写的是 `electron ^44.0.0`，44.2.0 在这个范围内，需要把锁定的版本定到 44.2.0。（master 上已经是 `^44.7.0`。）
2. **独立 Node：** 从上游 Node **v24.21.0** 源码加 Win7 补丁编译出真正的 `node.exe`。**不**拿 Electron 冒充 `node.exe`，原因：
   - 调用方用 `execFile` 直接执行写死路径的 `node.exe`。Node 从 2024 年起不允许不经 shell 启动 `.cmd`，所以必须是真 exe。
   - Electron 的 ABI 和普通 Node 不同，还开启了 V8 memory cage。agent 用 pnpm 装的原生模块预编译包会加载失败。
   - Electron 的 Node 用 BoringSSL，不是 OpenSSL。
   - primary-runtime 会被整份复制到 Harness home，复制 Electron 体积太大；改为指向安装目录又会在卸载或升级后失效。
   - 补丁版 Electron 44.2.0 里的 Node 小版本和 `lock.json` 锁定的 24.21.0 对不上。
3. **当前阶段（Phase 1）：** 先做独立 `node.exe`，再让主仓库的打包流程能用本地 Node 压缩包。Electron 的编译放到后面。

## 主仓库关键事实

2026-10-16 从 `github.com/deepseek-ai/deepseek-harness` 部分克隆（`--filter=blob:none`）到 `deepseek-harness/`。分支 `dsh-v0.2.0-rc.2-win7` 建在 tag `dsh-v0.2.0-rc.2`（`639ed01539`，2026-09-29，版本 `0.2.0-rc.2`）上。用户 fork 了官方仓库：`github.com/factfinding/deepseek-harness`，本地远程名是 `fork`；`origin` 仍指向官方仓库。截至 2026-10-16，fork 上只有 `master`，本机 Git Credential Manager 里没有存 GitHub 账号，`gh` 也没装。仓库里单独配置了提交身份（同 `node/`）。以下内容都按这个 tag 核对过。

- **主仓库的说明文件是 `AGENTS.md`，必须先读。** 本机 git 的 system 级配置是 `core.symlinks=false`，而且 Windows 开发者模式没开、创建软链接需要管理员权限，所以仓库里的 14 个软链接被检出成了只含目标路径的文本文件。受影响的有 `CLAUDE.md`、`packages/CLAUDE.md`、`vendor/CLAUDE.md`、`.claude/skills`（应指向 `.agents/skills`）以及 `snapshots/` 下的若干文件，Claude 不会自动加载这些说明和 skill。要避免，需先开启开发者模式，再用 `git -c core.symlinks=true clone …`。用户尚未执行。
- **独立 Node 的来源：** `scripts/primary-runtime/prepare.ts` 的 `preparePrimaryRuntime()` 原本固定从 `https://nodejs.org/dist/v${lock.nodeVersion}/${nodeFilename}` 下载，按 sha256 缓存并校验，解压后只复制 `node-v24.21.0-win-x64\node.exe` 和 `LICENSE`，zip 里的 npm 等都不用。Python 来自 python-build-standalone。
- **锁文件** `scripts/primary-runtime/lock.json`：`nodeVersion 24.21.0`、`pythonVersion 3.12.14`、`pythonRelease 20260901`，和 master 相同。`win-x64` 的官方 `nodeSha256` 是 `158f7685…`，另有 Python 的哈希和 wheels 列表。
- **pnpm：** 根目录和 `apps/desktop` 都锁定 `pnpm 11.7.0`（master 上是 11.28.5）。打包时把打包机上安装的 `pnpm` npm 包整个复制到 `primary-runtime/dependencies/pnpm`，运行时用独立 node 执行 `dependencies/pnpm/bin/pnpm.mjs`（`packages/skill/tool-workspace-dependencies/src/index.ts`）。
- **独立 `node.exe` 的三个使用方**（都按路径 `primary-runtime/dependencies/node/bin/node.exe` 调用）：
  - `apps/desktop/src/command-management.ts:139`：菜单"管理 dsh 命令…"的 worker，用 `execFile` 调用
  - `apps/desktop-host/src/office.ts:35`：Office 转换 skill
  - `packages/skill/tool-workspace-dependencies/src/index.ts:145`：agent 的 `load_workspace_dependencies` 工具，首次调用时把 primary-runtime 复制到 Harness home
- **Electron 当 Node 用的地方：** Host、插件、内置 `dsh` CLI 都通过 `ELECTRON_RUN_AS_NODE=1` 运行，见 `apps/desktop/scripts/node-bin/{node,node.cmd}`，打包后在 `resources/runtime/bin`。这部分会随补丁版 Electron 一起获得 Win7 支持。
- **Electron 的下载：** `apps/desktop/scripts/prepare-runtime.ts` 第 37–39 行，用 `@electron/get` 的 `downloadArtifact`，版本取自 `electron/package.json`，下载到 `BUILD_PATHS.downloads`。换成本地补丁版需要改这里。
- **Windows 打包：** `pnpm run package:desktop:win:x64:unsigned`，加 `--check` 只检查配置。需要先建好 `apps/desktop/.env.windows`（Git 已忽略），自己打包建议这样配置：
  ```ini
  DSH_DESKTOP_APP_ID=com.deepseek.harness
  DSH_DESKTOP_AUTO_UPDATE_ENV=production
  DSH_DESKTOP_MANDATORY_UPDATE_PROD_ORIGIN=https://<用户控制的域名>
  ```
  `production` 模式下不能写 `allowedAuthOrigins`；默认的 `test` 模式要求配置飞书登录地址，外部用不上。这个 tag 的打包说明在 `apps/desktop/README.zh.md`（master 上的 `apps/desktop/packaging/README.zh.md` 在这里不存在），可从 `apps/desktop/.env.windows.example` 复制模板。按该说明（第 321–324 行），未签名打包要求设置 `DSH_DESKTOP_APP_ID`，产物写到 `apps/desktop/.desktop-build/targets/win-x64/unsigned-artifacts/`，不需要 EV 证书。但第 419 行说明，所选环境的强制更新策略源站即使是未签名构建也必须配置。用户还没决定更新策略地址填什么。
  - **运行时行为（2026-10-17 查过源码，路径相对 `apps/desktop/`）：** 打包时 origin 写进安装包 `package.json` 的 `dshMandatoryUpdatePolicy`，打包后的应用只认这个值，不读环境变量（`src/main.ts:1285-1291`）。主进程对 `<origin>/api/v0/check_client_update?scenario=…` 发不带签名校验的 HTTPS GET（`src/mandatory-update-policy.ts:187-190`，超时 15 秒）。时机：启动时（不等待结果）、每 10 分钟（失败时退避到 1 小时）、窗口获得焦点、系统唤醒，以及菜单"检查更新"。**请求失败时不拦用户**：网络错误、DNS 失败、非 200、JSON 不对都只记一个不显示的 `unavailable`（191-205 行），初始状态是不拦，状态不跨重启保存。只有成功响应里 `code: 40005` 才会弹出强制更新窗口，关掉窗口就退出应用。没有任何受支持的开关能关掉这个检查（`AUTO_UPDATE_ENV` 只能是 `test`/`production`）。自动更新在未签名构建里本来就是关的（`publish` 为 null，不打包 `app-update.yml`）。
  - **自己打包建议：** `DSH_DESKTOP_AUTO_UPDATE_ENV=production`，`DSH_DESKTOP_MANDATORY_UPDATE_PROD_ORIGIN=https://policy.invalid`（`.invalid` 是保留顶级域，永远解析不了，所以永远不会被强制更新拦住，也不会弹出登录），`DSH_DESKTOP_MANDATORY_UPDATE_CONFIG='{}'`（production 模式不能写 `allowedAuthOrigins`，示例文件里那一行要改）。`.env.windows` 只允许白名单里的键，打包时父进程环境里的 `DSH_DESKTOP_*` 会被丢掉，所以这些值只能写在文件里。

## Win7 阻碍清单

| 层 | 主仓库现状 | 方案 | 状态 |
|---|---|---|---|
| Electron | `^44.0.0`（tag `dsh-v0.2.0-rc.2`） | 社区补丁 v44.2.0，自己编译 | **已编出并在 Win7 上运行**（2026-10-17）：以 Node 方式运行和默认窗口都正常，GPU 退回软件合成。见"Electron 44.2.0（Win7）编译" |
| 独立 Node | 24.21.0，来自 nodejs.org | 上游源码加补丁自己编译 | **Phase 1 基本完成**：Win7 版 node.exe 已编出并通过测试，主仓库的 primary-runtime 已能接入（改动未提交） |
| Python | 3.12.14，python-build-standalone | [adang1345/PythonVista](https://github.com/adang1345/PythonVista)（原 PythonWin7）的 3.12.14 NuGet 包 | **已接入并在 Win7 上验证**（`prepare.ts`/`lock.json`，未提交）。原来打包的 python-build-standalone 3.12.14 在 Win7 上启动失败：`python312.dll` 缺 `api-ms-win-core-path-l1-1-0.dll`、`CopyFile2`、`PssCaptureSnapshot`/`PssQuerySnapshot`/`PssFreeSnapshot` |
| 终端 | node-pty `1.2.0-beta.15`；`packages/subprocess/subprocess-local/src/index.ts:286` 在 Windows 上强制 `useConptyDll: true` | ConPTY 要 Win10 1809 以上，新版 node-pty 已删除 winpty。自己写的 `@dsh-win7/pty-winpty`（koffi + winpty.dll） | **已在 Win7 上验证**，接入代码已写（`subprocess-local` + 覆盖层），未提交 |
| 搜索 | `@vscode/ripgrep` 1.18.0（ripgrep 15.0.0） | 用 `x86_64-win7-windows-msvc` 目标自己编 | 官方 `rg.exe` 在 Win7 上崩溃（0xC0000005）；**Win7 版已编出并验证**，通过覆盖层接入打包 |
| Shell（PowerShell） | `pwsh-local` 优先用 pwsh 7，找不到时退回系统自带的 `powershell.exe`；Win7 自带的是 2.0 | 用 PowerShell 7.2.24（已验证在沙箱里可用） | Windows PowerShell 2.0 在受限令牌下启动失败（拒绝访问），编码前缀也要 PS 5.0 以上。pwsh 7.2 随包放在 `resources/runtime/pwsh`，Win7 上由 desktop 加到 Host 的 PATH（代码已写，未提交） |
| Office 转换 | `@deepseek-ai/libreoffice-kit-win32-x64` 的 `libreoffice-kit.exe` | dshlo.dll 兼容层 + 改 exe 导入表，再给 kit 的 `rm` 加只读属性处理 | **已在 Win7 上通过 CLI 验证**（2026-10-16），通过覆盖层接入打包；agent 通过 Office 技能调用要到 desktop 里验证 |
| 语音输入（实验性，默认关闭） | `sherpa-onnx-node` 1.13.8 + `sherpa-onnx-win-x64`（ONNX Runtime 1.28.2），模型从 Hugging Face 下载 | dsho.dll 兼容层 + 改 `onnxruntime.dll` 导入表 | **已在 Win7 上通过推理脚本验证**（2026-10-17，`scripts\win7-voice-test.js`），通过覆盖层接入打包；界面录音待验证 |
| 沙箱 | `packages/sandbox/sandbox-windows-acl`，通过 koffi 3.1.1 调用 `CreateRestrictedToken`、`AddMandatoryAce`、`ConvertStringSidToSidW` 等 | 用的都是 Vista 时代的 API，大概率不用改 | koffi 3.1.1 已在 Win7 上验证能加载并调用 Win32 API（2026-10-16）；沙箱实际用到的那几个 API 还没测 |
| pnpm | 11.7.0（tag），以 npm 包形式随 primary-runtime 分发，用独立 node 运行 | 不用改 | 11.7.0 已在 Win7 上验证可用，reflink 模块加载失败后自动退回复制。注意不要升级到 pnpm 12：它的原生程序在 Win7 上启动失败 |
| 浏览器（Web 模式） | 无 | [Supermium](https://github.com/win32ss/supermium/releases)，稳定版 144 R5 | 可用 |

## Phase 1 步骤：Win7 版 node.exe v24.21.0

**进度（2026-10-16）：** 步骤 1–3 已完成。`node/` 的本地分支 `win7` 基于 `v24.21.0`，共 7 个提交，每个提交信息里注明了出处，可用 `git -C node log --oneline v24.21.0..win7` 查看：

| 提交 | 来源 |
|---|---|
| uv：GetHostNameW 回退 | Electron 补丁 `third_party/electron_node/fix_crash_caused_by_gethostnamew_on_windows_7.patch` |
| uv：uv_get_process_title 崩溃 | Electron 补丁 `third_party/electron_node/fix_crash_uv_get_process_title_on_windows_7.diff` |
| uv：GetSystemTimePreciseAsFileTime 动态加载 | Electron 补丁 `third_party/electron_node/FR_add_real-time_clock_version_of_uv_hrtime()_#1674.diff` |
| v8：CreateWaitableTimerExW 动态加载 | Electron 补丁 `chromium/c19d5d67….diff` |
| v8：QueryThreadCycleTime 动态加载 | Electron 补丁 `chromium/ee43805a….diff` |
| v8：关闭 ETW 栈遍历 | Electron 补丁 `chromium/531c83c4….diff` 的 api.cc 部分；它改 `v8.gni` 的那一处对 gyp 构建无效，改为修改 `tools/v8_gypfiles/features.gypi` |
| src：启动检查放宽到 Win7 SP1 | 自己加的。Electron 不经过 `src/node_main.cc`，所以它的补丁里没有这一处 |

Electron-for-windows-7 v44.2.0 里只有这 6 个补丁涉及 libuv 或 V8，其余 600 多个改的都是 Chromium 和 Electron 本体。Node 自带的 `deps/openssl` 和 `deps/icu-small` 在 Electron 里没有对应部分（Electron 用 BoringSSL 和 Chromium 的 ICU），所以没有补丁可以参考，要等编译出来后检查导入表才能知道还有没有 Win8 以上的 API。

**编译结果（2026-10-16）：** 步骤 4、5 已完成，第 7 步完成了基本检查。
- `win7` 分支 `f1e720bc` 编译成功，用 `scripts/build-node.cmd`（`vcbuild.bat release x64 package`，含 LTCG，full-icu）。产物：`out/node-v24.21.0-win-x64.zip`，sha256 `3309fc6441bc8c5f14d92ebfed058738c252f2c4caa18c52839b080b04610162`（也存在同名 `.sha256` 文件里）。zip 由 vcbuild 的 package 步骤生成，和官方包的打包逻辑相同：顶层目录 `node-v24.21.0-win-x64\`，共 1994 个文件。
- 导入表：PE 子系统版本 6.00。只导入 11 个传统系统 DLL（kernel32、advapi32、ws2_32、crypt32、dbghelp、iphlpapi、user32、ole32、shell32、userenv、winmm），共 425 个函数，没有 `api-ms-win-*`，也没有延迟加载。在 Win7 虚拟机里逐个 `GetProcAddress`，全部存在。没有导入 KB2533623 提供的任何函数，所以不依赖这个补丁。
- `scripts/win7-smoke.js` 在 Win7 虚拟机里 21/21 通过，其中 `os.hostname()` 也通过了（DeftKing 的 Node 22 就失败在这一项上），说明 libuv 补丁生效。

- 包管理器和原生模块（2026-10-16，在 Win7 虚拟机里用 zip 解压出的完整目录测试）：npm 11.19.0、npx、corepack 0.36.0 都能运行，虚拟机能访问 registry.npmjs.org 和 registry.npmmirror.com。用 npm 和 pnpm 10.34.7（通过 corepack 拉起）分别装 `koffi@3.1.1`、`bufferutil`、`better-sqlite3`，再跑 `scripts/win7-native-test.js`，两种目录布局下都是 4/4 通过：ABI 137、koffi 调用 `GetCurrentProcessId`、bufferutil mask/unmask、better-sqlite3 内存数据库。这 3 个包的 win32-x64 预编译文件都随包一起下载，npm 11 和 pnpm 10 默认不运行安装脚本，对它们没有影响。
- **pnpm 12 在 Win7 上运行不了。** corepack 默认拉 pnpm latest，即 12.11.2，它下载的 `pnpm-native.exe` 启动时报 0xC0000139（找不到入口点）。导入表里缺 `GetSystemTimePreciseAsFileTime`、`ProcessPrng`、`WaitOnAddress`、`WakeByAddressAll`、`WakeByAddressSingle`，还缺 `combase.dll`，看起来是新版 Rust 编译的程序。pnpm 10 是纯 JS，可以用。**要查主仓库里 DSH 内置或锁定的 pnpm 是哪个版本。**

- pnpm 11（DSH 实际用的版本）：按 DSH 的方式，用我们的 node 执行 npm 包里的 `bin/pnpm.mjs`，11.7.0 和 11.28.5 在 Win7 上都正常，`--version` 能跑，`add` 能装包，装好的原生模块 4/4 通过。`add` 退出码是 1，那是 pnpm 11 遇到被忽略的安装脚本时报 `ERR_PNPM_IGNORED_BUILDS`，和 Win7 无关。pnpm 11 自带的 `@reflink/reflink-win32-x64-msvc` 原生模块在 Win7 上加载不了（缺 `ProcessPrng`、`WaitOnAddress`、`WakeByAddressAll`、`WakeByAddressSingle`），pnpm 会退回到复制文件（日志显示 "Packages are copied"），功能正常，只是更慢、更占磁盘。它自带的 `fastlist-0.3.0-x64.exe` 导入的函数都在。
- **步骤 6（2026-10-16，未提交）：** `deepseek-harness/` 的 `dsh-v0.2.0-rc.2-win7` 分支上改了两个文件。`scripts/primary-runtime/prepare.ts` 新增 `nodeArchive()`：设置了环境变量 `DSH_PRIMARY_RUNTIME_NODE_ARCHIVE` 时，直接用这个本地 zip，不从 nodejs.org 下载，但仍按 `lock.json` 校验 sha256。`lock.json` 的 win-x64 `nodeSha256` 改成了我们的 zip（`3309fc64…`）。所以没设这个变量时，下载到的官方包会因哈希不符直接失败。已验证（2026-10-16）：用 `tools/` 下的官方 Node 24 在主仓库 `corepack pnpm install --frozen-lockfile` 成功（设了 `ELECTRON_SKIP_BINARY_DOWNLOAD=1`，日志在 `out/pnpm-install.log`；lefthook 装了 pre-commit/pre-push/pre-merge-commit 钩子）。设好 `DSH_PRIMARY_RUNTIME_NODE_ARCHIVE` 后执行 `corepack pnpm run prepare:primary-runtime --target win-x64 --output out\primary-runtime-test --cache out\primary-runtime-cache` 成功，脚本自带的本机自检全部通过，产物里的 `node.exe` 和我们编的一致。反向测试：让环境变量指向官方 zip，会报 checksum mismatch 并退出。主仓库提交前要先问用户。
- **把生成的 primary-runtime 整体放进 Win7 虚拟机运行（2026-10-16）：** `dependencies\node\bin\node.exe` 版本检查通过；`node dependencies\pnpm\bin\pnpm.mjs --version` 输出 11.7.0。**Python 3.12.14（python-build-standalone）启动失败**，退出码 0xC0000135（找不到 DLL）：`python312.dll` 缺 `api-ms-win-core-path-l1-1-0.dll`（`PathCch*`，Win8）、`CopyFile2`（Win8）、`PssCaptureSnapshot`/`PssQuerySnapshot`/`PssFreeSnapshot`（Win8.1）。`python.exe` 本身导入的函数都在。

- **Python 换成 PythonVista（2026-10-16，未提交）：** 用户找到 [adang1345/PythonVista](https://github.com/adang1345/PythonVista)（就是改名后的 PythonWin7，MIT，仍在维护，从 python.org 源码编译，补丁在其 `patches/` 目录，自带替代版 `api-ms-win-core-path-l1-1-0.dll`）。选用它的 NuGet 包 `python.3.12.14.nupkg`（sha256 `13bd3e75…`）：包里的 `tools/` 正好是 DSH 要的 `python/python.exe` + `python/Lib/site-packages` 结构，并且带 pip。embeddable zip 不带 pip，不适用。主仓库改动：`lock.json` 的 win-x64 新增 `pythonNupkg {url, sha256}`（原有的 python-build-standalone 字段保留不用，减少和官方的冲突）；`prepare.ts` 新增 `unpackPython()`，win-x64 下载这个 nupkg，把 `tools/` 改名为 `dependencies/python`，其他平台不变；`prepare.spec.ts` 新增一个测试，检查 URL 和 `pythonVersion` 一致、它会改变 win-x64 的 payloadDigest 且不影响其他平台。`vitest run scripts/primary-runtime/prepare.spec.ts` 17/17 通过；重新生成 primary-runtime 后本机自检通过；整个 payload 放进 Win7 虚拟机，Python 的导入测试、`smoke.py`（Office 文档往返）、`pip check` 以及 ssl/sqlite3/ctypes/Pillow/lxml/venv 全部通过，node 和 pnpm 也正常。DSH 锁定的 numpy/pandas/Pillow/lxml 等 wheel 原样可用。
- **Web 版（npm 包 `@deepseek-ai/dsh@0.2.0-rc.2`）在 Win7 上（2026-10-16）：** 在虚拟机里用我们的 node 执行 `npm install @deepseek-ai/dsh@0.2.0-rc.2` 成功（536 个包，约 8 分钟，装在 `C:\dsh-test\dsh-web`；npm 11 跳过了 node-pty、koffi、dsh-subprocess-local 等的安装脚本）。`dsh --help`、`dsh web --help` 正常；`dsh web --no-open --host 127.0.0.1 --port 8787` 能启动，带 token 访问会 303 跳转、设置 cookie，页面 200，标题 "DeepSeek Harness"。用户在虚拟机里用 Supermium 打开后，聊天能正常收发。"添加工作区"点了没反应，原因是最初用 vmrun 在 Session 0 启动了服务，原生目录选择框（`dsh-host-directory-picker-native` 派生出的 worker 进程，通过 comdlg32 弹出）出现在 Session 0，被 Win7 的"交互式服务检测"拦截。改用 `vmrun runProgramInGuest -interactive -noWait` 在 Session 1 重启服务（启动脚本 `C:\dsh-test\dsh-web-start.cmd`，日志 `C:\dsh-test\dsh-web.log`，每次启动 token 都会变）。依赖里的原生程序在 Win7 上：koffi、node-addon-require-builtin、conpty.node 本身可用；**node-pty 的 `OpenConsole.exe`（终端）、`@vscode/ripgrep` 的 `rg.exe`（搜索）、`@deepseek-ai/libreoffice-kit-win32-x64` 的 `libreoffice-kit.exe`（Office）都缺 Win8/Win10 API**，用到相应功能时会失败；sharp（libvips）和 sherpa-onnx 自带的 DLL 还没查。npm 方式安装时 primary-runtime 从哪里来、agent 的 `load_workspace_dependencies` 能否工作，还没查。

- **Web 版试用中发现的两个问题（2026-10-16）：**
  - "查找文件"报 `glob search failed (exit 3221225477)`，即 0xC0000005。直接运行 `rg.exe --version` 也是这个退出码，是前面查出的 ripgrep 缺 API 问题。
  - **"运行命令"报沙箱不可用：`windows-acl-run: AssignProcessToJobObject failed (Win32 5)`。** 根因是 Win7 不支持嵌套 Job。在 Windows 上，`subprocess-local` 的 spawn-runner 用 `win32-process` 的 `spawnCurrentTokenJobProcess` 启动目标进程（沙箱命令的目标就是 windows-acl runner），并把它放进 kill-on-close Job J1，J1 不允许脱离。runner 用 `CreateProcessAsUserW` 创建受限进程时，子进程自动继承 J1，再分配到它自己的 Job J2 时，Win7 返回 ERROR_ACCESS_DENIED。（另外 libuv 第一次 spawn 时会把 node 自身放进它的全局 Job，见 `node/deps/uv/src/win/process.c:109`；那个 Job 带 `SILENT_BREAKAWAY_OK`，不是这次失败的原因，但会让 `IsProcessInJob` 对 dsh 的 node 进程返回 True。）
  - **修复（主仓库，未提交；在虚拟机里直接改了装好的 npm 包来验证，等用户确认）：** `packages/subprocess/win32-process/src/process.ts` 新增 `NESTED_JOBS`（`os.release()` 低于 6.2 时为 false）。仅在 Win7 上：`spawnCurrentTokenJobProcess` 的 Job 附加 `JOB_OBJECT_LIMIT_BREAKAWAY_OK`；`spawnInheritedJobProcess` 创建受限进程时加 `CREATE_BREAKAWAY_FROM_JOB`。`abi.ts` 新增这两个常量。受限进程的 Job J2 不加任何脱离标志，所以沙箱进程的子孙进程仍然全部留在 J2 里；runner 退出时 J2 句柄关闭，受限进程也会被结束。没有用 `SILENT_BREAKAWAY_OK`，因为那样普通命令的子孙进程会全部脱离 J1，取消命令时清理不干净。Win7 上的代价：J1 里的进程（runner 和不受沙箱限制的普通命令）可以显式创建脱离 J1 的子进程。`vitest run packages/subprocess/win32-process` 59/59 通过（Win11 上 `NESTED_JOBS` 为 true，行为不变）。虚拟机里改的是 `C:\dsh-test\dsh-web\node_modules\@deepseek-ai\dsh-win32-process\lib\index.js`，原文件备份为同目录的 `index.orig.js`。

  - **Job 修复生效后，下一层是 PowerShell 的问题。** 命令能在沙箱里启动了，但返回退出码 0xFFFF0000，stderr 是乱码。在虚拟机里直接调用 runner（`node …\dsh-sandbox-windows-acl\lib\runner.js --workspace <ws> --temp <root> --mode workspace-write -- <argv>`，stdin 必须重定向，比如 `< nul`，否则报 `SetHandleInformation failed (87)`）复现：受限令牌下 `cmd /c echo` 正常；**Win7 自带的 Windows PowerShell 2.0 在受限令牌下启动失败**，stderr 为 UTF-16："Windows PowerShell 被终止，返回以下错误: 拒绝访问。"原因还没查。另外，`packages/shell/pwsh-local/src/index.ts:49` 的编码前缀 `[System.Text.UTF8Encoding]::new($false)` 要 PowerShell 5.0 才支持，在 2.0 上会报 MethodNotFound，输出编码也就没被设成 UTF-8（中文系统下是 GBK，DSH 按 UTF-8 解析就成了乱码）。
  - **PowerShell 7.2.24 可以替代**（微软签名，zip 的 sha256 `a1ccb6d8…` 和发布说明一致，放在本机 `out/pwsh/`）。它在 Win7 上能直接运行；在沙箱里用 DSH 原样的前缀，能写工作区文件，中文输出是正确的 UTF-8。`pwsh-local` 查找 pwsh 的顺序是 `%ProgramFiles%\PowerShell\7\pwsh.exe` → PATH 里的 `pwsh.exe` → 系统自带的 `powershell.exe`。虚拟机里把它解压到了 `C:\dsh-test\pwsh72`，并在 `dsh-web-start.cmd` 里把这个目录加到 PATH 最前面，没有往系统里安装。WMF 5.1（Windows PowerShell 5.1）官方支持 Win7 SP1（需 .NET 4.5.2 以上），但没测它在受限令牌下能不能启动。**2026-10-16 用户决定：pwsh 7.2 随 desktop 安装包分发，由 desktop 在启动 Host 时控制 PATH 等环境变量**（最终目标是 desktop，Web 版只是测试手段）。具体放在哪、怎么接进打包流程，还没做。
  - **ripgrep 的处理（用户决定）：** 用 Rust 的 `x86_64-win7-windows-msvc` 目标重新编译。这是 Tier 3 目标，没有预编译的 std，要用 `-Z build-std` 从源码编。nightly 1.101.0（2026-10-15）的 std 在 win7 目标下编不过：`std/src/sys/stdio/windows.rs` 里 `is_console` 被 `#[cfg(not(target_vendor = "win7"))]` 排除了，但调用处没有排除。所以改用 stable 1.96.0 的 `rust-src` 加 `RUSTC_BOOTSTRAP=1`。`@vscode/ripgrep` 1.18.0 带的是 ripgrep 15.0.0（rev `3a612f88b8`，`+pcre2`，静态 CRT），源码克隆在 `ripgrep/`，同一提交。编译脚本 `scripts/build-ripgrep.ps1`（`release-lto` 配置，`--features pcre2`，`+crt-static`）。DSH 通过 `packages/fs/tool-fs-search/src/search-core.ts` 的 `resolveRgPath()` 取 `@vscode/ripgrep` 的 `rgPath`（Electron 里换成 `.asar.unpacked`），所以只要替换 `@vscode/ripgrep-win32-x64/bin/rg.exe`，DSH 代码不用改。**已编出（2026-10-16）**：`out/rg-15.0.0-win7-x64.exe`，sha256 `0d938ebb…`（完整值在同名 `.sha256` 文件里），4.1 MB，编译用时约 3.5 分钟。`--version` 输出和官方那份一致（`15.0.0 (rev 3a612f88b8)`，`+pcre2`，PCRE2 10.45 带 JIT）。只导入 advapi32/kernel32/ntdll/userenv 共 132 个函数，在 Win7 虚拟机里全部存在；`--version`、`--files`、`-P` 搜索都正常。已替换虚拟机里 `C:\dsh-test\dsh-web\node_modules\@vscode\ripgrep-win32-x64\bin\rg.exe`，原文件备份为同目录的 `rg.orig.exe`。打包时怎么替换（pnpm patch、打包脚本覆盖，还是自己发布一个 platform 包），还没定。

  - **看图失败：sharp 报 `ERR_DLOPEN_FAILED: The specified procedure could not be found`。** `@img/sharp-win32-x64`（sharp 0.35.5，libvips 8.18.7）的 `libvips-42.dll` 静态链接了用 Rust 写的 librsvg，导入了 `api-ms-win-core-synch-l1-2-0.dll!WaitOnAddress/WakeByAddressSingle/WakeByAddressAll` 和 `bcryptprimitives.dll!ProcessPrng`。它从 synch-l1-2-0 一共导入 10 个函数，另外 7 个（InitOnce*、条件变量）Win7 的 kernel32 里有。libvips 的 Windows 构建链很重，不打算重编，改用**兼容层 DLL**：`shim/dshw7.c` + `shim/dshw7.def`，用 `scripts/build-shim.cmd` 编到 `out/shim/dshw7.dll`（x64，静态 CRT，只导入 kernel32）。系统有真正的实现时一律调用真实 API，Win8+ 行为不变。Win7 上 `WaitOnAddress` 用 256 个桶的 SRWLOCK + CONDITION_VARIABLE 模拟（比较和唤醒都在桶锁内，不会丢唤醒；Single 也唤醒整桶，这是允许的虚假唤醒），`ProcessPrng` 用 `SystemFunction036`。synch-l1-2-0 里 Win7 已有的函数都转发给 kernel32。再用 `scripts/patch-imports.ps1` 把 `libvips-42.dll` 导入表里的两个 DLL 名原地改成 `dshw7.dll`（原版 libvips 本来就没有签名）。在虚拟机里替换了 `C:\dsh-test\dsh-web\node_modules\@img\sharp-win32-x64\lib\libvips-42.dll`（原文件备份为 `libvips-42.orig.dll`），并放入 `dshw7.dll`。用 node 直接测试：生成 PNG、metadata、resize+JPEG、WebP、**SVG（librsvg）转 PNG** 全部通过。pnpm 11 的 reflink 模块缺的也是同样 4 个函数，可以用同样的办法处理。

  - **Office 转换（libreoffice-kit 0.1.5）：** agent 并不是直接调用它。Office 技能（`packages/skill/skill-office`，`office-docx`/`office-pptx`/`office-xlsx`）的 `get()` 会在技能说明末尾附上一段 "Installed LibreOffice Kit"，给出 node 和 `lib/cli.js` 的绝对路径。所以只有 agent 先加载了 Office 技能才会用它；有一次用户让它把 docx 转 PDF，它没加载技能，直接去找 Word/LibreOffice/pandoc。CLI 子命令：`capabilities --json`、`convert --input --output`、`render`、`recalculate`。在 Win7 虚拟机里：`capabilities` 正常（只走 JS），`convert` 失败：`LibreOffice helper returned an invalid response (exit 3221225785)`，即 0xC0000139，`libreoffice-kit.exe` 起不来。Web 版的 Office 文件预览也依赖它（`dsh-web-app` → `dsh-office-to-pdf`）。
  - **"文件资源服务不可用"（侧栏文件预览）：** 来自 `ui-sidebar-documentpreview` 的 `TextPreview`，条件是文件资源快照的状态为 `none`，即浏览器端 `ctx.resources` 没有 `file` 协议的提供者（`packages/client/resources/src/client/resources.ts`）。提供者由 `api-workspace-files` 的浏览器端插件注册（需要注入 `resources`、`remote`、`remote.workspaceFiles`）。服务端插件在运行（插件页显示正常，文件树能列文件），浏览器控制台只有一个 `/open-in-app/icon/explorer` 的 404。已排除的原因：后注册不刷新（`register()` 会 attach 已有记录）、Windows 路径编码问题（`file-address.ts` 处理正确）。**结论（2026-10-16）：是 Supermium 的问题**，用户在 Win11 上用同版本 Supermium 打开本机跑的同版本 Web 版（`out/host-web/`，`DSH_HOME=out/host-web/dsh-home`）也一样不行，和 Win7 无关。目标是 desktop（用 Electron 自带的 Chromium），用户决定不处理。

  - **终端（侧栏"新建终端"报 `Cannot launch conpty`，agent 的 terminal_* 工具同样）：** 两者都走 `subprocess.spawnTerminal` → `packages/subprocess/subprocess-local/src/index.ts` 的 `requireNodePty().spawn()`，DSH 只用到 IPty 的 `pid/onData/onExit/write/resize/pause/resume/kill`。用户选了"koffi + winpty.dll 适配层"：`shim/pty-winpty/`（`@dsh-win7/pty-winpty`，CJS，按 node-pty 的接口提供 `spawn()`），`scripts/build-pty-winpty.ps1` 把它和 winpty 0.4.3 的 x64 `winpty.dll`、`winpty-agent.exe` 组装到 `out/pty-winpty/`（发布包 `winpty-0.4.3-msvc2015.zip` sha256 `35a48ece…`，没有签名，2017 年的预编译版；正式打包时建议从源码自己编）。winpty 两个文件的 283 个导入在 Win7 上都存在。踩过的坑：CONIN 是只入站的管道，`net.connect` 会退回到只读方式打开，导致写不进去，改用 `fs.openSync(name, O_WRONLY)`。本机和 Win7 上，cmd 与 pwsh 7.2 都通过测试：输入输出、resize、`exit 7` 的退出码、kill（退出码 0xC000013A）。pwsh 下偶尔有 PSReadLine 重绘的残影，属于屏幕抓取的局限。虚拟机里装到了 `C:\dsh-test\dsh-web\node_modules\@dsh-win7\pty-winpty\`，并修改了 `@deepseek-ai/dsh-subprocess-local/lib/index.js`：Win7（`os.release()` 低于 6.2）时 `createLazyRequire` 加载 `@dsh-win7/pty-winpty`，否则照旧加载 `node-pty`；原文件备份为 `index.orig.js`。主仓库源码还没改。

  - **Office 转换已修通（2026-10-16，Win7 虚拟机里用 CLI 验证）：** `@deepseek-ai/libreoffice-kit-win32-x64` 0.1.5 只有一个 exe（`bin/libreoffice-kit.exe`，LibreOffice 静态链接，没签名），`program/` 下 639 个文件全是资源。它导入 48 个模块共 1466 个函数，Win7 只缺 4 个：kernel32 `GetCurrentPackageFullName`、`GetSystemTimePreciseAsFileTime`，user32 `SetThreadDpiAwarenessContext`，bcrypt `BCryptKeyDerivation`（`delay shell32.dll!Characteristics` 是 dump 脚本的误报）。做法：兼容层 `shim/dshlo.c` → `out/shim/dshlo.dll`。`scripts/gen-forward-def.ps1` 根据 exe 的导入表生成 `out/shim/dshlo.def`：exe 从这 3 个 DLL 导入的 419 个函数里，415 个转发回原 DLL，4 个自己实现（有真实 API 就调真实的；Win7 上分别返回 NO_PACKAGE、退回 `GetSystemTimeAsFileTime`、返回与进程级 DPI 相符的上下文（返回 NULL 时 kit 会报 "Failed to configure Windows raster DPI"）、返回 STATUS_NOT_SUPPORTED）。`scripts/build-shim.cmd dshlo out\shim\dshlo.def`（link 要列出被转发 DLL 的 .lib）。然后用 `patch-imports.ps1` 把 exe 的 `KERNEL32.dll`/`USER32.dll`/`bcrypt.dll` 改名为 `dshlo.dll`，产物在 `out/shim/libreoffice-kit.patched.exe`。之后还有一个问题：kit 把 `USERPROFILE` 指向临时 profile，Win7 的系统外壳会在那里建一个只读的 `Documents`（带 desktop.ini），导致清理时 `rm` 报 EPERM，最后返回 "LibreOffice conversion cleanup failed."（PDF 其实已经生成）。修法：在 kit 的 `lib/index.js` 和 `lib/cli.js` 里把 `rm` 包一层，Windows 上递归删除遇到 EPERM 时先清除整棵树的只读属性再重试一次。结果：docx/xlsx/pptx 转 PDF、pptx 渲染 PNG 全部成功（渲染出的中文正确），不再残留临时目录。虚拟机里替换的文件：`…\libreoffice-kit-win32-x64\bin\libreoffice-kit.exe`（原文件备份为 `libreoffice-kit.orig.exe`）+ `bin\dshlo.dll`；`…\libreoffice-kit\lib\index.js`、`cli.js`（原文件备份为 `*.orig.js`）。注意：虚拟机里 npm 装的 kit 是 0.1.5，主仓库锁定的是 0.1.1，接入打包时要按实际版本重新生成和打补丁。**Web 版没有 Office 技能**：`skill-office` 只组装在 `packages/bundle/sdk-app` 和 desktop（`apps/desktop-host/src/office.ts`，kit CLI 用 primary-runtime 的 `node.exe` 运行，也就是我们编的 Win7 版 node）里，所以在 Web 版里 agent 不知道有 kit，会去找 Word COM/LibreOffice/pandoc。用户决定不在 Web 版里测，留到 desktop 再验证 agent 调用这条路径。

**Web 版试用结果（2026-10-16，用户确认）：** 聊天、运行命令（Job 修复 + pwsh 7.2）、查找文件（Win7 版 rg）、看图（sharp + dshw7 兼容层）在 Win7 上都正常了。还不能用：终端（node-pty/ConPTY）、Office 转换和预览（libreoffice-kit）。侧栏文件预览的问题是 Supermium 的，不处理。

## desktop 打包流程（2026-10-16 梳理，tag dsh-v0.2.0-rc.2）

`pnpm run package:desktop:win:x64:unsigned` → `apps/desktop/scripts/package-target.ts win-x64 --unsigned`。要点：
- **安装包里的运行时 `node_modules`**：由 `apps/desktop/scripts/prepare-dsh.ts` 现场 `pnpm install` 生成（用下载的 Electron 当 Node 运行 pnpm 11.7.0；在临时工程里装，工作区包来自本地 tarball，外部包从 npm 安装，`nodeLinker: hoisted`）。然后复制到 `.desktop-build/targets/win-x64/dsh/node_modules`（138–143 行），之后写入 `desktop-runtime.json`，里面记录了每个文件的 SHA-256（162 行）。`afterPack` 和打包后的 smoke 都会按这份清单校验哈希。**仓库自带的 pnpm `patchedDependencies` 对这一步不生效。** 所以替换 rg/libvips/kit 等文件，必须放在 143 到 162 行之间。
- 原生文件最后在 `resources/app.asar.unpacked/dsh/node_modules/<包>/…`（`beforePack` 会按 PE 文件头把所有 exe/dll/node 都列进 asarUnpack）。
- **Electron**：`apps/desktop/scripts/prepare-runtime.ts:36-41` 用 `@electron/get` 下载，版本取自 `electron` 包（锁文件解析为 44.0.0），解压到 `.desktop-build/targets/win-x64/electron`。electron-builder 用 `electronDist` 指向这个目录。这份 Electron 同时也被用来运行打包时的 pnpm。
- **Host 进程**：`apps/desktop/src/host-process.ts:189-201` 的 spawn 用的 env 来自 `main.ts:445`（Windows 上就是桌面主进程的 `process.env`）。`desktopNodeEnvironment` 有一个没被用到的 `bin` 参数，传了就会把它加到 PATH 前面（`src/node-environment.ts:12-18`，`host-process.ts:199` 传的是 undefined）。pwsh 7.2 从这里注入 PATH。
- **安装程序**：electron-builder 的 NSIS，加上自带的 x86 `window-frame.dll`（`apps/desktop/installer/*.cpp/.h`，在 `beforeBuild` 里由 `scripts/prepare-windows-installer.ps1` 用 cl 编译）。**Win7 问题**：`installer/extract.h:57-58` 用了 `PROC_THREAD_ATTRIBUTE_JOB_LIST`（Win10 才有），解压会失败；`window-frame.cpp:256-280` 的 `InstallerApplyFrame` 在 DWM 调用失败时（Win7 关闭 Aero）返回错误，`lifecycle.nsh:19-24` 收到后会退出安装程序。

**接入计划：**
1. `subprocess-local`：Win7 上加载 `@dsh-win7/pty-winpty`（改源码）。
2. 运行时覆盖层：在 `prepare-dsh.ts` 第 143 到 162 行之间按清单替换或新增文件（Win7 版 rg.exe、改过导入表的 libvips + dshw7.dll、改过导入表的 libreoffice-kit.exe + dshlo.dll、kit 的 index.js/cli.js、pty-winpty）。清单里记录原文件的 sha256，原文件对不上就直接报错，避免上游版本变了以后悄悄替换错。
3. pwsh 7.2：`prepare-runtime.ts` 放进 `resources/runtime/pwsh`，Win7 上由 `main.ts` 把它加到 Host 的 PATH 里。
4. Electron：`prepare-runtime.ts` 支持用本地编译的 zip。
5. 安装程序：`extract.h` 在不支持 JOB_LIST 时退回到"挂起创建 + AssignProcessToJobObject"；DWM 失败不当作致命错误。

**接入进度（2026-10-16，主仓库改动未提交）：** 1–5 的代码都写好了，完整打包还没跑，要等 Electron 编出来。
- 1：`subprocess-local/src/index.ts` 的 `NODE_PTY_MODULE`，Win7 上是 `@dsh-win7/pty-winpty`，否则是 `node-pty`。
- 2：`apps/desktop/scripts/runtime-overlay.ts`（新文件）的 `applyRuntimeOverlay()` 读覆盖层的 `manifest.json`（`{schemaVersion:1, entries:[{path, source, replaces?}]}`）：有 `replaces` 时要求原文件 sha256 一致，没有时要求原路径不存在，然后复制。`prepare-dsh.ts` 在 `runtime:materialize-modules` 之后、写 `desktop-runtime.json` 之前，设置了 `DSH_WIN7_RUNTIME_OVERLAY` 时执行 `runtime:win7-overlay` 步骤。覆盖层由 `scripts\build-win7-overlay.ps1` 生成到 `out\win7-runtime-overlay`，共 8 项：rg.exe、libvips-42.dll + dshw7.dll、libreoffice-kit.exe + dshlo.dll、kit 的 index.js/cli.js、pty-winpty。文件和虚拟机里测过的逐字节相同，`applyRuntimeOverlay` 的测试通过。**原文件的哈希取自 `out\host-web\node_modules`（kit 0.1.5、sharp 0.35.5）。** 主仓库 lockfile 里是 kit 0.1.1、sharp 0.35.3，但 `prepare-dsh.ts` 打包时会在临时工程里用 `pnpm install --lockfile-only` 重新解析（依赖写的是 `^0.1.1`、`^0.35.3`），实际装的是当时的最新版。仓库的 `pnpm-lock.yaml` 只用于仓库开发，不进安装包。官方 rc.2 安装包也是这样，按 tag 日期（9/29）推算，装的是 kit 0.1.2（0.1.3 是 9/30 发布的）和 sharp 0.35.5。上游发了新版本后哈希就对不上，打包会报错，要用新版本重新生成覆盖层（kit 的 exe 还要重新生成 `dshlo.def`）。
- 3：`prepare-runtime.ts` 新增 `prepare:win7-pwsh` 步骤：设置 `DSH_WIN7_PWSH_ARCHIVE` 时，按 `DSH_WIN7_PWSH_SHA256` 校验后解压到 `runtime/pwsh`。`apps/desktop/src/win7-environment.ts`（新文件）的 `win7HostEnvironment()`：只在 Win7 上、而且 `resources/runtime/pwsh/pwsh.exe` 存在时，把这个目录加到 Host 环境的 PATH 前面；`main.ts` 启动 Host 时调用它。
- 4：`prepare-runtime.ts` 里，设置了 `DSH_WIN7_ELECTRON_ARCHIVE` 时用这个本地 zip，不调用 `downloadArtifact`。
- 5：`extract.h` 和 `window-frame.cpp` 已改，`/W4 /WX` 编译通过；x86 `window-frame.dll` 的 196 个导入在 Win7 上都存在（用 32 位 PowerShell 检查）。
- 另外还有前面的 Job 修复（`win32-process`）和 PythonVista（`prepare.ts`/`lock.json`）。

**完整打包要设的环境变量**（在 `deepseek-harness\` 下，另需 `apps/desktop/.env.windows`，更新策略地址还没定）：`DSH_PRIMARY_RUNTIME_NODE_ARCHIVE=out\node-v24.21.0-win-x64.zip`、`DSH_WIN7_RUNTIME_OVERLAY=out\win7-runtime-overlay`、`DSH_WIN7_PWSH_ARCHIVE=out\pwsh\PowerShell-7.2.24-win-x64.zip` + `DSH_WIN7_PWSH_SHA256=a1ccb6d8…`（完整值在同目录的 `.sha256` 文件里，和发布说明一致）、`DSH_WIN7_ELECTRON_ARCHIVE=<编好的 Electron zip>`。路径都相对本目录。

## Electron 44.2.0（Win7）编译

**2026-10-16 开始。** Electron v44.2.0 的 DEPS 锁定 Chromium **152.0.7977.76**，内置 Node v24.20.0。
- 源码在 `e\`（gclient 根目录，`e\src` 是 Chromium，`e\src\electron` 是 Electron）。路径尽量短，因为 Chromium 的目录很深。depot_tools 在 `depot_tools\`。构建环境统一由 `scripts\electron-env.cmd` 设置：depot_tools 和官方 Node 24 放在 PATH 最前面；`DEPOT_TOOLS_WIN_TOOLCHAIN=0`，用本机的 VS 2022；用 `GIT_CONFIG_COUNT/KEY/VALUE` 覆盖 `core.autocrlf=false`、`core.longpaths=true`、`core.filemode=false`，不改全局 git 配置（depot_tools 提示要改全局配置，没有授权）。
- 拉取：`scripts\electron-sync.cmd`（`gclient sync --revision src/electron@refs/tags/v44.2.0 --revision src@<sha> --revision src/third_party/electron_node@<sha> --no-history --shallow -j 8`），日志在 `out\electron-sync.log`。网络直连 chromium.googlesource.com 和 storage.googleapis.com 都正常。用 sha 钉住 `src` 和 `electron_node` 的原因见下面"第二次 sync"。
- 打 Win7 补丁：`scripts\apply-electron-win7-patches.ps1`，照补丁仓库 `chromium\apply_patches.bat` 的做法：按 `commit_hashes.txt` 从最后一行到第一行的顺序，依次 `git apply --ignore-space-change` 331 个 Chromium 补丁（其中 `rust01`/`rust02` 改的是 Chromium 自带 Rust 工具链里的 std 源码，最后打）；然后打 `electron\*.diff`（在 `src\electron`）、`third_party\electron_node\*`（在 `src\third_party\electron_node`），最后在 `src` 下打根目录的 `disable-redraw-lock.patch` 和 `RoOriginateLanguageException.diff`。补丁仓库自带的 `.bat` 写死了 `E:\electron\src` 路径，结尾还有 `pause`，所以没有直接用。**打完补丁后不要再运行 `gclient sync`**，否则会重置源码。
- 编译前置条件：VS 组件 `Microsoft.VisualStudio.Component.VC.ATLMFC`、Windows SDK 10.0.26100 的 "Debugging Tools for Windows"。**用户已在 2026-10-16 装好。**
- **第一次 sync 失败：** `cipd ensure` 下载 CIPD 包 `chromium/third_party/updater/chrome_win_x86`（Chrome 更新程序的测试二进制）时，被 Windows Defender 判为"病毒或可能不需要的软件"，解压失败，sync 中止。当时 `src`、`src\electron` 已经拉下来，占了约 30 GB。处理：不改 Defender 设置，改为在 `scripts\electron.gclient`（sync 脚本每次用它覆盖 `e\.gclient`）里用 `custom_deps` 把 DEPS 里全部 24 个 `src/third_party/updater/*/cipd` 设为 `None`，Electron 不编也不测这些。之后重新 sync 会接着上次的进度。第一次的日志在 `out\electron-sync.1.log`。另外看到对 `e\src` 运行的 `git fetch --dry-run` 进程，应该是 VS Code 的 git 插件，不是我们的。
- **VS Code 的 git 插件：** 它会扫描到 `e\src`、`e\src\electron`、`depot_tools`，然后自动 fetch Chromium 的完整历史。已在本目录 `.vscode\settings.json` 里让它不扫描、不监听、不搜索这些目录（见 CLAUDE.md）。用户重启 VS Code 后还剩 9 个孤儿 git 进程，经用户同意已结束。
- **第二次 sync 卡在 `src` 上（2026-10-16 22:22 开始）：** gclient 对 `e\src` 执行了 `git fetch --no-tags -- origin`（refspec 是 `+refs/heads/*`，没有 `--depth`），29 分钟后失败，又自动重试。原因：Electron 的 DEPS 用 tag 名钉 `src`（`152.0.7977.76`）和 `electron_node`（`v24.20.0`）。checkout 已经存在时，`gclient_scm.py` 的 `update()` 用 `IsValidRevision(..., sha_only=True)` 判断要不要 fetch，tag 名永远通不过这个检查，所以每次 sync 都会做一次完整 fetch。shallow 仓库没有可以衔接的历史，这样会把 main 的整段历史全拉下来（20 GB 以上）。本地 HEAD 其实早就是要的提交（`git ls-remote` 核对过：`152.0.7977.76` = `0d89dfa2…`，`v24.20.0^{}` = `71b8b174…`）。处理：停掉这轮 sync，在 `electron-sync.cmd` 里加 `--revision src@0d89dfa2… --revision src/third_party/electron_node@71b8b174…` 改用 sha，sha 已经在本地，就不会再 fetch。失败的那次 fetch 在 `e\src\.git\objects\pack\` 留下一个 17.44 GB 的 `tmp_pack_*`，确认没有进程在用后，经用户同意删掉了。这一轮的日志在 `out\electron-sync.prev.log`。**以后升级 Electron 版本时，要按新 DEPS 重新查这两个 sha。**
- **第三次 sync 卡在 PGO hook 上（2026-10-16 23:04）：** `electron_pgo_profiles_win` 运行 `download-profiles.py --targets win-x64,win-arm64`。x64 那份（376 MB）20 秒下完；arm64 那份的连接挂住了，32 分钟 0 字节。脚本按 1 MB 一块读，`recv` 超时 300 秒，只要偶尔来一点数据就不会超时。处理：用 curl 新开连接下载（18 秒），按 `win-arm64.pgo.txt` 里的 sha256 校验后放进 `src\electron\build\pgo_profiles\`，结束卡住的 hook（gclient 以退出码 2 结束），然后重跑 sync，这时脚本会认出本地文件，跳过下载。注意 gclient 先跑 Electron 的 hook，再跑 Chromium 的，所以 hook 失败后不能直接去打 Win7 补丁，要重跑 sync，把剩下的 Chromium hook（clang、Rust、gn 等）跑完。重跑时 Electron 的补丁会先撤回再重新打（gclient 把各仓库检出回 DEPS 的版本），所以要在打 Win7 补丁之前重跑。日志在 `out\electron-sync.3.log`。PGO 文件只有 official 构建才用。
- **sync 完成（2026-10-16 23:5x，第四次）：** 退出码 0，23 个 hook 全部跑完，日志 `out\electron-sync.log`。D 盘还剩 187.5 GB。之后 `git status` 显示 src 下 9 个子仓库的 gitlink 有改动（v8、skia、angle 等），那是 Electron 补丁在这些子仓库里提交造成的，正常。
- 资源：D 盘开始时剩约 221 GB，删掉临时包后剩 189.7 GB；本机内存 23 GB、页面文件 27 GB。Chromium 最后的链接很吃内存，official/ThinLTO 构建可能不够，要控制并发或用非 official 的 Release 配置。
- **编译：** `scripts\electron-build.cmd`，gn 参数在 `scripts\electron-release.gn`，脚本把它拷成 `e\src\out\Release\args.gn`，文件有变化时才重新 `gn gen`；然后 `autoninja -C out\Release -j %ELECTRON_JOBS% electron:electron_dist_zip`（默认 12 个本地任务，Chromium 152 默认用 Siso，autoninja 会把 `-j` 换成 `-local_jobs`）。产物 `out\Release\dist.zip` 的结构和官方 `electron-v44.2.0-win32-x64.zip` 相同，给 `DSH_WIN7_ELECTRON_ARCHIVE` 用。**参数的取舍：** 用非 official 的 Release（`import all.gn`，`is_official_build=false`，不开 DCHECK），不用 Electron 的 `release.gn`。official 会开 ThinLTO 和 PGO，用 23 GB 内存链接 electron.exe 很可能不够，而且以后为 Win7 问题改代码重编时，非 LTO 重新链接快得多。其余：`is_component_ffmpeg=true`（和官方包一样带 ffmpeg.dll）；`symbol_level=1`、`blink_symbol_level=0`（Win7 上崩溃时还能看到调用栈）；`concurrent_links=2`；`override_electron_version="44.2.0"`（不设的话，`electron/BUILD.gn` 要从 git 读版本，会去读 `electron\.git\packed-refs`，`--no-history` 检出没有这个文件，`gn gen` 直接报错）。`treat_warnings_as_errors=false` 不用自己设：Win7 补丁 `chore_drop_support_for_Windows_7__8__8.1_(#36427).diff` 已经加进了 Electron 的 `all.gn`。等能跑起来了，需要的话再用 official 编一次。不要设 `CHROMIUM_BUILDTOOLS_PATH`：设了 gn 会警告"highly unsupported"，不设也能找到 gn。实际 autoninja 选的是 ninja（`-j 12`），不是 Siso。
- **打补丁（2026-10-16 23:5x）：** `apply-electron-win7-patches.ps1` 打完 338 个（331 个 Chromium + 2 个 Electron + 3 个 Node + 2 个根目录），0 个失败，只有空白字符警告，日志 `out\electron-win7-patches.log`。
- **编译：** `gn gen` 生成 31965 个目标，用时 30 秒。23:54 开始 `electron-build.cmd`，共 46473 步，12 个 clang-cl 并行，日志 `out\electron-build.log`。
  - 第一次在第 2176 步失败（日志 `out\electron-build.1.log`）：Chromium 的 clang 插件报 `[chromium-rawptr] Use raw_ptr<T> instead of a raw pointer`，位置是 Win7 补丁恢复的 `base/synchronization/condition_variable.h:117` 的 `ConditionVarImpl *impl_;`。`build/config/clang/clang.gni` 里的 `enable_check_raw_ptr_fields` 和 `enable_check_raw_ref_fields` 只在非 official 构建里打开；补丁作者编的是 official，所以没遇到这个问题。处理：在 `electron-release.gn` 里把这两项设为 false，和 official 一致，生成的代码不受影响。其余插件检查在 official 构建里同样会跑，所以保留。2026-10-17 00:0x 重新开始编译。
  - 第二次在第 41147/45990 步失败（06:40，日志 `out\electron-build.2.log`）：链接 `node_mksnapshot.exe` 时找不到 `CertGetEnhancedKeyUsage`、`CertOpenStore`、`CertEnumCertificatesInStore`、`CertCloseStore`，都是 Electron 内置 Node 的 `src/crypto/crypto_context.cc` 直接调用的。`libnode` 在 Windows 上只链接 `psapi.lib`，上游是通过 `//base` 的 `onecore.lib`（OneCore 合集导入库，里面包含 crypt32 的函数）解析到的，而 Win7 补丁把 `onecore.lib` 从 base、gfx、gpu 里删了（它会引入 Win7 没有的 API 集）。`electron.exe` 不受影响，因为 net/crypto 显式链接了 `crypt32.lib`。补丁作者为什么能编过还不清楚，可能是 official 的 ThinLTO 把用不到的代码去掉了。修复：我们自己的补丁 `win7-fixes\electron\third_party\electron_node\libnode-link-crypt32.patch`，给 libnode 加上 `crypt32.lib`。`apply-electron-win7-patches.ps1` 已改为在补丁仓库的补丁之后再打 `win7-fixes\electron\<src 下的路径>\*.patch`。这次是手动 `git apply` 的，没有重跑整个脚本：补丁仓库里有些补丁先后改同一处，重跑时前面补丁的"已打过"反向检查可能不通过。06:4x 继续编译。
  - 第三次失败（07:28，日志 `out\electron-build.3.log`）：最后链接 `electron.exe` 时找不到 `tabs::IsVerticalTabsFeatureEnabled()`，引用来自 `chrome/browser/themes/browser_theme_pack.cc:339`（上游代码，没有条件编译）。`browser_theme_pack.cc` 在 Electron 的 `//electron/chromium_src:chrome` 里，这个目标是 static_library，而定义所在的 `//chrome/browser/ui/tabs:features` 不在 electron 的依赖图里。上游没有任何代码引用 BrowserThemePack，这个 obj 不会被链接进来。Win7 补丁 `chromium\85a8bf56….diff`（"win7dep: remove non aeroglass code"）让 `native_chrome_color_mixer_win.cc` 调用了 `BrowserThemePack::IsPersistentImageID()`，于是这个 obj 被拉进了链接。和 crypt32 的问题是同一类：补丁作者的 official ThinLTO 会把用不到的代码去掉，非 LTO 链接不会。修复：`win7-fixes\electron\electron\chromium_src-tabs-features-dep.patch`，给 `chromium_src:chrome` 加上 `//chrome/browser/ui/tabs:features` 依赖（这个 source_set 很小，只依赖 base 和本来就在链接里的 `ui_features`）。07:3x 继续编译。**之后如果还有类似的未定义符号，先按这个思路查：补丁新加的引用把 static_library 里原本不会被链接的 obj 拉了进来。**
- **编译完成（2026-10-17 07:38）。** `out\Release\dist.zip` 153.4 MB，73 个文件，结构和官方包相同（`electron.exe` 270 MB，比 official 版大；另有 ffmpeg.dll、d3dcompiler_47、dxcompiler/dxil、vk_swiftshader、vulkan-1、locales、resources）。拷到 `out\electron-v44.2.0-win32-x64.zip`，sha256 在同名 `.sha256` 文件里（`6cf6eb81…`），给 `DSH_WIN7_ELECTRON_ARCHIVE` 用。`electron.exe` 版本资源是 44.2.0。注意 `LICENSES.chromium.html` 只有 401 字节（非 official 构建没生成完整的许可证文件），要分发时需补上。编译后 D 盘剩 171 GB。
- **导入表（`out\electron-imports\`）：** `electron.exe` 静态导入只有 crypt32/kernel32/msimg32/ntdll/psapi/version/winmm/ws2_32，其余全是延迟加载。在 Win7 虚拟机里逐个解析：存在的 DLL 里没有缺函数（`!Characteristics` 是导出脚本的误报，`comctl32!#345` 是 v6 的 TaskDialogIndirect，靠清单加载）。Win7 没有的整个 DLL：`api-ms-win-core-winrt-l1-1-0`、`api-ms-win-core-winrt-string-l1-1-0`、`d3d12`、`dcomp`、`bluetoothapis`，都是延迟加载，要靠补丁在运行时避开。`dxil.dll` 静态依赖 UCRT（`api-ms-win-crt-*`），它只给 D3D12 用，Win7 上不会加载。没有导入 KB2533623 的函数。其余 DLL 全部 OK。
- **在 Win7 虚拟机里运行（解压在 `C:\dsh-test\electron\`）：** `electron.exe --version` 输出 v44.2.0。`ELECTRON_RUN_AS_NODE=1`（Host/CLI 的运行方式）：Node 24.20.0、V8 15.2.124.19，`win7-smoke.js` 21/21 通过（hostname、process.title、hrtime 等靠 libuv 补丁的项都正常）。图形界面：在 Session 1 里启动默认应用，窗口正常显示（Aero 边框，页面内容完整）。GPU 进程初始化失败，退回软件合成：ANGLE D3D11 报 "DXGI 1.2 required to present to HWNDs owned by another process"（Win7 SP1 默认是 DXGI 1.1），SwiftShader 也初始化失败。**2026-10-17 用户装了 KB2670838（平台更新）并重启**，dxgi/d3d11/d2d1/dwrite 都升到 6.2.9200.16492，这个报错消失了，但默认仍然是软件合成。原因是 Chromium 的 `gpu/config/software_rendering_list.json` 第 68 条 "Do not use GPU accelerated rendering with VMware on Windows"（厂商 0x15ad，禁用全部功能），任何 Windows 版本在 VMware 里都一样。加 `--ignore-gpu-blocklist` 打开 `chrome://gpu` 实测（脚本在 `out\vm-inspect\gpu2\`）：GPU 进程独立运行，`gl=egl-angle,angle=d3d11`，Skia GaneshGL，GL_RENDERER 为 `ANGLE (VMware, VMware SVGA 3D (0x00000405) Direct3D11 vs_5_0 ps_5_0, D3D11-9.17.6.5)`，合成、光栅化、WebGL、视频解码都启用了。结论：在 Win7 上，我们的 Electron 装了 KB2670838 后 D3D11 这条路是通的；在真机上有正常显卡驱动的话，应该默认就能开 GPU 加速（没在真机上试过）。注意 `getGPUInfo('basic')` 在还没开窗口时只会显示 `gl=none`，要开窗口让 GPU 进程真正初始化才准。`vmrun captureScreen` 截出来是黑屏（显示器被电源管理关掉了），要在 guest 里用 `shot.ps1`（先模拟鼠标移动唤醒，再 CopyFromScreen）截屏，脚本在 `out\electron-imports\`。

**下一步（2026-10-16 更新）：** 目标是 desktop。终端（winpty）、Office（兼容层）、pwsh 7.2、rg、libvips 都已定下方案并写好了接入代码（见上面"接入进度"）。剩下的：
1. ~~sync 结束后运行 `scripts\apply-electron-win7-patches.ps1`，然后 `scripts\electron-build.cmd`。~~ 2026-10-17 完成。
2. 用 `out\electron-v44.2.0-win32-x64.zip` 跑完整的 desktop 打包：`scripts\package-desktop-win7.ps1`（设好全部输入的环境变量后运行 `pnpm run package:desktop:win:x64:unsigned`，额外参数原样传过去，比如 `--check`），日志 `out\package-desktop.log`。**2026-10-17 用户决定：**
   - **不要自动更新。** 未签名构建本来就不带自动更新。强制更新检查没法关，`.env.windows` 用 `production` + `https://policy.invalid` + `'{}'`，检查永远失败，所以永远不会拦用户（见上面"主仓库关键事实"）。App ID 用 `local.dsh-win7.harness`，不和官方安装冲突。
   - **kit/sharp 钉到 0.1.5/0.35.5**（在 Win7 上测过的版本），ripgrep 也一起钉在 1.18.0。做法：`build-win7-overlay.ps1` 把参考目录里这 6 个包（`@vscode/ripgrep`、`@vscode/ripgrep-win32-x64`、`sharp`、`@img/sharp-win32-x64`、`@deepseek-ai/libreoffice-kit`、`@deepseek-ai/libreoffice-kit-win32-x64`）的版本写进 `manifest.json` 的 `pins`；`runtime-overlay.ts` 新增 `pinRuntimeOverlayVersions()`，`prepare-dsh.ts` 在 `runtime:lockfile` 之前执行 `runtime:win7-pins` 步骤，把这些版本合并进临时工程 `pnpm-workspace.yaml` 的 `overrides`（必须是精确版本，和已有 override 冲突就报错）。这样钉的版本一定和覆盖层一致。新增测试 `apps/desktop/tests/runtime-overlay.spec.ts`，6/6 通过（要在仓库根目录运行 vitest）。重建覆盖层后，只有 dshw7.dll/dshlo.dll 两个兼容层 DLL 变了（重新编译，链接时间戳不同），其余和测过的逐字节相同。
   - **electron 依赖钉到 44.2.0**（`apps/desktop/package.json` 原来是 `^44.0.0`，lockfile 解析为 44.0.0；"已做的决定"第 1 条）。`pnpm install` 后 lockfile 只改了 electron 那几行。
   - 改过的 TS 文件 oxlint 全部通过（`tsx scripts/run-oxlint.ts <文件>`），`tsc -b apps/desktop/tsconfig.host.json` 通过。`main.ts` 里之前接入 pwsh 那行超过 140 字符，已拆行。
   - **第一次完整打包（2026-10-17 09:13 开始）在 `prepare:dsh` 的 `runtime:smoke` 失败**（日志 `out\package-desktop.log`）。在这之前，`--check`、版本钉住（6 条 `win7 pin`）、覆盖层（8 项全部通过哈希检查）、Office 往返自检、primary-runtime 自检都通过了。失败原因：`runtime:smoke` 用我们的 `electron.exe --expose-internals tests/fixtures/runtime-payload-smoke.mjs` 运行打好的运行时，`node-addon-native-custom-loader` 调用 `node-addon-require-builtin@0.1.6` 的 `requireBuiltin('internal/modules/esm/loader')` 时报 "unsupported Electron runtime fingerprint: Node 24.20.0, V8 15.2.124.19-electron.0 (supported Electron versions: 43.0.0, 44.0.0, 44.7.0, 45.0.0-alpha.6)"。这个包是 DeepSeek 自己的（`github.com/deepseek-ai/dsh-node-addon-require-builtin`，"runtime probing for internal access"），被 `apps/cli`、`packages/boot/app-boot`、`vendor/loader`（可选 peer）依赖；npm 上已有 0.1.7（9/30）和 0.1.9（10/8）。DSH 在 Win7 上实际运行时多半也会撞上这个问题，正在查。
     - **查到的情况：** 打包时按 `^0.1.6` 实际装的是 0.1.9（`node-addon-require-builtin`、`-win32-x64-msvc`、`node-addon-native-custom-loader` 都是 0.1.9，`out\host-web` 里也是）。上游 clone 在 `dsh-node-addon-require-builtin\`（master `a58d359` = release 0.1.9，没有 tag 和 release）。原理：通过 `node::PrincipalRealm::builtin_module_require()` 拿到 Node 内部的 builtin require；Windows 上 getter 不导出时，扫描 Realm 的虚表找到它，从 getter 的机器码里解析出字段偏移，调用后和直接读字段的结果对比，再确认结果是函数。所谓"指纹"就是 `packages/native/src/runtime_context/runtime_profile.cc` 里的 `kElectronProfiles` 白名单，按 Node 版本 + V8 版本精确匹配。表里 4 项返回的配置完全一样（tagged，tag 0），只用来选调用约定，没有按版本写死的偏移。上游文档写的是"其他 Electron 版本在分析并加入 CI 之前一律拒绝"（fail closed），没有通用模式，也没有能覆盖指纹的环境变量。0.1.9 也不支持 44.2.0（它的 V8 15.2.124.19 在 44.0.0 的 .13 和 44.7.0 的 .28 之间）。纯 Node 按主版本选择，Node 24 支持，所以 Web 版在 Win7 上能用。
     - **2026-10-17：** 我准备在 clone 的 `win7` 分支里给 `kElectronProfiles` 加一项 44.2.0，然后从源码编 win32-x64 的 `.node`，用覆盖层替换，并钉住这 3 个包的版本。改到一半，被 Claude Code 自动模式的安全分类器以 "Security Weaken" 拦下（这张白名单是上游有意设的 fail-closed 机制）。改动已撤回，clone 和 0.1.9 一致。
     - **改用不碰这个模块的修法（2026-10-17）：** 查 DSH 的用法后发现，Desktop 的 Host、Electron 版 CLI、pnpm 本来就全都带 `--expose-internals` 启动（`host-process.ts:189-190`、`desktop-host/src/index.ts:34`、`cli.ts:19`、`scripts/node-bin/node*`、`cli/dsh*`；设计说明 `.agents/notes/implemented/architecture/2026-09-11-desktop-electron-node-runtime.md:19` 说加这个 flag 正是因为这个模块在 Electron 44 里找不到符号）。有这个 flag 时，普通 `require('internal/…')` 就能拿到同一份内置模块；`vendor/loader/src/internal.ts:108-118` 本来就是先这样，失败才用模块。只有 `packages/boot/app-boot/src/profile-resolution/resolver.ts` 的 `internalModules()` 无条件调用模块，在 44.2.0 上会让 Host 和 Electron 版 CLI 启动失败（`PluginPackages` 一定会挂载）；打包自检 `apps/desktop/tests/fixtures/runtime-payload-smoke.mjs:158-159` 也是这样。修复：两处都改成和 `vendor/loader` 一样，带 `--expose-internals` 时用普通 `require`，否则仍然用模块（自检里仍然检查模块能加载）。先在本机用我们的 `electron.exe`（`ELECTRON_RUN_AS_NODE=1 --expose-internals`）验证过：resolver 用到的 5 个 id 都能直接 `require`，它检查的函数都在，`internal/modules/cjs/loader` 的 `Module` 就是 `require('module')`。这样不用改模块的白名单，不用重编 `.node`，也不用钉这 3 个包的版本。验证：app-boot 的 `profile-resolution`、`profile`、`linked-resolution-matrix` 三个测试文件共 5059 个用例，通过 5058 个（约 20 分钟）。唯一失败的 "excludes profile symlinks to files from linked roots" 是测试准备环境时 `symlinkSync(..., 'file')` 报 EPERM（本机没开开发者模式，建不了文件符号链接），和改动无关。两个改动文件的 oxlint 都通过。2026-10-17 第二次完整打包，第一次的日志改名为 `out\package-desktop.1.log`。
   - **第二次完整打包成功（2026-10-17 09:57–10:10，共 789 秒）：** `prepare:dsh` 176 秒（`runtime:smoke` 通过），electron-builder 200 秒，`smoke-packaged-runtime --unsigned` 27 秒。最后的 asar 自检在本机 Win11 上通过：koffi、sharp、HTML 转换、pty、pnpm、grep、glob 全部为 true，`dsh web` 能启动，DOCX/XLSX/PPTX 转 PDF 和技能 CLI 发现都通过。产物 `apps\desktop\.desktop-build\targets\win-x64\unsigned-artifacts\deepseek-harness-0.2.0-rc.2-win-x64-unsigned.exe`（352.2 MB），拷了一份到 `out\deepseek-harness-0.2.0-rc.2-win7-x64-unsigned.exe`。
   - **Win7 虚拟机安装（进行中）：** 安装包拷到 `C:\dsh-test\dsh-setup.exe`，在 Session 1 里启动。欢迎页正常显示（自绘无边框窗口，"选择安装位置"和"立即安装"），没有报界面错误，说明 `window-frame.cpp` 的修复生效（虚拟机开着 Aero/DWM，DWM 关闭的情况还没测）。点"立即安装"要用户手动操作。**用户装完试用：没有报错，文件预览也正常（2026-10-17）。**
   - **"打开方式"应用列表超时（用户 2026-10-17 发现，已修，待重新打包验证）：** 文件预览工具栏的下拉菜单显示"无法获取应用列表"。实现在 `packages/util/native-command/src/file-applications-windows.ts`：把一段内嵌 C# 的脚本写成 `.ps1`，用 `powershell.exe -STA -File` 运行（`SHAssocEnumHandlers` 枚举处理程序，`IAssocHandler::Invoke` 打开）。Win7 上有三层问题，都已在虚拟机里复现并验证修复：
     1. `powershell.exe` 是 2.0：在 Node `execFile` 下（stdin 是管道），`-File` 运行后不退出，25 秒后被中止，这就是界面上的超时；而且脚本用了 `ConvertTo-Json`（3.0+）和 C# 3 语法。修复：新增 `windowsPowerShell()`（`native-command/src/windows-powershell.ts`，只看真实的 `process.platform` 和 `os.release()`，WSL 下不会误判），Win7 返回 `pwsh.exe`（Host 的 PATH 里随包的 pwsh 7.2 排在最前），Win8+ 照旧返回 `powershell.exe`。
     2. pwsh 7（.NET 6）下 `Add-Type` 只要显式传了 `-ReferencedAssemblies`，就会替换掉默认引用集（`$PSHOME\ref`），而且图像类型在 `System.Drawing.Common` 里。修复：PSEdition 为 Core 时，引用 `$PSHOME\ref\*.dll` 加 `System.Drawing.Common`。（注意：这段脚本放在 JS 模板字符串里，注释里不能出现 `\r` 之类的反斜杠转义，否则会被替换成控制字符。）
     3. Win7 的 Shell 处理程序枚举对象，扛不住 .NET 给 COM 对象建包装器（RCW）时额外做的 QueryInterface：.NET Framework（PS 2.0）下报 E_FAIL，.NET 6 下访问冲突。直接取原始指针时，`SHAssocEnumHandlers` 返回 S_OK，QI 也正常（`out\vm-inspect\assoc\diag5`）。修复：C# 不再用 `[ComImport]` 接口，改为按虚表顺序直接调用（IEnumAssocHandlers::Next、IAssocHandler 的 GetName/GetUIName/GetIconLocation/Invoke、IShellItem::BindToHandler），自己管理 Release 和 CoTaskMemFree。
     4. 打开成功后，Win7 的 Shell 要等被打开的程序退出才释放 `SHSetInstanceExplorer` 的引用，`WithShellLifetime` 会一直等下去（实测 90 秒都没释放）。修复：只在系统版本低于 6.2 时把这段等待限制在 3 秒（期间照常处理消息），Win8+ 不变。
     - 结果：Win7 上用 pwsh 7.2 列出 `.txt` 的 8 个处理程序（带图标、默认标记），约 1 秒；用记事本打开约 4.4 秒，退出码 0。Win11 上 PowerShell 5.1 和 pwsh 7.2 都能正常列出；`file-applications-windows.spec.ts` 端到端测试（注册关联、列出、打开）把超时放宽到 60 秒后通过。它默认的 5 秒上限在本机上不够，原版代码同样超时（约 6 秒）。
     - 同类问题一起修了（Win7 上都会调用 Windows PowerShell 2.0）：`open-in-app` 的图标提取（`icons.ts`）、工作区默认目录（`workspace-controller/src/default-directory.ts`，用了 `::new()`）改用 `windowsPowerShell()`；"管理 dsh 命令"（`apps/desktop/src/command-manager-entry.ts`，`command-path.ps1` 要 PS 5）在 Win7 上改用 `resources\runtime\pwsh\pwsh.exe`。终端和 agent 的命令本来就优先用 pwsh，不受影响。
     - 2026-10-17 12:23 重新打包成功（日志 `out\package-desktop.log`，上一次的在 `.2.log`），新安装包已拷到 `out\` 和虚拟机 `C:\dsh-test\dsh-setup.exe`，等用户覆盖安装后验证。
     - 验证：native-command、open-in-app、workspace-controller 的 default-directory、desktop 的 command-path 测试 165 个通过（端到端那个在默认超时下失败，原因同上）；新增 `windows-powershell.spec.ts`；oxlint 和 4 个 `tsc -b` 都通过。诊断脚本都在 `out\vm-inspect\assoc\`。
   - **安装依赖（2026-10-17 核对）：** 测试用的虚拟机是 Win7 旗舰版 SP1 x64，补丁有 KB976902（SP1）、KB2533623、KB2534111、KB2999226（UCRT）、KB4474419（SHA-2），另有 VMware Tools 13.0.1 顺带装的 VC++ 2015–2022 运行库 14.40.33816（x64 和 x86），.NET Framework 只有 3.5。对安装后的 `win-unpacked` 里 1021 个 PE 文件跑了 `dumpbin /dependents` 和 `/imports`：
     - 静态 CRT、只依赖系统自带 DLL 的：electron.exe、primary-runtime 的 node.exe、rg.exe、winpty、koffi 等原生模块、dshw7/dshlo。
     - pwsh 7.2 是 .NET 6 自包含版，UCRT（`api-ms-win-crt-*`）全部随包附带，不依赖系统。
     - **依赖系统 UCRT（KB2999226 / KB3118401）的：** Python（`python.exe`、`python312.dll`、`DLLs\*.dll`，numpy/pandas 自带的 msvcp140）、sharp 的 `libvips-42.dll`（看图）、`libreoffice-kit.exe`。
     - **依赖 VC++ 2015–2022 运行库的：** `libreoffice-kit.exe`（`msvcp140*`、`vcruntime140*`，没有随包附带）。Python 自带 `vcruntime140`。
     - **静态导入 KB2533623 函数的：** `python312.dll`（`AddDllDirectory`、`RemoveDllDirectory`）、`libreoffice-kit.exe`（`AddDllDirectory`、`SetDefaultDllDirectories`；它的 kernel32 导入已改到 dshlo.dll，再转发回 kernel32，所以照样需要这个补丁）。没有这个补丁，这两个程序都启动不了。
     - 用不到的：conpty/OpenConsole（Win7 上用 winpty）、`dxil.dll`（D3D12）、reflink（加载失败会自动退回）。
     - 结论（2026-10-17 修订）：要用全部功能，需要 Win7 SP1 x64 + KB2533623（或 KB3063858）+ **KB4474419**（node.exe 要用其中的 `advapi32!EventSetInformation`，见下）+ VC++ 2015–2022 x64 运行库（它的安装包在 Win7 上会顺带装上 UCRT；也可以单独装 KB2999226）。原先写的"KB4474419 用不到"是错的：当时的导入检查是在已经装了它的旧虚拟机上做的。
   - **新的离线 Win7 上 kit 命令"退出码 1、无输出"（2026-10-17）：** 用户在全新离线 Win7 SP1（只装了 KB2533623 和 VC++ 14.44）上看到 agent 调用 LibreOffice Kit 命令行（`node.exe cli.js …`，连 `capabilities --json` 也是）退出码 1、没有任何输出。kit 出错时一定会往 stderr 写 JSON，所以是 node.exe 根本没启动起来；pwsh 在被调用的程序失败时返回 1。旧虚拟机上同样的 5 组对照（直接运行、沙箱跑 Python、沙箱跑 node、沙箱跑 kit、沙箱里 pwsh 再调 node 和 kit，脚本 `out\vm-inspect\kit\repro.cmd`）全部正常。**根因：我们编的 node.exe 静态导入了 `advapi32!EventSetInformation`**，来自 V8 系统跟踪的 `deps/v8/src/libplatform/tracing/recorder-win.cc`（TraceLogging；按 Win10 的 `WINVER` 编译时 SDK 的 `TraceLoggingProvider.h` 会直接调用它）。这个函数 Win8 才有，Win7 要装了 KB4474419 才有：旧虚拟机的 advapi32 是 6.1.7601.24384（2019-02，来自 KB4474419），原版 SP1 的是 6.1.7600.16385。之前在旧虚拟机上做导入检查，所以没发现。
     - **新工具 `scripts\check-win7-rtm-imports.ps1 -Root <目录>`：** 用原版 SP1 安装镜像（用户的 `D:\Downloads\cn_windows_7_ultimate_with_sp1_x64_dvd_u_677408.iso` → `out\win7-sp1-rtm\install.wim`，第 4 个映像）里的系统 DLL，核对目录下每个 PE 文件的静态导入。基准是原版 SP1 + KB2533623 + VC++/UCRT：x64 文件对 System32，x86 文件对 SysWOW64，System32 里找不到的再到 WinSxS 里找（GdiPlus.dll 只在 WinSxS 里，加载器照样能按名字找到）。安装包里任何位置自带的 DLL（比如 wheel 的 `*.libs`）都视为随包提供，UCRT/VC/Python 自己的 DLL 不查。对 win-unpacked 的 1035 个 PE 文件跑出来的结果：node.exe 缺 `EventSetInformation`；sherpa-onnx 的 `onnxruntime.dll` 缺 `CreateFile2`、`GetProcessMitigationPolicy`、`GetSystemTimePreciseAsFileTime`、`EventSetInformation`、`CreateDXGIFactory2`（Win8+，没有补丁能补，语音相关功能在 Win7 上用不了）；node-pty 的 conpty/OpenConsole（Win7 上不用）；reflink（失败后自动退回）。**以后每次出新包都要用它查一遍。**
     - **用户决定（2026-10-17）：把 KB4474419 列为必装项，node 不重编。** 曾试过的修法（已撤回）：node 的 `tools/v8_gypfiles/v8.gyp` 在 `v8_enable_system_instrumentation==1 and is_win` 这一段加上 `defines: ['TLG_HAVE_EVENT_SET_INFORMATION=2']`。SDK 的 `TraceLoggingProvider.h` 说明：设为 2 时改用 GetProcAddress 运行时查找，找不到就返回 NOT_SUPPORTED。Electron-for-windows-7 对 Chromium 的 TlmProvider 也是这么做的（`chromium\88c26c39….diff`）。重编刚开始就停了，`v8.gyp` 已 `git checkout`，node 仓库干净，`out\node-v24.21.0-win-x64.zip` 没变（sha256 `3309fc64…`）。以后如果要去掉这个必装项，照这个修法做。
     - **检查工具的基准加上了 KB4474419**：`-Updates` 默认是 `out\win7-sp1-rtm\updates\KB4474419\{System32,SysWOW64}`。这个补丁的 cab 是新格式（`_manifest_.cix.xml` 索引，载荷是 PA30 增量），没法直接解出 DLL，所以按 cix 列出的 236 个文件（系统 DLL 有 130 个 amd64、106 个 wow64/x86），从旧虚拟机里拷出版本号和补丁组件一致的 94 个 DLL（advapi32、kernel32、kernelbase、ntdll、crypt32、bcrypt 等；`api-ms-win-core-*-l1-1-0` 这批转发桩和没装的 provider 不在其中）。用新基准复查 win-unpacked：node.exe、libreoffice-kit.exe 都通过；只剩 conpty/OpenConsole（Win7 不用）、reflink（自动退回）、sherpa-onnx 的 onnxruntime.dll（`CreateFile2`、`GetProcessMitigationPolicy`、`GetSystemTimePreciseAsFileTime`、`CreateDXGIFactory2`，属于实验性的"语音输入" `packages/experimental/speech-to-text-sensevoice`，当时判断在 Win7 上用不了；后来用 dsho.dll 修好了，见下面"语音输入"）。
     - **离线包：** `安装说明.txt` 里 KB4474419 改为必需（写明原因、调整了顺序和检查命令），补了语音输入不可用、新机器上的测试情况和"已按原版 SP1 + KB4474419 核对"。重新生成的 ISO 是 `out\win7-offline-kit-v2.iso`：旧的 `win7-offline-kit.iso` 正挂在新虚拟机的光驱上，被占用，覆盖不了。
    - **语音输入（2026-10-17）：** 插件管理里的 Voice Input（`packages/experimental/voice-input-bundle`，默认关闭）。Host 用 Electron 的 Node 模式起一个 worker，加载 `sherpa-onnx-node`，在 CPU 上跑 SenseVoiceSmall int8 和 Silero VAD；渲染进程负责录音。
      - **问题：** sherpa-onnx-win-x64 里只有 `onnxruntime.dll`（ORT 1.28.2，静态 CRT）有问题，它静态导入了 6 个 Win8+ 函数。检查工具之前漏报了其中的 `api-ms-win-core-path-l1-1-0.dll`，原因是自带的 Python 目录里有一份同名 DLL，就被当成"随包提供"了。实际上那份不在 onnxruntime.dll 的搜索路径上。
      - **在 ORT 源码里的用法**（`patches/onnxruntime`，v1.28.2，只做了 `core/platform` 等目录的稀疏检出）：
        - `CreateFile2`：`env.cc` 读模型时用。
        - `PathCchRemoveBackslash`、`PathCchRemoveFileSpec`：`path_lib.cc` 取目录名。
        - `GetSystemTimePreciseAsFileTime`：`env_time.cc`。
        - `GetProcessMitigationPolicy`、`CreateDXGIFactory2`：`device_discovery.cc` 枚举硬件时用，失败了就跳过 GPU，打印一行 `Failed to create DXGI factory.`。
        - 其余新 API（`dxcore.dll`、`SetThreadDescription`）都是动态获取的。
      - **修法：** `shim/dsho.c` 兼容层。名字只能 4 个字符，因为它要顶替 `dxgi.dll` 这个导入名。
        - onnxruntime.dll 的 kernel32、dxgi、api-ms-win-core-path 三项导入都改指向 dsho.dll，其余 162 个 kernel32 函数原样转发。
        - 6 个函数在有原版 API 时直接调原版。Win7 上的退路：
          - `CreateFile2` 改调 `CreateFileW`。
          - `GetProcessMitigationPolicy` 一律返回"未启用"，只有 DEP 报"已启用"。
          - `CreateDXGIFactory2` 改调 `CreateDXGIFactory1`，ORT 要的是 IDXGIFactory6，所以会得到 E_NOINTERFACE。
          - `PathCch*` 自己实现。
        - `build-win7-overlay.ps1` 新增 2 项，`pins` 加了 `sherpa-onnx-node`、`sherpa-onnx-win-x64` 1.13.8。
      - **验证：**
        - `check-win7-rtm-imports.ps1` 检查结果为 0 个缺失。
        - `scripts\win7-voice-test.js` 照 `inference.ts` 的默认配置建识别器和 VAD，转写模型仓库自带的 `test_wavs\zh.wav`、`en.wav`：
          - 本机 Win11 + 官方 Node：全部通过。
          - 旧虚拟机里原版 onnxruntime.dll：加载失败。
          - 补丁版：用 DSH 的 Electron 44.2.0（Node 模式）和 Win7 版 node 都全部通过，中英文结果和本机一致。
          - 虚拟机里创建识别器约 25 秒，本机 1.8 秒（虚拟机只有 2 个 vCPU）。worker 启动受 `prepareTimeoutMs`（1 小时）约束，所以没问题。
      - **模型：** `runtime/assets.json` 固定了版本、大小和 sha256。
        - 默认从 huggingface.co / hf-mirror.com 下载到 `%USERPROFILE%\.dsh\speech-to-text\sensevoice\models\`：`sensevoice-onnx\model.int8.onnx`（228 MB）、`sensevoice-onnx\tokens.txt`、`silero\silero_vad.onnx`。
        - 离线时手动放到这个位置即可，文件完整就不会再提示下载。
        - 本机已下载到 `out\sensevoice-models\`（含两个测试音频）。
      - **检查工具修正：** `check-win7-rtm-imports.ps1` 现在只把三处的 DLL 算作随包提供：导入方所在目录、`-Root` 的顶层目录（应用目录）、任意 `*.libs` 目录。用新规则复查新包的 win-unpacked（1036 个 PE 文件），只剩 conpty/OpenConsole（Win7 不用）和 reflink（自动退回），没有新问题。
      - **打包（2026-10-17 15:49）：** 日志在 `out\package-desktop-win7.log`。
        - 安装包 `out\deepseek-harness-0.2.0-rc.2-win7-x64-unsigned.exe`，sha256 `cbf5e8a8…`（另有 `.sha256` 文件）。包里 sherpa-onnx 目录下的两个文件和覆盖层一致。
        - 已拷到离线包和旧虚拟机的 `C:\dsh-test\dsh-setup.exe`。旧虚拟机已按离线说明把模型放到 `C:\Users\test\.dsh\speech-to-text\sensevoice\models\`。
        - **待用户验证：** 覆盖安装后启用"语音输入"，应当不提示下载；然后用麦克风录音。两台虚拟机都有 HD Audio 声卡，会自动连接主机的默认设备。
      - **离线包：**
        - 加了 `voice-models\`（目录结构和 DSH 的模型目录一样）。
        - `安装说明.txt` 新增第七节：放模型的 xcopy 命令、文件大小、下载地址，以及启用和使用步骤。原来的"语音输入在 Win7 上无法使用"已删掉，SHA-256 已更新。
        - 新 ISO 是 `out\win7-offline-kit-v3.iso`（707 MB）。`make-iso.ps1` 加了 `FreeMediaBlocks = 0`，因为 IMAPI2 默认按 650 MB 的 CD 限制大小。
    - **从安装程序结束页启动后，命令报 `AssignProcessToJobObject failed (Win32 5)`（2026-10-17）：** 先在离线虚拟机上出现，覆盖安装后的旧虚拟机也出现。agent 的每条命令都失败。
      - **根因：**
        - 按用户安装时，结束页的"运行"是用 NSIS 的 `Exec` 直接启动应用（`apps/desktop/installer/pages.nsh:237`），DSH 就成了安装程序的子进程。
        - Win7 的程序兼容性助手把安装程序整棵进程树放在一个 Job 里，限制标志只有 `BREAKAWAY_OK`（0x800），没有 `SILENT_BREAKAWAY_OK`。
        - Host 和 runner 都继承了这个 Job。runner 用 `spawnCurrentTokenJobProcess` 创建命令进程时没加脱离标志，命令进程也在里面。Win7 不支持嵌套 Job，所以把它分配到自己的 Job 时被拒绝。
        - 从开始菜单启动时，主进程所在的 Job 带静默脱离，子进程不在任何 Job 里，所以一直正常。
        - libuv 在同样情况下会吞掉这个错误，不影响 Host 和 runner 的启动。
      - **怎么查的：** 外部进程拿不到别人的 Job 句柄，所以用 `PROC_THREAD_ATTRIBUTE_PARENT_PROCESS` 以目标进程为父进程启动探测进程，让它继承同一个 Job，再由它用 `QueryInformationJobObject(NULL, …)` 查限制标志和成员。
        - 脚本在 `scripts\win7-job-probe\`（`own-job.ps1`、`parent-spawn.ps1`、`job-detail.ps1/.cmd`），拷到 guest 的 `C:\dsh-test\` 下运行，结果写到 `C:\dsh-test\job-detail.txt`。
        - 要用 `runProgramInGuest -interactive` 运行，否则在 Session 0 创建的控制台子进程会以 0xC0000142 失败。
        - 结果：开始菜单启动的 DSH，主进程的子进程不在 Job 里；结束页启动的 DSH，整棵树都在同一个 0x800 Job 里；从这个 Job 里加 `CREATE_BREAKAWAY_FROM_JOB` 创建的子进程不在任何 Job 里。
      - **修法（主仓库 `win32-process`，未提交）：** `process.ts` 新增 `createOutsideCreatorJob`。
        - Win7 上两条创建路径都先带 `CREATE_BREAKAWAY_FROM_JOB` 创建（当前令牌的 `CreateProcessW` 和受限令牌的 `CreateProcessAsUserW`）。
        - 外层 Job 不允许脱离、返回 `ERROR_ACCESS_DENIED` 时，去掉这个标志再创建一次。
        - 原先只有受限令牌那条固定带这个标志，没有退路。
        - `abi.ts` 加了 `ERROR_ACCESS_DENIED`。
        - 新测试 `tests/win7-jobs.spec.ts` 模拟 NT 6.1 加载模块，4 个用例。
      - **验证：**
        - win32-process 的 63 个测试全部通过，oxlint 和 `tsc -b` 也通过。
        - 用户开了开发者模式后，win32-process、subprocess-local、sandbox-windows-acl、app-boot 一起跑：6007 个通过。
        - 之前因为建不了符号链接（EPERM）失败的用例都过了。
        - 唯一的失败是 `native-windows.spec.ts` 里的一个用例：它超过了 5 秒的默认时限，当时打包在同时运行，机器负载很高。单独跑连续 3 次都通过。
        - `native-windows.spec.ts` 要先清掉 `NoDefaultCurrentDirectoryInExePath` 才能通过：Claude Code 的 shell 设置了它，改变了相对路径的搜索规则。
      - **临时绕过：** 关掉 DSH，从开始菜单重新打开。用户随后从结束页启动新包验证，问题已解决（2026-10-17）。
    - **发布到 GitHub（2026-10-17）：** 用户决定的结构如下。仓库结构、版本对应和移植步骤写在 `docs/porting.md`。
      - **DSH 源码改动：**
        - 放在公开 fork `factfinding/deepseek-harness`。
        - 分支 `dsh-v0.2.0-rc.2-win7` 上按主题拆成 8 个提交：
          - primary-runtime
          - win32-process 的 Job
          - winpty
          - 打开方式和 pwsh
          - desktop 的 Electron 和 pwsh
          - 运行时覆盖层
          - app-boot 的 internals
          - 安装程序
        - tag `dsh-v0.2.0-rc.2-win7.1`。
      - **其余部分：** 放在新的公开仓库 `factfinding/dsh-win7`，就是本目录。
        - `.gitignore` 是白名单。
        - `deepseek-harness` 作为子模块。
        - node 的 7 个提交导出到 `win7-fixes/node/v24.21.0/`。
        - 新写了 README（安装要求、离线安装、语音模型、已知限制）、`docs/porting.md`、MIT 许可证。
        - 许可证署名写的是"dsh-win7 contributors"。
      - **Release：** 只上传安装包。Windows 更新、VC++ 运行库和语音模型不再分发，README 里写了官方下载地址和测试用文件的 SHA-256。
      - **注意：** Electron-for-windows-7 补丁仓库没有 LICENSE 文件。README 里注明了出处，node 补丁的提交信息里也写了来源。
      - **打包（2026-10-17 17:35）：**
        - 安装包 sha256 `49813472…`。已确认 app.asar 里的 `dsh-win32-process/lib/index.js` 含 `createOutsideCreatorJob`。
        - 已拷到 `out\`、离线包（说明里的 SHA-256 已更新）和旧虚拟机的 `C:\dsh-test\dsh-setup.exe`。新 ISO 是 `out\win7-offline-kit-v4.iso`。
        - **待用户验证：** 覆盖安装，从结束页启动，然后让 agent 运行命令。
   - **（已撤销）自带 Python 加装 matplotlib：** 2026-10-17 用户先要求加，随后发现问题不是缺 matplotlib，要求恢复。所有改动都已撤回：lock.json、prepare.ts、prepare.spec.ts 只剩之前的 Win7 改动；smoke.py、工具说明、快照、文档、README 已经 `git checkout`。那一轮打包中途停掉，没有产出安装包，`out\` 里的安装包仍是 12:23 那一版（sha256 `f933bcb6…`，和离线包里的一样）。下面的记录留着，以后要加包时可以参考。原始记录： 用自带 Python 的 pip 执行 `install --dry-run --report --only-binary=:all: --platform … --target`，按 5 个平台分别解析 `matplotlib`，同时把 numpy 2.3.5、pillow 12.3.0、python-dateutil、six 固定在原版本（报告在 `out\mpl-resolve\`）。新增 matplotlib 3.11.2、contourpy 1.4.0、fonttools 4.67.0、kiwisolver 1.5.1（各平台二进制 wheel，写进 `targets.<平台>.wheels`），以及 cycler 0.12.1、packaging 26.3、pyparsing 3.3.3（纯 Python，写进共用的 `wheels`），7 个都登记进 `pythonPackages`。`prepare.spec.ts` 要求每个平台的 wheel 和 `pythonPackages` 一一对应，所以 5 个平台都要配齐。Win7 兼容性：Windows 版 16 个 .pyd 的导入只有 UCRT、`vcruntime140/_1`（Python 自带）、python312 和系统 DLL；kernel32 的 42 个函数都是 Vista/Win7 就有的，user32/shell32/ole32/psapi 的也都有（`SetCurrentProcessExplicitAppUserModelID` 是 Win7 引入的）。comctl32 的序号 410/412/413（窗口子类化相关）只有 `_tkagg` 用，而自带 Python 没有 Tk。其他改动：
     - `prepare.ts` 的 `unpackPrimaryRuntimeWheel` 原本只允许 `.data/scripts`，fonttools 带一个 `.data/data/share/man/man1/ttx.1`。现在额外放行 `.data/data/share/man/`（文档，原样留在 `.data` 下），其他 data 路径照旧拒绝，并加了测试。
     - 中文图表：matplotlib 只在 `font.family` 显式列出多个字体时才逐字回退，而且读默认模板时连注释行也当默认值读，所以追加一行会被判为重复定义。做法：只在 win-x64 上，把 `mpl-data/matplotlibrc` 里注释掉的 `#font.family:` 那一行原地替换成 `font.family: DejaVu Sans, Microsoft YaHei, SimHei`（找不到恰好一行就报错）。效果：英文照旧用 DejaVu，中文用雅黑（示例图 `out\mpl-resolve\sample-chart.png`）。因为组装改变了产物内容，`primaryRuntimePayloadDigest` 的 `format` 从 4 升到 5，已安装用户的运行时副本会重新复制，用户自己加装的包会被清掉。
     - `smoke.py`：设置 `MPLCONFIGDIR` 到临时目录，用 Agg 画图并检查 PNG 尺寸；Windows 上标题带中文，要求没有 "missing from font" 警告。
     - `load_workspace_dependencies` 的说明加上 matplotlib，同步改了快照 `snapshots/session/workspace-dependencies/tool-schemas.expected.json`、`scripts/snapshots/python-sdk-single-exe/authoring/model-visible.json`、`docs/tool-catalog(.zh).md`、`apps/desktop/README(.zh).md`。
     - 验证：本机 `prepare:primary-runtime --target win-x64` 加自检通过；prepare.spec、tool-workspace-dependencies、primary-runtime-preparation 共 90 个测试通过；oxlint 通过。Win7 上还要用户装上新包后实测 import 和画图。
   - **离线安装包（2026-10-17）：** 用户要在一台全新、无网络、无 VMware Tools 的 Win7 SP1 上测试。目录 `out\win7-offline-kit\`，做成了 `out\win7-offline-kit.iso`（444.5 MB，`scripts\make-iso.ps1`，用户挂到光驱）。内容：DSH 安装包、`Windows6.1-KB2533623-x64.msu`（必需）、`Windows6.1-KB4474419-v3-x64.msu`（建议，为了 Joliet 64 字符的限制改了名）、`vc_redist.x64.exe`（必需）、`Windows6.1-KB2999226-x64.msu`（备用）、`Windows6.1-KB2670838-x64.msu`（可选），以及 `安装说明.txt`（UTF-8 带 BOM、CRLF，里面有安装顺序、检查命令、功能检查清单和 SHA-256）。所有微软包的签名都有效。
     - **VC++ 运行库的选择：** 微软的 `aka.ms/vc14/vc_redist.x64.exe` 现在给的是 VS 2026 那一代，Learn 页面写明只支持 Win10/11 和 Server 2016 以上，不能用。`aka.ms/vs/17/release/vc_redist.x64.exe` 给的是 14.44.35211（"2015-2022" 系列的最后一版，微软签名，sha256 `cc0ff0eb…`），放进了离线包。测过的是 14.40.33816（VMware Tools 13.0.1 顺带装的；VMware Tools 的 `windows.iso` 里的 setup.exe 拆不出单独的 vc_redist）。旧的测试虚拟机 `C:\ProgramData\Package Cache` 里应该有 14.40 的安装包，必要时可以拿来对照。14.44 的安装包里嵌着 8 个 KB2999226 包（Vista/7/8/8.1 的 x86/x64，用 7-Zip 解开 23.8 MB 那个 cab 容器可以看到），所以在 Win7 上会自动安装 UCRT；离线包里的 `Windows6.1-KB2999226-x64.msu` 就是从里面提出来的。
     - 新虚拟机没有 VMware Tools，`vmrun` 的 guest 操作（拷文件、运行程序、截屏）都用不了，只能靠用户操作和挂 ISO。
3. 在 Win7 虚拟机里测试安装程序和 desktop。
4. 问过用户后，提交主仓库的改动（先不推送）。

1. **整理补丁。** `git clone https://github.com/e3kskoy7wqk/Electron-for-windows-7 patches/Electron-for-windows-7`，列出 `v44.2.0/third_party/electron_node/` 下的**完整**文件清单。网页上只看到部分文件，已知有这三个：
   - `FR_add_real-time_clock_version_of_uv_hrtime()_#1674.diff`
   - `fix_crash_caused_by_gethostnamew_on_windows_7.patch`
   - `fix_crash_uv_get_process_title_on_windows_7.diff`

   从文件名看都是 libuv（`deps/uv`）的修改，需要逐个审阅。补丁是第三方代码，先读懂再应用。`v44.2.0/` 根目录还有 `RoOriginateLanguageException.diff` 和 `disable-redraw-lock.patch`，看起来属于 Chromium/Electron，与 Node 无关，需要确认。
2. **参考已有构建。** 已 clone 到 `patches/`。[DeftKing/nodejs-win7](https://github.com/DeftKing/nodejs-win7) 只有编好的 Node 22.23.x 二进制（`.7z`/`.msi`，走 Git LFS），没有构建脚本和补丁，只能拿来对照导入表。[vladimir-andreevich/node.js-windows-7](https://github.com/vladimir-andreevich/node.js-windows-7) 是改好的 v20.19.2 完整源码，但删掉了大量文件，直接和上游 diff 噪音太大，用户决定不走这条路，以 Electron-for-windows-7 的补丁为主。
3. **获取源码。（2026-10-16 已完成：`node/` 在 `v24.21.0` = `955266bf`，libuv 1.52.1，工作区约 720 MB，其中 `.git` 111 MB，LF 换行已确认。）** `git -c core.autocrlf=false -c core.longpaths=true clone --depth 1 --branch v24.21.0 --config core.autocrlf=false --config core.longpaths=true https://github.com/nodejs/node node`。本机 system 级配置是 `core.autocrlf=true`，不关掉的话文件会被转成 CRLF，LF 格式的补丁就打不上；`longpaths` 用来应付 `deps/` 下的深层路径。本目录里其他第三方 clone 也照此处理。Electron 的 `third_party/electron_node` 和上游 Node 目录结构相同，补丁预计可以直接 `git apply`，路径可能需要调整。
4. **编译。** 用 `vcbuild.bat release x64`。已核实（`node/BUILDING.md`）：Node 24 起必须用 ClangCL，需要 VS 组件 `Microsoft.VisualStudio.Component.VC.Llvm.Clang` 和 `Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset`，另需 NASM。本机现状：VS Community 2022 17.14、Windows SDK 10.0.26100、Python 3.14.6（configure 支持 3.9–3.14）已有。NASM 3.02 已装在 `%LOCALAPPDATA%\bin\NASM\nasm.exe`（用户级 winget 安装，不一定在 PATH 里，编译前需确认）。ClangCL 组件已装好（clang 19.1.5）。本机 16 个逻辑 CPU、23 GB 内存。2026-10-16 已开始编译（`scripts/build-node.cmd`，日志在 `out/build-node.log`，第一次中断前的日志在 `out/build-node.1.log`），configure 通过，ICU、OpenSSL 已编完。vcbuild 默认只用 `/m:2` 加 `/MP`，但 clang-cl 不支持 `/MP`，实际只有 2 到 3 个文件同时编译。脚本里已改为通过 MultiToolTask 并行（`CL_MPCount=12`），现在同时有 13 到 16 个 clang-cl。
5. **打包。** 按 nodejs.org 的 `node-v24.21.0-win-x64.zip` 的目录结构打成 zip，输出到 `out/`，并计算 sha256。动手前先读 `prepare.ts` 第 93 行附近的解压逻辑，确认它需要的目录结构。
6. **修改主仓库。** 让 `prepare.ts` 的 win-x64 目标能读取本地压缩包，例如通过环境变量指定路径，同时更新 `lock.json` 的哈希。三个调用方不需要改。
7. **在 Win7 上测试**（需要 Win7 x64 SP1 实机或虚拟机）。基本检查：`node -v`、`os.hostname()`、`process.title`、`process.hrtime.bigint()`、`fs`、`child_process`、`worker_threads`、`crypto`。再用内置 pnpm 装一个带原生预编译包的 npm 包。

## 建议的目录结构

```
dsh-win7/
  HANDOFF.md
  patches/Electron-for-windows-7/   第三方补丁（clone）
  node/                             nodejs/node v24.21.0 源码
  scripts/                          自己写的构建脚本（不要放进第三方源码目录）
  out/                              node zip、sha256、构建日志
  deepseek-harness/                 主仓库的独立 clone（不是 worktree，不依赖 D:\Documents\2026\deepseek-harness）
```

## 待用户决定的问题

1. ~~主仓库的改动放在哪里~~：已定，clone 到本目录 `deepseek-harness/`（2026-10-16）。
2. ~~Win7 测试环境~~：已定，用本机 VMware Workstation 25 里的 Win7 SP1 x64 虚拟机（2026-10-16）。`D:\Documents\Virtual Machines\Windows 7 x64\Windows 7 x64.vmx`，2 vCPU / 4 GB，NAT 网络，DHCP 地址 192.168.45.129。计划用 `C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe` 的 guest 操作（拷文件、运行程序）来测试，前提是虚拟机里装好 VMware Tools 并提供一个有密码的账号。2026-10-16 用户已在虚拟机里装好 KB4474419 和 VMware Tools（13.0.1），`vmrun` 的 guest 操作已验证可用。guest 账号是 `test`，是管理员，以 High 完整性级别运行；密码由用户在对话中提供，不写进文件，新对话需要再问用户。虚拟机系统为 Win7 旗舰版 SP1 6.1.7601（中文），已装补丁：KB976902、KB2534111、KB2999226、KB4474419，以及 2026-10-16 通过 vmrun 用 DISM 装上的 KB2533623（状态"已安装"，不需要重启，`SetDefaultDllDirectories`/`AddDllDirectory`/`RemoveDllDirectory` 已确认可用）。注意：这台虚拟机装了 KB2533623，没装这个补丁的 Win7 上是否能运行，要靠导入表检查来保证。KB2533623 不是 Vista 专用补丁，Vista、Win7、Server 2008/2008 R2 都有对应的包（Win7 x64 的是 `Windows6.1-KB2533623-x64.msu`）。社区常把 KB3063858（MS15-063，2015-06-09，修补 LoadLibrary 提权漏洞 CVE-2015-1758）当作它的替代品，但"取代"这一点没能从微软官方来源核实。它提供 `SetDefaultDllDirectories`、`AddDllDirectory`、`RemoveDllDirectory` 和 `LoadLibraryEx` 的 `LOAD_LIBRARY_SEARCH_*` 标志。Node 源码里只有 3 处用到 `LOAD_LIBRARY_SEARCH_SYSTEM32`（`deps/uv/src/win/winapi.c` 2 处，`deps/v8/src/diagnostics/unwinding-info-win64.cc` 1 处），而且加载失败都有回退。所以 node.exe 应该不需要这个补丁，编出来后用导入表再确认。Python 那边可能需要。测试目录是 guest 的 `C:\dsh-test\`。

**对照结果：** DeftKing 的 Node 22.23.3 跑 `scripts/win7-smoke.js`，21 项通过 20 项，唯一失败的是 `os.hostname()`（`uv_os_gethostname returned ENOSYS`）。我们的 GetHostNameW 补丁修的就是这个问题。
3. **Electron 在哪台机器上编译。** D 盘现在剩约 260 GB，本机可能够用，但还需确认 Chromium 构建的实际占用。
4. **更新策略地址**，即 `.env.windows` 里的 `DSH_DESKTOP_MANDATORY_UPDATE_PROD_ORIGIN`。

## 约束

- 在主仓库里 commit、push 或建 PR 之前，先问用户。
- 主仓库有大量自动检查（`AGENTS.md` 里的 `doc-sync`、`build:check` 等），但这个 fork 不打算进上游，不必为了通过上游的文档检查去改内容。
