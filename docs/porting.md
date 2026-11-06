# 构建与适配新版本

本文写给要自己构建 Win7 版、或者把适配移植到 DSH 新版本的人。目录约定和常用命令见 [CLAUDE.md](../CLAUDE.md)；每项改动的原因写在对应的提交信息和代码注释里。

所有命令都在仓库根目录下用 PowerShell 7 运行。

## 版本对应（dsh-v0.2.2-rc.1-win7.1）

| 组件 | 版本 | 固定在哪里 |
|---|---|---|
| DSH | 上游 tag `dsh-v0.2.2-rc.1` | 子模块 `deepseek-harness`。fork 分支 `dsh-v0.2.2-rc.1-win7` 上有 9 个提交：8 个 Win7 适配，加 1 个自动更新地址；tag 是 `dsh-v0.2.2-rc.1-win7.1` |
| Electron | 44.2.0：Chromium 152.0.7977.76（`src@0d89dfa2`），electron_node `71b8b174`（v24.20.0）。DSH 0.2.2 声明 `^44.7.0`（Chromium 152.0.7977.130），社区补丁目前只到 44.2.0，fork 里钉在 44.2.0 | `scripts/electron.gclient`、`scripts/electron-sync.cmd`；gn 参数在 `scripts/electron-release.gn`；版本钉在主仓库 `apps/desktop/package.json` |
| pnpm | 11.28.5（随自带运行时分发） | 主仓库根目录 `package.json` 的 `packageManager` |
| Electron Win7 补丁 | [e3kskoy7wqk/Electron-for-windows-7](https://github.com/e3kskoy7wqk/Electron-for-windows-7) `1086a0a7`（目录 `v44.2.0`），外加 `win7-fixes/electron` | `scripts/apply-electron-win7-patches.ps1` |
| 自带 Node | 24.21.0，外加 `win7-fixes/node/v24.21.0` 的 7 个补丁 | 主仓库 `scripts/primary-runtime/lock.json` 里的 `nodeSha256` |
| 自带 Python | PythonVista 3.12.14 NuGet 包 | `lock.json` 里的 `pythonNupkg` |
| PowerShell | 7.2.24 win-x64 zip（sha256 `a1ccb6d8ad52f917470a136c3752af4465f261bcbe570cf44f52aa69ae6e867e`） | `out\pwsh\*.sha256` |
| ripgrep | 15.0.0（`@vscode/ripgrep` 1.18.0 带的版本） | `scripts/build-ripgrep.ps1` |
| winpty | 0.4.3（`winpty-0.4.3-msvc2015.zip`） | `scripts/build-pty-winpty.ps1` |
| 覆盖层固定的 npm 包 | `@vscode/ripgrep` 1.18.0、`sharp` 0.35.5、`@deepseek-ai/libreoffice-kit` 0.1.5、`sherpa-onnx-node` 1.13.8 及各自的 win32-x64 包 | `scripts/build-win7-overlay.ps1` 从参考 `node_modules` 读出，写进覆盖层清单的 `pins` |
| VC++ 运行库（用户安装） | 14.44.35211 | README |

## 从零构建

### 准备

- **磁盘和机器：** Electron 的源码和产物要 100 GB 以上；编译时内存越大越好（本机 23 GB，`ELECTRON_JOBS=12`）。
- **工具：**
  - Visual Studio 2022，带 C++ 桌面开发、ClangCL 和 Windows SDK。
  - Rust：rustup stable，加上 `rust-src` 组件。
  - 7-Zip（`C:\Program Files\7-Zip`）。
  - 官方 Node 24.21.0：解压到 `tools\node-v24.21.0-win-x64\`，用于主仓库开发和打包。
  - Google 的 depot_tools：clone 到 `depot_tools\`。
- **克隆：** clone 时一律关掉 CRLF 转换，补丁要求 LF：
  ```powershell
  git -c core.autocrlf=false -c core.longpaths=true clone --recurse-submodules https://github.com/factfinding/dsh-win7
  ```
- **主仓库依赖：** 在 `deepseek-harness\` 下照 CLAUDE.md 的"主仓库本机环境"安装。

### 各部分产物（都放在 `out\`）

1. **Node**
   ```powershell
   git -c core.autocrlf=false clone --depth 1 --branch v24.21.0 --config core.autocrlf=false https://github.com/nodejs/node node
   git -C node switch -c win7
   git -C node am ..\win7-fixes\node\v24.21.0\*.patch
   cmd /c scripts\build-node.cmd *> out\build-node.log
   ```
   把 `node\Release\node-v24.21.0-win-x64.zip` 拷到 `out\`。编译结果不是逐字节可复现的，所以要把主仓库 `lock.json` 的 `nodeSha256` 改成自己这个 zip 的值。
2. **Electron**
   - clone 补丁仓库：
     ```powershell
     git -c core.autocrlf=false clone https://github.com/e3kskoy7wqk/Electron-for-windows-7 patches/Electron-for-windows-7
     git -C patches/Electron-for-windows-7 checkout 1086a0a7
     ```
   - 依次运行：
     - `cmd /c scripts\electron-sync.cmd`：拉源码，不带历史。
     - `scripts\apply-electron-win7-patches.ps1`：打补丁。之后不要再 `gclient sync`，否则补丁会被重置。
     - `cmd /c scripts\electron-build.cmd`：编译。
   - 把 `e\src\out\Release\dist.zip` 拷成 `out\electron-v44.2.0-win32-x64.zip`。
3. **ripgrep**
   - 在 `ripgrep\` 里 clone BurntSushi/ripgrep 的 tag `15.0.0`，然后运行 `scripts\build-ripgrep.ps1`。
   - 把 `out\ripgrep-target\x86_64-win7-windows-msvc\release-lto\rg.exe` 拷成 `out\rg-15.0.0-win7-x64.exe`。
4. **winpty：** 下载 [winpty 0.4.3](https://github.com/rprichard/winpty/releases/tag/0.4.3) 的 `winpty-0.4.3-msvc2015.zip`（sha256 `35a48ece…`，完整值见 `scripts/build-pty-winpty.ps1`），解压到 `out\winpty\extract\`。
5. **PowerShell：** 下载 [PowerShell 7.2.24](https://github.com/PowerShell/PowerShell/releases/tag/v7.2.24) 的 `PowerShell-7.2.24-win-x64.zip`，放到 `out\pwsh\`。旁边建一个同名 `.sha256` 文件，里面只写哈希值。
6. **参考 node_modules：** 用官方 Node 在 `out\host-web-0.2.2-rc.1\` 里运行 `npm install --ignore-scripts @deepseek-ai/dsh@0.2.2-rc.1`。覆盖层以这些文件为原件，记下它们的 sha256，并读出要固定的版本。
7. **覆盖层：** 运行 `scripts\build-win7-overlay.ps1 -Reference out\host-web-0.2.2-rc.1\node_modules`，生成 `out\win7-runtime-overlay\`。兼容层 DLL 会在这一步编译。
8. **打包：**
   - 先建 `deepseek-harness\apps\desktop\.env.windows`：
     ```
     DSH_DESKTOP_APP_ID=local.dsh-win7.harness
     DSH_DESKTOP_AUTO_UPDATE_ENV=production
     DSH_DESKTOP_MANDATORY_UPDATE_PROD_ORIGIN=https://policy.invalid
     DSH_DESKTOP_MANDATORY_UPDATE_CONFIG='{}'
     ```
     这里的地址是强制更新策略用的，指向不存在的 `policy.invalid`，所以不会触发强制更新。普通的自动更新另走 `DSH_WIN7_UPDATE_URL`，见下面的"发布"。
   - 再运行 `scripts\package-desktop-win7.ps1`（加 `--check` 只检查配置）。没设 `DSH_WIN7_UPDATE_URL` 时，它让包从本仓库 Release 的 `releases/latest/download/` 检查更新。
   - 产物在 `deepseek-harness\apps\desktop\.desktop-build\targets\win-x64\unsigned-artifacts\`：安装包、它的 `.blockmap` 和 `nightly.yml`。
   - 打包最后的自检（`smoke-packaged-runtime`）偶尔会超时：离线安装插件那一步只给 120 秒，而新生成的程序第一次运行会比较慢。这时安装包其实已经生成，在 `deepseek-harness\apps\desktop\` 下单独重跑 `corepack pnpm exec tsx scripts/smoke-packaged-runtime.ts --unsigned`，通过即可（0.2.1-rc.2 和 rc.3 两次打包都遇到了）。
   - 构建阶段偶尔会在 inspector 的 DevTools 那一步报 `EPERM: operation not permitted, rename …devtools.build-xxxx -> …devtools`：刚写出的几千个文件被别的进程（多半是杀毒软件扫描）占着。重新打包即可。
   - 打包时开着 VS Code，要在工作区设置的 `files.watcherExclude` 里排除 `**/.desktop-build/**`，改完重启 VS Code 才生效。Python Environments 扩展（`ms-python.vscode-python-envs`）每看到一个 `.py` 变化就启动一个 `rg` 扫描工作区，而打包要解压几千个 `.py`，`rg` 会占满所有 CPU。表现是电脑卡死，或者 `prepare:primary-runtime` 报 `spawnSync …python.exe ETIMEDOUT`（Python 自检每步限 120 秒）。排除后，打包从超时失败变成约 10 分钟完成。

### 检查与测试

- **静态导入检查：** 每次出新包都要跑一遍：
  ```powershell
  scripts\check-win7-rtm-imports.ps1 -Root <win-unpacked 目录>
  ```
  它核对每个 exe/dll/node/pyd 的静态导入，基准是原版 SP1 + KB2533623 + KB4474419 + VC++/UCRT。需要准备：
  - `out\win7-sp1-rtm\install.wim`：从 Win7 SP1 x64 安装镜像的 `sources\` 里取。
  - `out\win7-sp1-rtm\updates\KB4474419\{System32,SysWOW64}\`：从装了 KB4474419 的机器上拷出这个补丁更新过的 DLL。

  目前只允许出现两项：ConPTY 组件（Win7 上不用）和 reflink（加载失败后会自动改用复制）。
- **虚拟机测试：**
  - 至少用一台只装了必需更新的全新 Win7 SP1。
  - 分别从开始菜单和从安装程序结束页的"运行"启动 DSH。从结束页启动时，DSH 会继承安装程序所在的 Job：Win7 的程序兼容性助手建的，只允许显式脱离。在这种情况下，命令进程要先脱离它才能加入自己的 Job，见 fork 里 `fix(windows): leave the creator's Job…` 那个提交。
  - 测试脚本：
    - `scripts/win7-smoke.js`：Node 本身；
    - `scripts/win7-native-test.js`：原生模块；
    - `scripts/win7-voice-test.js`：语音推理；
    - `scripts/win7-gpu-check.cmd`：用 DevTools 端口启动 DSH，读出 `chrome://gpu` 的特性状态，判断是否开了 GPU 加速。实体机装 KB2670838 后为开启；虚拟机里 Chromium 的黑名单屏蔽了 VMware 显卡，始终是软件渲染；
    - `scripts/win7-job-probe/`：查进程所在的 Job。

## 适配 DSH 新版本

假设上游新 tag 是 `dsh-vX`，上一次适配的是 `dsh-v0.2.2-rc.1`：

1. **迁移源码改动**
   ```powershell
   git -C deepseek-harness fetch origin --tags
   git -C deepseek-harness switch -c dsh-vX-win7 dsh-vX
   git -C deepseek-harness cherry-pick dsh-v0.2.2-rc.1..dsh-v0.2.2-rc.1-win7
   ```
   - 逐个解决冲突。9 个提交各管一件事，提交信息写了原因，可以据此判断上游是否已经换了做法。
   - 冲突解决完以后，先在主仓库里 `corepack pnpm install --frozen-lockfile`，再继续 cherry-pick。否则 pre-commit 钩子可能因为 `node_modules` 还是旧版本而报错（比如 "Provider metadata is stale"）。
   - 如果某个包不再声明某个依赖，pnpm 不会删掉它在这个包 `node_modules\.bin` 里留下的启动脚本。等那个依赖的旧版本被清掉，打包就会报 `Cannot find module …\.pnpm\<包>@<旧版本>\…`（0.2.1-rc.3 时 `apps/desktop` 的 tsx 就是这样）。找出指向不存在的 `.pnpm` 目录的启动脚本，删掉就行。
   - 自动合并的地方也要逐个核对。0.2.1 时上游重构过 Node 下载和打包脚本，Win7 的改动要按新结构重新接入。
2. **对照依赖版本，有变化的部分重做**
   - **Electron：** `apps/desktop/package.json` 不再是 44.2.0 时，要换成 Electron-for-windows-7 对应版本的补丁，重新编译。必要时更新 `win7-fixes/electron` 和 `electron-release.gn`。
   - **Node：** `scripts/primary-runtime/lock.json` 的 Node 版本变了时，在新版本上重新打 `win7-fixes/node` 的补丁，改好后导出到 `win7-fixes/node/<新版本>/`，重新编译并更新 `nodeSha256`。
   - **Python：** 版本变了时，换成 PythonVista 对应版本，更新 `pythonNupkg`。
   - **pnpm：** 不要升级到 pnpm 12，它的原生程序在 Win7 上启动失败。
   - **原生包：** 按新版本建参考目录 `out\host-web-<版本>`，和覆盖层清单里记录的原件 sha256 逐个比对。都相同时，现有覆盖层可以原样复用（0.2.1 就是这样）；有变化时再用 `-Reference` 指向新目录运行 `build-win7-overlay.ps1`，按新文件重新生成兼容层的导出表，并复查缺哪些函数。打包时也会做同样的 sha256 检查，原件对不上就直接失败，不会悄悄换错文件。
   - **上游新代码：** 搜一下新出现的 `powershell.exe` 调用（Win7 上是 2.0）、无条件调用 `node-addon-require-builtin` 的地方，以及新增的 koffi 绑定和安装程序原生代码。
3. **出包并验证：** 打包，跑静态导入检查，在虚拟机里测试，方法同上。再按下面的"测试自动更新"，从上一版更新到这一版试一次。
4. **发布**
   - 在 fork 上打 `dsh-vX-win7.1` 并推送分支和 tag。
   - 在本仓库里更新子模块指针、README 和本文的版本表，提交后打同名 tag。
   - 整理 Release 文件，再新建 Release（`X` 是不带 `dsh-v` 的版本号）：
     ```powershell
     scripts\prepare-win7-release.ps1 -Version X     # 输出到 out\release\dsh-vX-win7.1\
     ```
     上传其中的安装包、`.blockmap` 和 `nightly.yml` 三个文件，`.sha256` 里的值写进 Release 说明。Release 要标为 Latest，不能标成预发布。

## 自动更新

从 0.2.1-rc.5 起，Win7 版用 DSH 自带的更新功能（electron-updater），只改打包配置，不改更新代码：

- 打包时设了 `DSH_WIN7_UPDATE_URL`，未签名的 Windows 包里就会有 `resources\app-update.yml`，DSH 的更新功能看到它才会开启。地址默认是本仓库的 `releases/latest/download/`，GitHub 会把它跳转到标为 Latest 的那个 Release。
- 更新频道是 `nightly`，所以要找的是 `nightly.yml`。`prepare-win7-release.ps1` 把里面安装包的地址改成带 tag 的绝对地址 `releases/download/<tag>/<安装包>`，安装包和 `.blockmap` 则按上面的文件名放在同一个 Release 里。
- **增量下载：** 旧安装包取自安装时缓存的 `%LOCALAPPDATA%\@deepseek-aidsh-desktop-updater\installer.exe`。旧版本的 blockmap 优先用同一目录里的 `current.blockmap`，它是上次自动更新时存下的；没有这个文件时（手动安装的版本），electron-updater 把新安装包地址里的新版本号全部换成已安装的版本号，再加上 `.blockmap`，就得到旧版本 blockmap 的地址。按 `dsh-v<版本>-win7.1` 的 tag 和 `deepseek-harness-<版本>-win7-x64-unsigned.exe` 的文件名，这个地址正好落在旧版本自己的 Release 里，所以每个 Release 只放自己的三个文件。
- 缺 blockmap 或缓存时会退回完整下载。自动更新过以后又手动装了别的版本时，`current.blockmap` 和 `installer.exe` 就对不上了，拼出来的文件过不了 SHA-512 校验，也会退回完整下载。这些情况只是多下载一些，不会装坏。增量的大小取决于两版安装包有多少块相同：rc.3 到 rc.5 要下 31 MB，上游改动大的 0.2.1-rc.5 到 0.2.2-rc.1 要下 398 MB，接近整包。
- GitHub 支持单段 Range 请求，多段的会回 501，所以更新地址带 `useMultipleRangeRequest: false`，一次请求一段。
- 更新是静默安装：DSH 退出，装完后自动重新打开，期间没有窗口。

发布时注意：

- 以后每个 Release 都要带 `nightly.yml` 并标为 Latest，否则 `latest/download/nightly.yml` 会 404，已安装的版本检查不到更新。给旧版本补发的 Release 不要标 Latest（`gh release create --latest=false`）。
- DSH 只认更高的版本号。同一个上游版本重新发布（`win7.2`）时，要用 `--build-version` 抬高版本号，比如 `0.2.1-rc.5` 用 `0.2.1-rc.5.2`；这时 `prepare-win7-release.ps1` 用 `-Version 0.2.1-rc.5.2 -Tag dsh-v0.2.1-rc.5-win7.2`。上游正式版（不带 `-rc`）后面不能这样加，遇到时再定办法。版本号替换后的 blockmap 地址不再落在旧 Release 里，要把旧版本的 blockmap 按算出来的目录和文件名一起上传，否则只是退回完整下载。

### 测试自动更新

在虚拟机里装上一版，让它从本机的测试服务器更新到新版。`scripts/win7-update-test-server.mjs` 模拟 GitHub 的两次跳转、单段 Range 和对多段 Range 的 501，并记下每个请求：

1. 准备服务器目录，`<主机 IP>` 是虚拟机能访问到的本机地址：
   ```powershell
   scripts\prepare-win7-release.ps1 -Version X -BaseUrl http://<主机 IP>:8817/releases/download/ -Out out\update-test\dsh-vX-win7.1
   ```
   再把上一版的 `.blockmap` 放进 `out\update-test\<上一版的 tag>\`，文件名和它在 Release 里的一样：
   ```powershell
   gh release download <上一版的 tag> --repo factfinding/dsh-win7 -p '*.blockmap' -D out\update-test\<上一版的 tag>
   ```
2. 启动服务器：`tools\node-v24.21.0-win-x64\node.exe scripts\win7-update-test-server.mjs out\update-test dsh-vX-win7.1 <主机 IP> 8817`。
3. 在虚拟机里把上一版安装目录下 `resources\app-update.yml` 的 `url` 改成 `http://<主机 IP>:8817/releases/latest/download/`。0.2.1-rc.3 及更早的版本没有这个文件，新建一个：
   ```yaml
   provider: generic
   url: http://<主机 IP>:8817/releases/latest/download/
   channel: nightly
   useMultipleRangeRequest: false
   updaterCacheDirName: '@deepseek-aidsh-desktop-updater'
   ```
   如果这台虚拟机之前自动更新过，再装回旧版来测，先删掉 `%LOCALAPPDATA%\@deepseek-aidsh-desktop-updater\` 下的 `pending` 目录和 `current.blockmap`。不删的话，electron-updater 会直接用 `pending` 里已经下好的安装包；`current.blockmap` 和重装的旧安装包对不上，也会退回完整下载。
4. 在 DSH 里检查更新、下载、安装。服务器日志里安装包的请求应该都是 206，加起来远小于安装包大小，这说明走的是增量下载。装完后 DSH 会自动重新打开，版本变成新版。DSH 不记录更新日志，用 GitHub 实测时没有服务器日志可看，可以在虚拟机里对比 `netstat -e` 的接收字节数，只要明显小于安装包大小，就说明没有退回完整下载。

想测"已安装的这一版再往后更新"时，用 `scripts\package-desktop-win7.ps1 --build-version X.<日期>.<n>` 打一个版本号更高、其余相同的测试包，它的 tag 和文件名按这个版本号来。发布后，还要把 `app-update.yml` 的地址换回 GitHub，从真实的 Release 再测一次。

## 版本号规则

- **fork 分支：** `<上游 tag>-win7`。
- **发布 tag：** `<上游 tag>-win7.<n>`，fork 和本仓库用同一个名字。同一个上游版本修了问题再发布时，`n` 加 1，版本号的处理见上面的"自动更新"。
- **Release 文件名：** `deepseek-harness-<版本>-win7-x64-unsigned.exe` 和同名的 `.blockmap`，再加 `nightly.yml`。增量下载靠 tag 和文件名里的版本号找到旧版本的 blockmap，不要改这个格式。
- **本仓库 main：** 跟最新的适配。旧版本需要修补时，从它的 tag 开一个 `release/<上游 tag>` 分支。
