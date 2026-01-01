FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    curl \
    android-tools-adb \
    iproute2 \
    ca-certificates \
    proxychains4 \
    netcat-openbsd \
    socat \
    && rm -rf /var/lib/apt/lists/*

RUN printf "strict_chain\n\
proxy_dns\n\
remote_dns_subnet 224\n\
tcp_read_time_out 30000\n\
tcp_connect_time_out 30000\n\
[ProxyList]\n\
socks5 127.0.0.1 1055\n" > /etc/proxychains4.conf

RUN curl -fsSL https://tailscale.com/install.sh | sh

RUN mkdir -p /var/lib/tailscale
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY start.sh /start.sh
RUN chmod +x /start.sh
COPY . .
RUN chmod +x /app/app/socks_forwarder.py

ENV PORT=8080
EXPOSE 8080

CMD ["/start.sh"]