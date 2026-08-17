# Keep the system/runtime baseline identical to the previously deployed image.
# This digest is the linux/amd64 image that backed 2026.7.1-2-slim on containernode.
FROM ghcr.io/openclaw/openclaw@sha256:8789721d2e9b24b780a1504b56deb4c6bd5c7dbf96a1dd117e7c45c2ed72c8ac AS package-install

USER root
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --omit=dev \
    && test "$(node -p "require('./node_modules/openclaw/package.json').version")" = "2026.8.1-beta.2" \
    && mkdir -p /runtime \
    && cp -a node_modules/openclaw/. /runtime/ \
    && cp -a node_modules /runtime/node_modules \
    && rm -rf /runtime/node_modules/openclaw

FROM ghcr.io/openclaw/openclaw@sha256:8789721d2e9b24b780a1504b56deb4c6bd5c7dbf96a1dd117e7c45c2ed72c8ac

USER root
RUN find /app -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
COPY --from=package-install --chown=node:node /runtime/ /app/
RUN ln -sfn /app /app/node_modules/openclaw \
    && ln -sfn /app/openclaw.mjs /usr/local/bin/openclaw \
    && chmod 0755 /app/openclaw.mjs \
    && test "$(node -p "require('/app/package.json').version")" = "2026.8.1-beta.2"

LABEL org.opencontainers.image.title="OpenClaw for containernode" \
      org.opencontainers.image.version="2026.8.1-beta.2" \
      org.opencontainers.image.base.name="ghcr.io/openclaw/openclaw@sha256:8789721d2e9b24b780a1504b56deb4c6bd5c7dbf96a1dd117e7c45c2ed72c8ac" \
      org.opencontainers.image.description="Pinned openclaw@2026.8.1-beta.2 installed over the previous containernode runtime baseline"

USER node
WORKDIR /app
