FROM alpine:latest

# Install OpenSSH, Rsync, Supervisor, and Bash
RUN apk add --no-cache openssh rsync bash

# Setup SSH directories and generate host keys
RUN mkdir -p /var/run/sshd /root/.ssh && \
    chmod 700 /root/.ssh

# Copy configuration files
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]