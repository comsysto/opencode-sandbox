FROM ubuntu:resolute-20260413

ARG USER_ID
ARG GROUP_ID
ARG OPENCODE_PASSWORD

ENV MISE_INSTALL_PATH="/usr/local/bin/mise"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get -y --no-install-recommends install curl git ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN if ! getent group ${GROUP_ID} > /dev/null 2>&1; then \
    groupadd -g ${GROUP_ID} dev \
;fi

RUN if ! getent passwd ${USER_ID} > /dev/null 2>&1; then \
    useradd -m -l -u ${USER_ID} -g ${GROUP_ID} --shell /bin/bash dev \
;fi

RUN mkdir -p /workspace
RUN chown -R ${USER_ID}:${GROUP_ID} /workspace

RUN curl https://mise.run | sh

RUN mkdir -p /etc/mise/
COPY mise.toml /etc/mise/config.toml
RUN mise install --system

COPY opencode-password /opencode-password
COPY entrypoint.sh /entrypoint.sh
RUN chown -R ${USER_ID}:${GROUP_ID} /entrypoint.sh /opencode-password
RUN chmod +x /entrypoint.sh

USER ${USER_ID}
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]