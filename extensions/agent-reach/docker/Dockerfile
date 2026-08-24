# Hermes Docker terminal image with Agent-Reach zero-config CLIs.
# Built on the VPS by scripts/remote/agent-reach-up.sh
# Upstream: https://github.com/Panniantong/Agent-Reach
FROM nikolaik/python-nodejs:python3.11-nodejs20

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    npm_config_update_notifier=false

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       ca-certificates curl git gnupg unzip \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# Agent-Reach from GitHub (NOT the unrelated PyPI name) + zero-config deps
ARG AGENT_REACH_REF=main
RUN python3 -m pip install --upgrade pip \
  && python3 -m pip install \
       "https://github.com/Panniantong/agent-reach/archive/${AGENT_REACH_REF}.zip" \
       "yt-dlp[default]" \
       feedparser \
  && python3 -m pip install \
       "git+https://github.com/public-clis/bilibili-cli.git" \
  && npm install -g mcporter \
  && agent-reach --help >/dev/null \
  && yt-dlp --version \
  && gh --version \
  && mcporter --help >/dev/null 2>&1 || true \
  && (bili --help >/dev/null 2>&1 || bili-cli --help >/dev/null 2>&1 || true)

# Config dir mounted from host at runtime
RUN mkdir -p /root/.agent-reach && chmod 700 /root/.agent-reach

WORKDIR /workspace
