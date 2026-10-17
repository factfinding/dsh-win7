# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

个人实验：让 DeepSeek Harness 桌面版（Electron 应用）在 Windows 7 x64 上运行，不提交上游。所有代码都 clone 到本目录下，包括主仓库（`deepseek-harness/`）。**不要使用上一级目录里那份旧的 `deepseek-harness` checkout（`..\deepseek-harness`）。**

本目录是公开仓库 `dsh-win7`（`github.com/factfinding/dsh-win7`），但只跟踪自己的文件。`.gitignore` 是白名单，只放行：
- `scripts/`、`shim/`、`win7-fixes/`、`docs/`；
- README、LICENSE、本文件；
- `deepseek-harness` 子模块，指向 fork 的适配分支。

第三方 clone、工具链、`out/` 都不进仓库，新增要公开的顶层文件或目录时要在 `.gitignore` 里放行。仓库结构、版本对应、构建和适配新版本的步骤见 [docs/porting.md](docs/porting.md)。Release 只上传安装包，系统更新和运行库在 README 里写清楚，不再分发。

**进度、已做的决定和待决问题都以 HANDOFF.md 为准，开工前先读完。** 阶段状态、阻碍清单或待决问题有变化时更新 HANDOFF.md，不要写进本文件。

HANDOFF.md 是本机的开发记录，不进仓库（2026-10-17 用户决定），因为里面有本机路径、虚拟机的网络和账号等环境信息。公开文件（README、`docs/`、脚本注释、提交信息）不要链接或引用它；要公开的结论写进这些文件本身。本文件也会公开，写本机路径时用相对路径，不写邮箱、密码这类个人信息。

## 目录约定

- `node/`：nodejs/node 的 clone。Win7 改动都在本地分支 `win7` 上，一个补丁一个提交，提交信息写明出处。新的改动也照此提交。`node/` 仓库里单独配置了提交身份。`node/` 不进仓库，公开的是 `git -C node format-patch --no-signature --zero-commit -o win7-fixes/node/<版本> v<版本>..win7` 导出的补丁；`win7` 分支改了以后要重新导出。
- `patches/`：参考用的第三方仓库，只读不改。补丁是第三方代码，先读懂再 `git apply`。
- `ripgrep/`：BurntSushi/ripgrep 15.0.0 的 clone，用 `scripts/build-ripgrep.ps1` 编 Win7 版（产物在 `out/ripgrep-target/`）。
- `shim/pty-winpty/`：自己写的 `@dsh-win7/pty-winpty`，在 Win7 上代替 node-pty（koffi 调 winpty.dll），用 `scripts/build-pty-winpty.ps1` 组装到 `out/pty-winpty/`。
- `shim/`：自己写的 Win7 兼容层源码，用于不方便重编的第三方二进制。`dshw7.c/.def`：`WaitOnAddress` 系列和 `ProcessPrng`，用在 sharp 的 `libvips-42.dll` 上。`dshlo.c`：libreoffice-kit.exe 缺的 4 个函数，它的 `.def` 由 `scripts/gen-forward-def.ps1` 根据 exe 的导入表生成（替换整个 kernel32/user32/bcrypt 时，其余函数都要转发回去）。`dsho.c`：sherpa-onnx 的 `onnxruntime.dll`（语音输入）缺的 6 个函数，`.def` 也是生成的；名字只有 4 个字符，因为它还要顶替 `dxgi.dll`。三者都由 `scripts/build-win7-overlay.ps1` 编好并放进运行时覆盖层。用 `scripts/build-shim.cmd [名字] [def]` 编，用 `scripts/patch-imports.ps1` 把目标文件导入表里的 DLL 名改成兼容层的名字（新名字不能比原名长）。
- `deepseek-harness/`：主仓库的部分克隆。改动放在分支 `dsh-v0.2.0-rc.2-win7` 上，这个分支建在 tag `dsh-v0.2.0-rc.2`（官网最新的 desktop 版本）上，不是 master。远程 `origin` 是官方仓库，只用来拉取；远程 `fork` 是用户的 fork `github.com/factfinding/deepseek-harness`（公开），推送到这里。仓库里单独配置了提交身份。每次发布打 tag `<上游 tag>-win7.<n>`；它在 dsh-win7 里是子模块，fork 上推了新提交以后，要在 dsh-win7 里更新子模块指针。
- `scripts/`：自己写的构建脚本，不要放进第三方源码目录。
- `win7-fixes/`：自己写的补丁，用于没有独立 clone 的第三方源码（Electron/Chromium），以及从 `node/` 导出的 Node 补丁（`win7-fixes/node/<版本>/`）。`win7-fixes/electron/<e\src 下的路径>/*.patch` 由 `scripts/apply-electron-win7-patches.ps1` 在补丁仓库的补丁之后打到该路径的仓库里。补丁文件用 LF 换行，在注释里写明原因。
- `tools/`：本机开发用的工具。`tools/node-v24.21.0-win-x64/` 是**官方** Node 24.21.0（哈希和 `lock.json` 原值 `158f7685…` 一致），供本机在主仓库里开发时使用；主仓库 CI 用的是 Node 24，本机 nvm 里没有 24。不要改用户全局的 nvm 版本，在命令里临时把它加到 PATH 前面。不要拿我们编的 Win7 版 node 做本机开发，免得本机的问题和补丁搅在一起。
- `out/`：node zip、sha256、构建日志。
- `e/`：Electron + Chromium 源码（gclient 根目录），`depot_tools/`：Google 的工具链。`.vscode/settings.json` 让 VS Code 不扫描、不监听、不搜索这两个目录（否则 VS Code 的 git 插件会去拉 Chromium 的完整历史）；不要删掉。

**clone 时一律加 `-c core.autocrlf=false -c core.longpaths=true`（并用 `--config` 写进该仓库）。** 本机 system 级配置是 `core.autocrlf=true`，不关掉的话文件会被转成 CRLF，LF 格式的补丁就打不上。

## 架构要点：DSH 里有两种 "Node"

这一点要看多个文件才能理清。动手前先确认要改的是哪一种：

1. **Electron 当 Node 用**：Host、插件、内置 `dsh` CLI 都用 `ELECTRON_RUN_AS_NODE=1` 运行（见主仓库 `apps/desktop/scripts/node-bin/`）。这部分会随补丁版 Electron 44.2.0 一起获得 Win7 支持，Electron 的下载入口在 `apps/desktop/scripts/prepare-runtime.ts`。
2. **独立的 primary-runtime `node.exe`**：由 `scripts/primary-runtime/prepare.ts` 按 `lock.json`（Node 24.21.0）从 nodejs.org 下载。三个调用方都用 `execFile` 按固定路径 `primary-runtime/dependencies/node/bin/node.exe` 调用。它必须是从上游源码加 Win7 补丁编出的真 exe，不能拿 Electron 代替，原因见 HANDOFF.md 的"已做的决定"。这就是当前 Phase 1 的目标。

Phase 1 对主仓库的改动只有两处：让 `prepare.ts` 的 win-x64 目标能读取本地压缩包，同时更新 `lock.json` 的哈希。三个调用方不改。产出的 zip 必须和 nodejs.org 的 `node-v24.21.0-win-x64.zip` 目录结构相同。

## 命令

在本目录下用 PowerShell 执行，都验证过。实际打包用 `scripts\package-desktop-win7.ps1`，它会设好下面打包那条用到的全部变量。

```powershell
# 获取源码
git -c core.autocrlf=false -c core.longpaths=true clone --depth 1 --branch v24.21.0 --config core.autocrlf=false --config core.longpaths=true https://github.com/nodejs/node node
git -c core.autocrlf=false -c core.longpaths=true clone --config core.autocrlf=false --config core.longpaths=true https://github.com/e3kskoy7wqk/Electron-for-windows-7 patches/Electron-for-windows-7

# 编译 Node（release x64 + package）。日志重定向到 out\build-node.log，在后台运行
cmd /c scripts\build-node.cmd *> out\build-node.log
# 只改了 C/C++ 源码、没改 gyp 时，可加 noprojgen 跳过重新生成工程
cmd /c scripts\build-node.cmd noprojgen *> out\build-node.log

# 主仓库本机环境（在 deepseek-harness\ 下）：官方 Node 24 + 仓库锁定的 pnpm（corepack）
$env:PATH = (Resolve-Path ..\tools\node-v24.21.0-win-x64).Path + ';' + $env:PATH
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
$env:ELECTRON_SKIP_BINARY_DOWNLOAD = '1'   # 官方 Electron 在 Win7 上不能用，本机开发也用不到
corepack pnpm install --frozen-lockfile

# 主仓库 Windows 打包（在 deepseek-harness\ 下）。需先建 apps/desktop/.env.windows，见 docs/porting.md
# 必须指向 Win7 版 node zip，否则 lock.json 的哈希对不上，打包会失败
$env:DSH_PRIMARY_RUNTIME_NODE_ARCHIVE = (Resolve-Path ..\out\node-v24.21.0-win-x64.zip).Path
pnpm run package:desktop:win:x64:unsigned        # 加 --check 只检查配置
```

`scripts/build-node.cmd` 会清掉 `NoDefaultCurrentDirectoryInExePath`。Claude Code 的 shell 设置了这个变量，它会让 cmd 找不到当前目录下的 `vcbuild.bat`。自己写的 `.cmd` 文件必须是 CRLF 换行。

### 在 Win7 虚拟机里测试

虚拟机信息见 HANDOFF.md 待决问题 2。用 `vmrun` 的 guest 操作，账号 `test`，密码问用户：

```powershell
$vmrun = "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe"
$vmx = '<虚拟机的 .vmx 路径，见 HANDOFF.md>'
$cred = @('-gu','test','-gp','<密码>')
& $vmrun -T ws @cred copyFileFromHostToGuest $vmx <本机文件> 'C:\dsh-test\<文件>'
# runProgramInGuest 不回传输出：在 guest 里重定向到文件，再拷回本机
& $vmrun -T ws @cred runProgramInGuest $vmx 'C:\Windows\System32\cmd.exe' '/c C:\dsh-test\node\node.exe C:\dsh-test\win7-smoke.js > C:\dsh-test\out.txt 2>&1'
& $vmrun -T ws @cred copyFileFromGuestToHost $vmx 'C:\dsh-test\out.txt' <本机路径>
```

`scripts/win7-smoke.js` 是 HANDOFF.md Phase 1 第 7 步的检查清单，每项输出一行 PASS/FAIL。`scripts/win7-native-test.js` 测原生模块：在装好 `koffi bufferutil better-sqlite3` 的目录里运行。`scripts/win7-voice-test.js` 测语音输入的推理（用法见文件开头），模型和测试音频在 `out\sensevoice-models\`。guest 里的 Node 完整包解压在 `C:\dsh-test\node-v24.21.0-win-x64\`，解压工具在 `C:\dsh-test\tools\7z.exe`。guest 是中文系统，cmd 自身的输出是 GBK 编码，node 的输出是 UTF-8。

检查整个安装包在 Win7 上缺不缺 API，首选 `scripts\check-win7-rtm-imports.ps1 -Root <目录>`。它不需要虚拟机：用原版 SP1 安装镜像里的系统 DLL（`out\win7-sp1-rtm\`），叠加 KB4474419 的系统 DLL（从装了它的旧虚拟机里拷出来），核对每个 exe/dll/node/pyd 的静态导入。基准是安装说明里的必装项：SP1 + KB2533623 + KB4474419 + VC++/UCRT。旧虚拟机打过更多补丁，用它做的检查会漏掉问题：node.exe 依赖 KB4474419 才有的 `EventSetInformation`，就是这样漏掉的。

在 guest 里逐个解析导入的老办法：先在本机导出导入表，再在 guest 里解析。guest 装了 KB2533623，所以要另外在本机确认没有导入 `SetDefaultDllDirectories`、`AddDllDirectory`、`RemoveDllDirectory`：

```powershell
scripts\dump-imports.ps1 -Exe node\out\Release\node.exe -OutTsv out\node-imports.tsv
# 把 tsv 和 scripts\check-imports-win7.ps1 拷到 guest，再通过 .cmd 执行：
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\dsh-test\check-imports-win7.ps1 -Tsv C:\dsh-test\node-imports.tsv
```

`runProgramInGuest` 默认在 Session 0（服务会话）里运行程序，弹出的窗口用户看不见：Win7 只会弹出"交互式服务检测"提示。会弹窗的程序（比如 `dsh web`，添加工作区时会弹原生的目录选择框）要加 `-interactive`（常配合 `-noWait`）启动，这样才会在用户的桌面会话（Session 1）里运行，前提是用户已用 `test` 登录。用户注销后，这样启动的进程会随会话一起结束，需要重新启动；重新登录后的会话号也可能变（比如变成 2）：

```powershell
& $vmrun -T ws @cred runProgramInGuest $vmx -interactive -noWait 'C:\Windows\System32\cmd.exe' '/c C:\dsh-test\dsh-web-start.cmd'
```

稍复杂的 guest 命令要先写成 CRLF 的 `.cmd` 文件，拷进去再执行。直接写在 `runProgramInGuest` 的参数里时，有些程序会收到一个多余的空白参数，比如 DISM 报错 87"未识别命令行选项"。Win7 自带的 DISM 不支持 `/format:table`。guest 里只有 PowerShell 2.0。

装好 VMware Tools 之前（比如重装了虚拟机），往里传文件只能打包成 ISO，再由用户在 VMware 里挂到光驱上：

```powershell
# 用 Windows PowerShell 5.1 运行（IMAPI2 COM）。Joliet 文件名最长 64 个字符，太长的文件先改名
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\make-iso.ps1 -SourceDir <目录> -IsoPath out\to-vm.iso
```

## 主仓库注意事项

- 主仓库的说明文件是 `AGENTS.md`。主仓库是在 `core.symlinks=false` 下检出的，软链接都变成了只含目标路径的文本文件，所以主仓库的 `CLAUDE.md` 和 `.claude/skills` 不会自动加载。开发者模式已在 2026-10-17 打开，测试里建符号链接的用例能跑了，但已检出的文件不会自动变回软链接。直接读 `AGENTS.md` 和 `.agents/skills/`。
- 在主仓库或 dsh-win7 commit、push、打 tag、发 Release 或建 PR 之前，先问用户。
- 这个 fork 不进上游，不必为了通过上游的 `doc-sync` 等文档检查去改内容。
