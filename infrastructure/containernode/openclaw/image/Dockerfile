# Optional offline/custom-image fallback. The deployment uses the official image directly.
# This digest is the official 2026.10.7 image index; the linux/amd64 variant uses Node 24.22.1.
FROM ghcr.io/openclaw/openclaw@sha256:fb26f0841659dc757f23feec9adeab51f11d76779a409db5d22e191b43841afa AS package-install

USER root
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm_config_allow_remote=all npm_config_dangerously_allow_all_scripts=true npm ci --omit=dev \
    && test "$(node -p "require('./node_modules/openclaw/package.json').version")" = "2026.10.7" \
    && mkdir -p /runtime \
    && cp -a node_modules/openclaw/. /runtime/ \
    && cp -a node_modules /runtime/node_modules \
    && rm -rf /runtime/node_modules/openclaw

FROM ghcr.io/openclaw/openclaw@sha256:fb26f0841659dc757f23feec9adeab51f11d76779a409db5d22e191b43841afa

USER root
RUN find /app -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
COPY --from=package-install --chown=node:node /runtime/ /app/
RUN ln -sfn /app /app/node_modules/openclaw \
    && ln -sfn /app/openclaw.mjs /usr/local/bin/openclaw \
    && chmod 0755 /app/openclaw.mjs \
    && test "$(node -p "require('/app/package.json').version")" = "2026.10.7"

LABEL org.opencontainers.image.title="OpenClaw for containernode" \
      org.opencontainers.image.version="2026.10.7" \
      org.opencontainers.image.base.name="ghcr.io/openclaw/openclaw@sha256:fb26f0841659dc757f23feec9adeab51f11d76779a409db5d22e191b43841afa" \
      org.opencontainers.image.description="Pinned openclaw@2026.10.7 installed over the official Node 24.22.1 runtime baseline"

USER node
WORKDIR /app
