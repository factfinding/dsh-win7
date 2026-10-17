# dsh-win7

让 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）桌面版在 **Windows 7 SP1 x64** 上运行的非官方适配。

> 本项目与 DeepSeek 无关，也不提交到上游。Win7 版的问题请在本仓库提 issue，不要报到官方仓库。

| | |
|---|---|
| 适配的 DSH 版本 | 0.2.0-rc.2（上游 tag `dsh-v0.2.0-rc.2`） |
| 当前发布 | [`dsh-v0.2.0-rc.2-win7.1`](https://github.com/factfinding/dsh-win7/releases/tag/dsh-v0.2.0-rc.2-win7.1) |
| DSH 源码改动 | [factfinding/deepseek-harness](https://github.com/factfinding/deepseek-harness/tree/dsh-v0.2.0-rc.2-win7) 的 `dsh-v0.2.0-rc.2-win7` 分支 |

## 安装

### 系统要求

- Windows 7 SP1 x64。32 位系统和没有 SP1 的 Win7 都不行。
- 磁盘：程序约 1.3 GB。第一次使用时，自带的 Python/Node 运行时还会复制一份到用户目录，约 0.3 GB。
- 不需要另装 .NET、Python、Node.js、PowerShell 或 Office。DSH 自带：
  - PowerShell 7.2；
  - Python 3.12，含 numpy、pandas、python-docx、python-pptx、openpyxl、Pillow、lxml 等；
  - Node.js 24 和 pnpm；
  - Office 文档转换。

### 先装这些系统更新和运行库

按顺序安装，每装完一个都按提示重启：

| 顺序 | 文件 | 是否需要 | 作用 |
|---|---|---|---|
| 1 | KB2533623（或替代它的 KB3063858） | 必需 | 提供 `AddDllDirectory` 等函数。没有它，Python 和 Office 转换无法启动。 |
| 2 | KB4474419（SHA-2 更新，v3） | 必需 | 它更新的 advapi32 里有自带 node.exe 要用的 `EventSetInformation`。没有它，node.exe 启动不了，助手运行 Node 命令（比如 Office 转换）时会"退出码 1、无输出"。 |
| 3 | VC++ 2015–2022 x64 运行库 **14.44.35211** | 必需 | Office 转换需要它。在 Win7 上它会顺带安装通用 C 运行库 UCRT（KB2999226），Python、看图、Office 转换都要用 UCRT。 |
| – | KB2999226（UCRT） | 备用 | 装完 VC++ 运行库后，如果检查发现没有 UCRT，再单独装它。 |
| – | KB2670838（平台更新） | 可选 | 真机上配合正常的显卡驱动，可能开启 GPU 加速。虚拟机里没有作用。 |

下载地址：

- Windows 更新：在 [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/) 搜索 KB 编号，选 "Windows 7 for x64-based Systems" 那一项。
- VC++ 运行库：<https://aka.ms/vs/17/release/vc_redist.x64.exe>。
  - **不要**用微软官网"最新版"的 `aka.ms/vc14/vc_redist.x64.exe`：那是 Visual Studio 2026 那一代，只支持 Win10/11。
  - 14.44.35211 是 2015–2022 系列的最后一版。

装完后在命令提示符里检查：

```
wmic qfe get HotFixID | findstr "2533623 3063858 2999226 4474419"
dir C:\Windows\System32\ucrtbase.dll
```

应该能看到 KB2533623（或 KB3063858）、KB2999226 和 KB4474419，并且 `ucrtbase.dll` 存在。

测试时用的文件的 SHA-256 如下（Win7 上用 `certutil -hashfile 文件名 SHA256` 校验）：

```
58b8b00113fa8b9657d8da5b14bae93f765f29651c81055e3d127d4a22e5c0d6  Windows6.1-KB2533623-x64.msu
99312df792b376f02e25607d2eb3355725c47d124d8da253193195515fe90213  windows6.1-kb4474419-v3-x64_b5614c6cea5cb4e198717789633dca16308ef79c.msu
cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b  vc_redist.x64.exe (14.44.35211)
43234d2986ca9b0de75d5183977964d161a8395c3396279ddfc9b20698e5bc34  Windows6.1-KB2999226-x64.msu
9fe71e7dcd2280ce323880b075ade6e56c49b68fc702a9b4c0a635f0f1fb9db8  Windows6.1-KB2670838-x64.msu
```

### 安装 DSH

1. 从 [Releases](https://github.com/factfinding/dsh-win7/releases) 下载 `deepseek-harness-0.2.0-rc.2-win7-x64-unsigned.exe`，核对 Release 页面上的 SHA-256。
2. 运行它。安装包没有签名，Win7 会提示"无法验证发布者"，点"运行"，然后点"立即安装"。
3. 装好后开始菜单里会出现 DeepSeek Harness。

### 离线安装

安装和启动都不需要联网。在能上网的电脑上把上面的更新、运行库和 DSH 安装包下载好，拷到 Win7 上按同样顺序安装即可。没有网络时可以浏览文件、运行命令、使用自带的 Python。和模型对话需要能访问模型服务：内网环境可以在设置里改成内网能访问的地址。

### 语音输入（实验性，可选）

语音输入在本机识别，不上传录音。它默认是关闭的，在侧栏的插件管理里启用带蓝色声波图标的"语音输入"即可。

联网时 DSH 会自己下载模型。离线时，先把下面 3 个文件下载好（国内可以把 `huggingface.co` 换成 `hf-mirror.com`），再按目录放进 `%USERPROFILE%\.dsh\speech-to-text\sensevoice\models\`。文件名和大小不能变，DSH 会校验 SHA-256。

| 放到 | 下载地址 | 字节数 |
|---|---|---|
| `sensevoice-onnx\model.int8.onnx` | <https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/model.int8.onnx> | 239,233,841 |
| `sensevoice-onnx\tokens.txt` | <https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/2365baeacb507f821a0c8120fcee3d484dba7a07/tokens.txt> | 315,894 |
| `silero\silero_vad.onnx` | <https://huggingface.co/csukuangfj/vad/resolve/fba88cd2e921609e7675c3aaf51e0b9b295da4bc/silero_vad.onnx> | 1,807,522 |

需要电脑上有麦克风。第一次识别要先加载模型，慢的机器上要等几十秒；闲置 5 分钟后模型会卸载，下次用时再加载。

### 已知限制

- 界面用软件渲染（GPU 加速默认不开），功能不受影响，窗口很大时滚动可能没那么流畅。
- 没有自动更新。程序会定期检查一个不存在的更新地址，检查失败时什么也不会发生。
- 很多新版的二进制 Python 包（尤其是用 Rust 写的）在 Win7 上无法导入。给自带的 Python 加装包，请建一个继承自带包的虚拟环境，装完先 import 试一下：
  ```
  "%USERPROFILE%\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe" -m venv --system-site-packages .venv
  ```
- 终端用 winpty 代替 ConPTY（ConPTY 要 Win10 1809 以上）。

## 适配了什么

| 组件 | 上游的问题 | 适配方式 |
|---|---|---|
| Electron | 官方 44.x 只支持 Win10+ | 用社区补丁 [Electron-for-windows-7](https://github.com/e3kskoy7wqk/Electron-for-windows-7) 自己编译 Electron 44.2.0，再加上 [`win7-fixes/electron`](win7-fixes/electron) 里的修复 |
| 自带 Node.js | 官方 24.x 不能在 Win7 上启动 | 用 Node 24.21.0 源码加 [`win7-fixes/node`](win7-fixes/node) 的 7 个补丁编译 |
| 自带 Python | python-build-standalone 依赖 Win8+ API | 换成 [PythonVista](https://github.com/adang1345/PythonVista) 3.12.14 |
| PowerShell | Win7 自带的 2.0 在沙箱里启动不了 | 自带 PowerShell 7.2.24 |
| 搜索（ripgrep） | 官方 rg.exe 在 Win7 上崩溃 | 用 `x86_64-win7-windows-msvc` 目标编译 ripgrep 15.0.0 |
| 看图（sharp）、Office 转换（LibreOffice Kit）、语音输入（ONNX Runtime） | 原生 DLL/EXE 导入了 Win8+ 函数 | 兼容层 DLL（[`shim/`](shim)），并改写这些文件的导入表 |
| 终端 | node-pty 只支持 ConPTY | 自己写的 [`@dsh-win7/pty-winpty`](shim/pty-winpty)（winpty） |
| DSH 自身 | Job 嵌套、打开方式列表、安装程序等 | 主仓库 fork 里的 8 个提交 |

## 仓库结构

- `deepseek-harness/`：子模块，指向 fork 的适配分支。
- `scripts/`：构建、打包和检查脚本。
- `shim/`：Win7 兼容层源码。
- `win7-fixes/`：Electron 和 Node 的补丁。
- [`docs/porting.md`](docs/porting.md)：从零构建，以及适配 DSH 新版本的步骤。
- [`CLAUDE.md`](CLAUDE.md)：给 Claude Code 的项目说明。

## 许可证

本仓库自己的代码以 [MIT](LICENSE) 许可证发布。DeepSeek Harness 以 MIT 许可证发布，版权归 DeepSeek 所有。安装包里的 Electron、Chromium、Node.js、Python、PowerShell、ripgrep、winpty、ONNX Runtime 等第三方组件，各自遵循自己的许可证。Electron 的 Win7 补丁来自 [e3kskoy7wqk/Electron-for-windows-7](https://github.com/e3kskoy7wqk/Electron-for-windows-7)。
