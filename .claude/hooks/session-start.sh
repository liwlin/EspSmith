#!/bin/bash
# SessionStart hook for Claude Code on the web.
# 安装前端 npm 依赖并预取 Rust cargo 依赖,使 web 沙箱中可直接构建/测试。
#
# 镜像源说明:仓库为本地(国内)开发配置了 npmmirror(package-lock.json)
# 和 rsproxy(src-tauri/.cargo/config.toml)镜像。本钩子仅在云端容器中、
# 且实际检测到镜像不可达时,才通过环境变量 / 容器内临时文件把镜像重定向
# 回官方源 —— 不修改任何提交到仓库的配置文件,本地开发不受影响。
set -uo pipefail

# 仅在远程(web)执行环境中运行
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

warn() { echo "[session-start] $*" >&2; }

session_env() {
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "$1" >> "$CLAUDE_ENV_FILE"
  fi
}

mirror_reachable() {
  curl -sf --max-time 5 -o /dev/null "$1"
}

# --- npm:npmmirror 不可达时改用官方 registry ----------------------------
# replace-registry-host=always 会把 lockfile 中记录的镜像下载地址也替换为
# 当前 registry 的 host,因此无需改动 package-lock.json。
if ! mirror_reachable "https://registry.npmmirror.com/react"; then
  warn "registry.npmmirror.com 不可达,npm 本会话临时改用官方 registry"
  export npm_config_registry="https://registry.npmjs.org/"
  export npm_config_replace_registry_host="always"
  session_env 'export npm_config_registry="https://registry.npmjs.org/"'
  session_env 'export npm_config_replace_registry_host="always"'
fi

# --- cargo:rsproxy 不可达时重定向回官方 crates.io ------------------------
# cargo 的 [source] 替换表无法用环境变量覆盖(CARGO_SOURCE_* 不生效),
# 只能用 --config 命令行参数。这里在容器家目录(非仓库内)生成一个注入
# 该参数的 cargo 包装脚本,并将其加入本会话 PATH。
if ! mirror_reachable "https://rsproxy.cn/index/config.json"; then
  warn "rsproxy.cn 不可达,cargo 本会话临时重定向到官方 crates.io"
  SHIM_DIR="$HOME/.cache/claude-cargo-shim"
  REAL_CARGO="$(command -v cargo || echo "$HOME/.cargo/bin/cargo")"
  mkdir -p "$SHIM_DIR"
  cat > "$SHIM_DIR/cargo" <<EOF
#!/bin/bash
exec "$REAL_CARGO" \\
  --config 'source.crates-io.replace-with="official"' \\
  --config 'registries.official.index="sparse+https://index.crates.io/"' \\
  "\$@"
EOF
  chmod +x "$SHIM_DIR/cargo"
  export PATH="$SHIM_DIR:$PATH"
  session_env "export PATH=\"$SHIM_DIR:\$PATH\""
fi

# --- 依赖安装(失败只告警,不阻断会话启动) -------------------------------
if ! npm install; then
  warn "npm install 失败,会话照常启动;可在会话中手动重试"
fi

if ! cargo fetch --manifest-path src-tauri/Cargo.toml; then
  warn "cargo fetch 失败,会话照常启动;首次 cargo 构建时会重新下载依赖"
fi

echo "[session-start] 环境准备完成"
exit 0
