# ================================================================
# HarmonyOS Command Line Tools Docker 镜像
# ----------------------------------------------------------------
# 功能: 预装鸿蒙 Command Line Tools 及其完整构建依赖环境
#       (JDK 21 / 内置 Node.js / ohpm / hvigorw / hdc / 签名工具),
#       可直接在 GitCode 流水线中自动化构建 HarmonyOS 应用。
# 构建前提: 将 Command Line Tools Linux 版压缩包放置于构建上下文根目录
#       (默认文件名 commandline-tools-linux-x64.zip, 可用 --build-arg 覆盖)。
# ================================================================

# ============ 阶段 1: 基础镜像 (Ubuntu 26.04, amd64, GLIBC>=2.28) ============
# 说明: 本镜像仅支持 amd64，用 ARG 而非常量写 --platform, 以消除 BuildKit FromPlatformFlagConstDisallowed warning。
# 注意不用预定义的 $TARGETPLATFORM (会报 RedundantTargetPlatform)，故用自定义变量名。
ARG IMAGE_PLATFORM=linux/amd64
FROM --platform=$IMAGE_PLATFORM ubuntu:26.04

# ============ 阶段 2: 时区 / 语言 / 字符集 ============
# 时区 Asia/Shanghai, 语言 en_US.UTF-8
ENV TZ=Asia/Shanghai \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# ============ 阶段 3: 安装系统基础依赖 ============
# 安装 libgl1-mesa-dev 以支持纹理压缩; 安装 JDK 21;
#         安装 apt-utils/curl/wget/git/zip/unzip 等基础工具。
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list.d/ubuntu.sources \
    && sed -i 's@//.*security.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends \
        apt-utils \
        curl \
        wget \
        git \
        zip \
        unzip \
        ca-certificates \
        libgl1-mesa-dev \
        pkg-config \
        build-essential \
        libgl1-mesa-dev \
        libatomic1 \
        locales \
        openjdk-21-jdk-headless \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============ 阶段 4: 解压安装 Command Line Tools (BuildKit bind mount) ============
# 使用 BuildKit bind mount 将压缩包挂载进构建过程直接解压:
#   - zip 不写入任何镜像层 (否则 COPY 层即使后续删除仍占用 ~2.35GB)
#   - 需 Docker 23.0+ (默认启用 BuildKit) 或 docker buildx build
# 注意: 压缩包内含顶层 command-line-tools 目录, 直接解压到 /opt,
#       最终 Command Line Tools 根目录为 /opt/command-line-tools。
ARG CLT_ZIP_FILENAME=commandline-tools-linux-x64.zip
RUN --mount=type=bind,source=${CLT_ZIP_FILENAME},target=/tmp/clt-build.zip \
    unzip -q /tmp/clt-build.zip -d /opt

# ============ 阶段 4b: BiSheng 原生工具链兼容库 (Issue #1) ============
# 背景: BiSheng 的 lld (即 ld.lld) 依赖 libxml2.so.2, 而 Ubuntu 26.04 仅提供
#       libxml2.so.16, 且默认不再安装任何 libxml2, 导致 C++ 原生工程 CMake 检测失败。
#       详见 https://github.com/springtwr/harmonyos-clt/issues/1
# 做法: 临时借用 Ubuntu 24.04 (noble) 源, 仅下载 (不安装) libxml2 与 libicu74,
#       解开后只取 3 个库文件放入 /opt/compat-lib, 经 ldconfig 注册,
#       运行时无需 LD_LIBRARY_PATH, 也不影响系统自带的 libxml2.so.16。
# 说明: 仅 download 不 install, 不会污染 26.04 系统包; 不写死版本号, 每次构建自动
#       跟进 noble-security 最新 (LTS 内 soname 冻结, 构建日志打印实际版本以备追溯)。
# 维护: 若新版 BiSheng 新增系统依赖, 阶段 8 的 ldd 门禁会在构建时报错,
#       按此配方把包名加入 download 列表并补充 cp 即可。
RUN echo 'deb https://mirrors.ustc.edu.cn/ubuntu noble main universe' > /etc/apt/sources.list.d/noble-compat.list \
    && echo 'deb https://mirrors.ustc.edu.cn/ubuntu noble-updates main universe' >> /etc/apt/sources.list.d/noble-compat.list \
    && echo 'deb https://mirrors.ustc.edu.cn/ubuntu noble-security main universe' >> /etc/apt/sources.list.d/noble-compat.list \
    && apt-get update -y \
    && mkdir -p /tmp/compat-dl \
    && ( cd /tmp/compat-dl && apt-get download libxml2 libicu74 ) \
    && echo "--- 兼容库 .deb 版本 ---" \
    && dpkg-deb -f /tmp/compat-dl/libxml2_*.deb Package Version \
    && dpkg-deb -f /tmp/compat-dl/libicu74_*.deb Package Version \
    && mkdir -p /tmp/compat-x1 /tmp/compat-x2 /opt/compat-lib \
    && dpkg-deb -x /tmp/compat-dl/libxml2_*.deb /tmp/compat-x1 \
    && dpkg-deb -x /tmp/compat-dl/libicu74_*.deb /tmp/compat-x2 \
    && cp -L /tmp/compat-x1/usr/lib/x86_64-linux-gnu/libxml2.so.2 \
             /tmp/compat-x2/usr/lib/x86_64-linux-gnu/libicuuc.so.74 \
             /tmp/compat-x2/usr/lib/x86_64-linux-gnu/libicudata.so.74 \
             /opt/compat-lib/ \
    && echo '/opt/compat-lib' > /etc/ld.so.conf.d/bisheng-compat.conf \
    && ldconfig \
    && rm -f /etc/apt/sources.list.d/noble-compat.list \
    && rm -rf /tmp/compat-dl /tmp/compat-x1 /tmp/compat-x2 \
    && rm -rf /var/lib/apt/lists/* \
    && echo "--- 兼容库内容 ---" && ls -lh /opt/compat-lib/

# ============ 阶段 5: 配置环境变量 (依据鸿蒙官方文档 Linux 路径) ============
# JAVA_HOME / NODE_HOME / HDC_HOME / HAP_SIGN_TOOL_PATH / PATH
ENV COMMANDLINE_TOOL_DIR=/opt/command-line-tools \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    NODE_HOME=/opt/command-line-tools/tool/node \
    HDC_HOME=/opt/command-line-tools/sdk/default/openharmony/toolchains \
    HAP_SIGN_TOOL_PATH=/opt/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar \
    PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:/opt/command-line-tools/tool/node/bin:/opt/command-line-tools/sdk/default/openharmony/toolchains:/opt/command-line-tools/bin:$PATH

# ============ 阶段 6: 工作目录 + ohpm 仓库配置 ============
# 预设 ohpm 仓库地址, 默认使用官方 ohpm 仓库,
#         可用 --build-arg OHPM_REGISTRY=xxx 覆盖。
# 注: 新版 Command Line Tools 已内嵌 HarmonyOS SDK, SDK 管理能力集成于
#     hvigor 插件 @ohos/hos-sdkmanager-common, 无需独立 sdkmgr 及国家码设置。
WORKDIR /workspace

ARG OHPM_REGISTRY=https://ohpm.openharmony.cn/ohpm/
ENV OHPM_REGISTRY=${OHPM_REGISTRY}
RUN ohpm config set registry ${OHPM_REGISTRY}

# ============ 阶段 6b: npm 镜像仓库配置 ============
# 若工程在 hvigor/hvigor-config.json5 中依赖 npm 三方组件,
# 流水线中需配置 npm 镜像地址才能正确下载 (官方"搭建流水线"文档要求)。
# 默认华为云 npm 镜像 + HarmonyOS @ohos scope 镜像,
# 可用 --build-arg NPM_REGISTRY / OHOS_NPM_REGISTRY 覆盖。
ARG NPM_REGISTRY=https://repo.huaweicloud.com/repository/npm/
ARG OHOS_NPM_REGISTRY=https://repo.harmonyos.com/npm/
ENV NPM_REGISTRY=${NPM_REGISTRY} \
    OHOS_NPM_REGISTRY=${OHOS_NPM_REGISTRY}
RUN npm config set registry ${NPM_REGISTRY} --location=global \
    && npm config set "@ohos:registry" ${OHOS_NPM_REGISTRY} --location=global \
    && echo "--- npm 全局配置 ---" && npm config get registry && npm config get "@ohos:registry"

# ============ 阶段 7: 非 root 运行用户 (安全最佳实践) ============
# 说明: GitCode 等 CI 容器环境通常以 root 运行, 故默认保持 root 用户,
#       以兼容 CI 场景; 如需以非 root 运行, 可在 docker run 时指定
#       --user harmony (构建阶段仍使用 root 安装所有依赖)。
RUN useradd -m -s /bin/bash harmony \
    && chown -R harmony:harmony /workspace

# ============ 阶段 8: 构建验证 ============
# 确认 java / node / ohpm / hvigorw / hdc 均可用且版本信息正确输出。
# 另含 BiSheng 原生工具链 ldd 回归门禁 (Issue #1): 逐个检查 BiSheng/bin 下所有文件,
# 若有缺失的系统依赖则构建失败, 防止基础镜像升级或 BiSheng 更新引入新的缺库问题。
RUN echo "===== Java =====" && java -version \
    && echo "===== Node =====" && node -v \
    && echo "===== ohpm =====" && ohpm -v \
    && echo "===== hvigorw =====" && hvigorw -v \
    && echo "===== hdc =====" && hdc -v \
    && echo "===== CLT 目录内容 =====" && ls ${COMMANDLINE_TOOL_DIR} \
    && echo "===== BiSheng 原生工具链依赖门禁 =====" \
    && for bin in ${COMMANDLINE_TOOL_DIR}/sdk/default/hms/native/BiSheng/bin/*; do \
         if [ -f "${bin}" ]; then \
           absent=$(ldd "${bin}" 2>/dev/null | grep "not found" || true); \
           if [ -n "${absent}" ]; then echo "缺失依赖: ${bin}: ${absent}"; fail=1; fi; \
         fi; \
       done; \
       if [ "${fail:-0}" = "1" ]; then echo "ERROR: BiSheng 存在缺失的系统依赖"; exit 1; fi \
    && echo "BiSheng 依赖检查通过"
