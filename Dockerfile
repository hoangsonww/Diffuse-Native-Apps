# Toolbox for docs, git hooks, and agent workflows.
# Native apps and `swift test` require macOS + Xcode. This image does not
# replace that — it gives Linux and Codespaces a working checkout for
# everything that is not an Apple SDK.

FROM node:22-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        git \
        jq \
        make \
        python3 \
        python3-pip \
        shellcheck \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts \
    && npm cache clean --force

CMD ["bash"]
