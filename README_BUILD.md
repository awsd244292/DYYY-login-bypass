# DYYY 构建指南（产出 .deb）

> DYYY 是一个 **iOS Theos/Logos Tweak**（用于调整抖音 UI / 绕过登录等）。
> 它产出的 `.deb` 是 **`iphoneos-arm` 包**，必须在 **macOS + Theos + iOS SDK + ldid**
> 环境下交叉编译，**无法在 Linux / Windows 上直接编译**。

---

## 0. 没有 Mac？用 GitHub Actions 云端构建（推荐）

本仓库自带 `.github/workflows/build.yml`，会在 **GitHub 托管的 macOS  runner** 上
用 `huami1314/theos-action` 自动装好 Theos + iOS SDK 并 `make package`，
最后把 `rootful / rootless / roothide` 三种 `.deb` 作为 **构建产物（artifact）** 上传。
你全程不需要任何本地工具链，也不需要有 Mac。

步骤（约 5 分钟，免费 GitHub 账号即可）：

1. 在 GitHub 新建一个**公开**仓库（私有也可，但要给 Actions 读写权限）。
2. 把本目录（`/workspace/DYYY`）下的全部文件推上去（保持 `.github/` 目录结构）：
   ```bash
   cd DYYY
   git init && git add -A && git commit -m "DYYY with login bypass"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
3. 进入仓库的 **Actions** 标签页 → 选择 **build deb** → 点 **Run workflow**
   （也可直接等 push 触发的那次运行）。
4. 运行结束后，在对应 run 的 **Artifacts** 里下载 `DYYY-<时间戳>.zip`，
   里面包含三个 `.deb`（rootful / rootless / roothide）。
5. 用 Sileo / Filza 安装对应你设备方案的 `.deb`，或用 TrollFools 注入到抖音 (Aweme)。

> 提示：`build.yml` 在 `workflow_dispatch`（手动 Run workflow）时**必定构建**，
> 不会因为"没有检测到相关改动"而跳过。

---

## 1. 前置条件（本地 macOS 构建，可选）

- 一台 macOS（Apple Silicon 或 Intel 均可）。
- Xcode 及命令行工具：`xcode-select --install`。
- 已安装 [Theos](https://theos.dev/docs/installation)。
- 已配置 **iOS SDK**（Theos 需要 iOS 头文件/框架才能编译 `arm64` / `arm64e` 的 `.dylib`）。
  - 推荐：下载社区整理好的 iOS SDK 放到 `$THEOS/sdk`（如 `iPhoneOS.sdk`）。
- 已安装 `ldid`（用于 iOS 代码签名）：`brew install ldid` 或 `sudo apt install ldid`（在 macOS 用 brew）。

## 2. 获取代码

```bash
git clone https://github.com/Wtrwx/DYYY.git
cd DYYY
```

> 若你使用的是本仓库的修改版（已含“绕过登录”模块），直接 `cd` 进该目录即可。

## 3. 构建

```bash
# 赋予脚本执行权限（首次）
chmod +x build_deb.sh

# 默认（有根设备）
./build_deb.sh

# 或指定方案：
./build_deb.sh rootless   # 无根 (rootless)
./build_deb.sh roothide   # roothide
```

脚本会执行 `make clean && make package FINALPACKAGE=1`，并在 `packages/` 下生成 `.deb`。

也可以直接手动构建（等价）：

```bash
export THEOS=/opt/theos
make clean
make package FINALPACKAGE=1            # 有根
# make package FINALPACKAGE=1 SCHEME=rootless
# make package FINALPACKAGE=1 SCHEME=roothide
```

## 4. 安装 / 注入

- **越狱设备**：用 Sileo / Filza 直接安装 `packages/*.deb`，重启抖音 (Aweme)。
- **TrollStore / TrollFools**：用 TrollFools 将生成的 tweak 注入到抖音 App。
- 注入/安装后，打开抖音 → 双指长按或「设置 → DYYY」→ 打开 **“绕过登录（游客浏览）”** 开关。

## 5. “绕过登录”适配说明（重要）

抖音每次大版本更新常会修改登录相关的**类名 / 方法名**，这正是老版本“失效”甚至注入崩溃的主因。

本仓库把所有绕过登录的 Hook 收敛到 **`DYYYLoginBypass.xm`** 单一文件，并采用“仅在目标类真实存在时才安装 Hook”的守卫策略，避免类名变更导致整个 Tweak 崩溃。

若新版抖音下绕过登录不生效，请：

1. 用 `@interface` 反向工程工具（如 **FLEX**、**FlexDecrypt**、**choper** 或 **IDA/Hopper**）确认当前版本的登录相关类与方法名，例如：
   - 账户单例：`AWEAccountManager` / `AWEUserAccount` 的 `isLogin`、`hasLogin`
   - 登录页 VC：`AWELoginViewController`、`AWEPhoneLoginViewController`、`AWENormalLoginViewController` 等
2. 在 `DYYYLoginBypass.xm` 中按注释更新对应分组的类名与方法名（集中在文件顶部与 `%group` 内，改动点很少）。
3. 重新执行第 3 步构建。

> 若某类名被改，对应分组因 `%init` 守卫不会命中——仅该部分失效，不会让 Tweak 整体崩溃。
