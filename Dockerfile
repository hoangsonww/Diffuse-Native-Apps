# Toolbox for docs, git hooks, agent workflows, and the Android app.
#
# The Apple apps and `swift test` require macOS + Xcode; that is a licensing
# and platform constraint this image cannot work around. Everything else —
# the landing page, the docs, the hooks, and the full Android build — runs
# here, so Linux and Codespaces contributors get a working checkout.
#
# Android needs a JDK 17 and the SDK. Gradle can provision its own JDK from
# Android/gradle/gradle-daemon-jvm.properties, but shipping one keeps the
# first container build fast and works offline.

FROM node:22-bookworm-slim

ARG ANDROID_COMMAND_LINE_TOOLS_VERSION=11076708
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=35.0.0

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    JAVA_HOME=/opt/java/17

ENV PATH=${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        make \
        python3 \
        python3-pip \
        shellcheck \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Temurin JDK 17 from Adoptium, matching the vendor and version pinned in
# Android/gradle/gradle-daemon-jvm.properties.
RUN mkdir -p /etc/apt/keyrings \
    && curl --fail --silent --show-error --location https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" \
        > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends temurin-17-jdk \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /opt/java \
    && ln -s "$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")" /opt/java/17 \
    && "${JAVA_HOME}/bin/java" -version

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl --fail --location --retry 3 \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_COMMAND_LINE_TOOLS_VERSION}_latest.zip" \
        --output /tmp/android-tools.zip \
    && unzip -q /tmp/android-tools.zip -d /tmp/android-tools \
    && mv /tmp/android-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm -rf /tmp/android-tools /tmp/android-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${ANDROID_BUILD_TOOLS}" >/dev/null

WORKDIR /workspace

COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts \
    && npm cache clean --force

CMD ["bash"]
