FROM ubuntu:resolute-20260413

ARG USER_ID
ARG GROUP_ID

ENV MISE_INSTALL_PATH="/usr/local/bin/mise"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get -y --no-install-recommends install \
       curl git ca-certificates build-essential \
       squid gosu iptables \
    && rm -rf /var/lib/apt/lists/*

RUN if ! getent group ${GROUP_ID} > /dev/null 2>&1; then \
    groupadd -g ${GROUP_ID} dev \
;fi

RUN if ! getent passwd ${USER_ID} > /dev/null 2>&1; then \
    useradd -m -l -u ${USER_ID} -g ${GROUP_ID} --shell /bin/bash dev \
;fi

RUN mkdir -p /workspace
# precreate directory where we mount the volume for opencode and setup permissions for the dev user
# otherwise the directory will be created by root when mounting and the dev user won't have permissions to write to it
RUN mkdir -p /home/dev/.local/share
RUN chown -R ${USER_ID}:${GROUP_ID} /workspace /home/dev/.local

RUN curl https://mise.run | sh

RUN mkdir -p /etc/mise/
COPY mise.toml /etc/mise/config.toml
RUN chmod ugo+r /etc/mise/config.toml
RUN mise install --system

# Squid proxy configuration
COPY squid.conf /etc/squid/squid.conf
COPY opencode-sandbox-firewall /etc/squid/opencode-sandbox-firewall

COPY opencode-password /opencode-password
COPY entrypoint.sh /entrypoint.sh
RUN chown ${USER_ID}:${GROUP_ID} /opencode-password
RUN chmod +x /entrypoint.sh

# Run as root so entrypoint can start squid and configure iptables,
# then switches to the dev user via gosu before starting opencode.
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
