# HarmonyOS Command Line Tools Docker 镜像

基于 Ubuntu 26.04 的 Docker 镜像，预装鸿蒙 **Command Line Tools** 及其完整构建依赖环境（JDK 21、内置 Node.js、ohpm、hvigorw、hdc、hap-sign-tool 等），开箱即用，可直接在本地或 CI 中构建 HarmonyOS 应用。

## 镜像内已预装内容

| 组件 | 说明 |
|------|------|
| Command Line Tools | 解压于 `/opt/command-line-tools` |
| JDK 21 | `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64` |

**仓库源配置**（均可通过 `--build-arg` 覆盖）：

| 配置 | 默认值 | 覆盖参数 |
|------|--------|----------|
| ohpm 仓库 | `https://ohpm.openharmony.cn/ohpm/` | `OHPM_REGISTRY` |
| npm 镜像 | `https://repo.huaweicloud.com/repository/npm/` | `NPM_REGISTRY` |
| @ohos npm scope | `https://repo.harmonyos.com/npm/` | `OHOS_NPM_REGISTRY` |

> 若工程在 `hvigor/hvigor-config.json5` 中依赖 npm 三方组件，需配置 npm 镜像地址（镜像已预设默认值）。

**其他信息**：默认工作目录 `/workspace`；默认 root 运行（兼容 CI），镜像内含 `harmony` 非 root 用户可用 `--user harmony` 指定。

## 前置条件

1. **Docker**：19.03+，支持 `--platform`。因 Dockerfile 使用 BuildKit `--mount` 特性，建议 Docker 23.0+（默认启用 BuildKit）或使用 `docker buildx build`。
2. **Command Line Tools 压缩包**：从[华为开发者官网](https://developer.huawei.com/consumer/cn/download/)（HarmonyOS 应用开发 -> Command Line Tools）下载 **Linux 版** 压缩包（建议 26.0.0 及以上版本），重命名或复制为 `commandline-tools-linux-x64.zip` 放置到项目根目录（可用 `--build-arg CLT_ZIP_FILENAME=<文件名>` 指定其他文件名）。

## 构建镜像

```bash
# 基本构建
docker build --build-arg CLT_ZIP_FILENAME=commandline-tools-linux-x64.zip -t harmonyos-clt:latest .

# 指定名称、标签，禁用缓存
docker build --build-arg CLT_ZIP_FILENAME=commandline-tools-linux-x64.zip \
  --no-cache -t harmonyos-clt:26.0.0.821 .

# 覆盖仓库源（内网/镜像源场景）
docker build --build-arg CLT_ZIP_FILENAME=commandline-tools-linux-x64.zip \
  --build-arg NPM_REGISTRY=https://your-mirror/npm/ \
  --build-arg OHPM_REGISTRY=https://your-mirror/ohpm/ \
  -t harmonyos-clt:latest .
```

> 首次构建需下载基础镜像与 apt 依赖，并解压约 2.3GB 的 CLT 压缩包，耗时较长。
> 镜像构建方式：使用 `--mount=type=bind` 挂载解压 zip，zip 不写入镜像层（减小体积），因此需 BuildKit。

## 验证镜像

```bash
docker run --rm -it harmonyos-clt:latest bash
```

进入容器后执行：

```bash
java -version   # 期望输出 JDK 21
node -v         # 期望输出 Node 版本 (>=18)
ohpm -v         # 期望输出 ohpm 版本
hvigorw -v      # 期望输出 hvigor 版本
hdc -v          # 期望输出 hdc 版本
```

## 推送镜像

构建与推送分离：先本地构建验证，确认无误后再推送。未指定仓库时使用 docker 默认 registry（如 Docker Hub）；推送到自定义仓库需先 `docker tag`。

```bash
# 推送到 docker 默认 registry (如 Docker Hub)
docker push harmonyos-clt:latest

# 推送到自定义仓库
docker tag harmonyos-clt:latest registry.example.com/harmonyos-clt:latest
docker push registry.example.com/harmonyos-clt:latest
```

> push 前需先 `docker login` 登录目标仓库。

## 常用命令速查

```bash
# 构建镜像
docker build --build-arg CLT_ZIP_FILENAME=commandline-tools-linux-x64.zip -t harmonyos-clt:latest .

# 进入容器交互
docker run --rm -it harmonyos-clt:latest bash

# 以非 root 用户运行 (安全模式)
docker run --rm -it --user harmony harmonyos-clt:latest bash

# 在容器内直接构建某 HarmonyOS 工程 (挂载宿主目录)
docker run --rm -v /path/to/project:/workspace harmonyos-clt:latest bash -c "cd /workspace && ohpm install --all && hvigorw assembleHap --mode module -p product=default -p buildMode=debug --no-daemon"
```

## 常见问题 FAQ

### Q1: 构建时报 "Command Line Tools 压缩包不存在"？

确认压缩包已下载并放置到项目根目录，文件名与默认值 `commandline-tools-linux-x64.zip` 一致，或使用 `--build-arg CLT_ZIP_FILENAME=<文件名>` 指定。

### Q2: 如何升级镜像中的 Command Line Tools 版本？

重新下载新版压缩包，覆盖项目根目录同名文件后重新执行 `docker build` 即可（建议加 `--no-cache` 避免旧层缓存）。

### Q3: 离线环境（内网）下能否使用？

可以。镜像构建时已本地安装全部工具链（SDK 随压缩包一起打包），构建产物不含网络下载的 SDK。只需在内网拉取/推送镜像即可。ohpm/npm 依赖下载仍需在运行时能访问相应仓库。

### Q4: 镜像体积较大？

镜像包含完整 JDK、Node.js 与 Command Line Tools（内嵌 SDK 约 6GB），体积较大属正常现象。构建时已使用 `--no-install-recommends` 清理 apt 缓存，并通过 BuildKit bind mount 避免 zip 写入镜像层，尽量减小体积。

### Q5: 如何以非 root 用户运行容器？

镜像默认以 root 运行（兼容 CI）。如需以非 root 运行：

```bash
docker run --rm -it --user harmony harmonyos-clt:latest bash
```

注意：挂载目录的读写权限需自行控制（`/workspace` 已授权给 `harmony` 用户）。

## 许可与免责

本镜像仅用于 HarmonyOS 应用构建场景，Command Line Tools 及相关组件的版权归其权利人所有。请遵循华为开发者平台的许可协议。