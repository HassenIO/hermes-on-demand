# Hermes Docker terminal image with Agent-Reach zero-config CLIs.
# Built on the VPS by scripts/remote/agent-reach-up.sh
# Upstream: https://github.com/Panniantong/Agent-Reach
# Base adds the Bot Desktop stack (Xvnc, xfce, Chromium) that Hermes browser_* needs in the sandbox.
FROM nousresearch/hermes-sandbox:desktop

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

# AWS CLI v2 (official installer) so the agent can use S3 with the forwarded AWS_* keys
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip \
  && unzip -q /tmp/awscliv2.zip -d /tmp \
  && /tmp/aws/install \
  && rm -rf /tmp/aws /tmp/awscliv2.zip \
  && aws --version

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

# Hermes runs agent-browser by name inside the sandbox; desktop images after v0.21 no longer bake it in.
# Keep in step with agent-browser in /opt/hermes/pm/lock.json.
ARG AGENT_BROWSER_VERSION=0.26.0
RUN npm install -g --ignore-scripts --no-audit --fetch-retries=5 "agent-browser@${AGENT_BROWSER_VERSION}" \
  && agent-browser --version

# Claude Code CLI for the bundled claude-code skill. Auth comes from CLAUDE_CODE_OAUTH_TOKEN
# via terminal.docker_forward_env. Pinned; the in-container auto-updater stays off.
ARG CLAUDE_CODE_VERSION=2.1.319
ENV DISABLE_AUTOUPDATER=1
RUN npm install -g --no-audit --fetch-retries=5 "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  && claude --version

# Config dir mounted from host at runtime
RUN mkdir -p /root/.agent-reach && chmod 700 /root/.agent-reach

WORKDIR /workspace
