FROM ubuntu:resolute-20260413

ARG USER_ID
ARG GROUP_ID

ENV MISE_INSTALL_PATH="/usr/local/bin/mise"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get -y --no-install-recommends install \
       curl git ca-certificates build-essential \
       squid gosu iptables iproute2 \
    && rm -rf /var/lib/apt/lists/*

RUN if ! getent group ${GROUP_ID} > /dev/null 2>&1; then \
    groupadd -g ${GROUP_ID} dev \
;fi

RUN if ! getent passwd ${USER_ID} > /dev/null 2>&1; then \
    useradd -m -l -u ${USER_ID} -g ${GROUP_ID} --shell /bin/bash dev \
RUN existing_group=$(getent group ${GROUP_ID} | cut -d: -f1); \
    if [ -z "${existing_group}" ]; then \
      groupadd -g ${GROUP_ID} dev; \
    elif [ "${existing_group}" != "dev" ]; then \
      groupmod -n dev "${existing_group}"; \
    fi

RUN existing_user=$(getent passwd ${USER_ID} | cut -d: -f1); \
    if [ -z "${existing_user}" ]; then \
      useradd -m -l -u ${USER_ID} -g ${GROUP_ID} --shell /bin/bash dev; \
    elif [ "${existing_user}" != "dev" ]; then \
      usermod -l dev -d /home/dev -m "${existing_user}"; \
    fi


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

# Squid proxy configuration and domain whitelist
# squid-whitelist.txt is extracted from opencode-sandbox-firewall by ocs-rebuild-container
COPY squid.conf /etc/squid/squid.conf
COPY squid-whitelist.txt /etc/squid/squid-whitelist.txt
# Host TCP ports allowed through the firewall (one port number per line)
COPY host-ports.txt /etc/host-ports.txt

COPY opencode-password /opencode-password
COPY entrypoint.sh /entrypoint.sh
RUN chown ${USER_ID}:${GROUP_ID} /opencode-password
RUN chmod +x /entrypoint.sh

# Run as root so entrypoint can start squid and configure iptables,
# then switches to the dev user via gosu before starting opencode.
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
