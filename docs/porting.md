# 构建与适配新版本

本文写给要自己构建 Win7 版、或者把适配移植到 DSH 新版本的人。目录约定和常用命令见 [CLAUDE.md](../CLAUDE.md)；每项改动的原因写在对应的提交信息和代码注释里。

所有命令都在仓库根目录下用 PowerShell 7 运行。

## 版本对应（dsh-v0.2.0-rc.2-win7.1）

| 组件 | 版本 | 固定在哪里 |
|---|---|---|
| DSH | 上游 tag `dsh-v0.2.0-rc.2` | 子模块 `deepseek-harness`。fork 分支 `dsh-v0.2.0-rc.2-win7` 上有 8 个提交，tag 是 `dsh-v0.2.0-rc.2-win7.1` |
| Electron | 44.2.0：Chromium 152.0.7977.76（`src@0d89dfa2`），electron_node `71b8b174`（v24.20.0） | `scripts/electron.gclient`、`scripts/electron-sync.cmd`；gn 参数在 `scripts/electron-release.gn` |
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
6. **参考 node_modules：** 用官方 Node 在 `out\host-web\` 里运行 `npm install @deepseek-ai/dsh@0.2.0-rc.2`。覆盖层以这些文件为原件，记下它们的 sha256，并读出要固定的版本。
7. **覆盖层：** 运行 `scripts\build-win7-overlay.ps1`，生成 `out\win7-runtime-overlay\`。兼容层 DLL 会在这一步编译。
8. **打包：**
   - 先建 `deepseek-harness\apps\desktop\.env.windows`：
     ```
     DSH_DESKTOP_APP_ID=local.dsh-win7.harness
     DSH_DESKTOP_AUTO_UPDATE_ENV=production
     DSH_DESKTOP_MANDATORY_UPDATE_PROD_ORIGIN=https://policy.invalid
     DSH_DESKTOP_MANDATORY_UPDATE_CONFIG='{}'
     ```
     更新地址指向不存在的 `policy.invalid`，所以不会自动更新。
   - 再运行 `scripts\package-desktop-win7.ps1`（加 `--check` 只检查配置）。
   - 产物在 `deepseek-harness\apps\desktop\.desktop-build\targets\win-x64\unsigned-artifacts\`。

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
    - `scripts/win7-job-probe/`：查进程所在的 Job。

## 适配 DSH 新版本

假设上游新 tag 是 `dsh-vX`：

1. **迁移源码改动**
   ```powershell
   git -C deepseek-harness fetch origin --tags
   git -C deepseek-harness switch -c dsh-vX-win7 dsh-vX
   git -C deepseek-harness cherry-pick dsh-v0.2.0-rc.2..dsh-v0.2.0-rc.2-win7
   ```
   逐个解决冲突。8 个提交各管一件事，提交信息写了原因，可以据此判断上游是否已经换了做法。
2. **对照依赖版本，有变化的部分重做**
   - **Electron：** `apps/desktop/package.json` 不再是 44.2.0 时，要换成 Electron-for-windows-7 对应版本的补丁，重新编译。必要时更新 `win7-fixes/electron` 和 `electron-release.gn`。
   - **Node：** `scripts/primary-runtime/lock.json` 的 Node 版本变了时，在新版本上重新打 `win7-fixes/node` 的补丁，改好后导出到 `win7-fixes/node/<新版本>/`，重新编译并更新 `nodeSha256`。
   - **Python：** 版本变了时，换成 PythonVista 对应版本，更新 `pythonNupkg`。
   - **pnpm：** 不要升级到 pnpm 12，它的原生程序在 Win7 上启动失败。
   - **原生包：** 重建 `out\host-web`，再运行 `build-win7-overlay.ps1`。原件变了时，sha256 检查会让打包直接失败，不会悄悄换错文件；这时按新文件重新生成兼容层的导出表，并复查缺哪些函数。
3. **出包并验证：** 打包，跑静态导入检查，在虚拟机里测试，方法同上。
4. **发布**
   - 在 fork 上打 `dsh-vX-win7.1` 并推送分支和 tag。
   - 在本仓库里更新子模块指针、README 和本文的版本表，提交后打同名 tag，把安装包上传到 GitHub Release。

### 版本号规则

- **fork 分支：** `<上游 tag>-win7`。
- **发布 tag：** `<上游 tag>-win7.<n>`，fork 和本仓库用同一个名字。同一个上游版本修了问题再发布时，`n` 加 1。
- **本仓库 main：** 跟最新的适配。旧版本需要修补时，从它的 tag 开一个 `release/<上游 tag>` 分支。
