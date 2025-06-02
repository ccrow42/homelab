FROM debian:bullseye

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y postfix procps vim && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


# Override with your config
COPY entrypoint.sh /entrypoint.sh
#COPY rsyslog.conf /etc/rsyslog.conf
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
