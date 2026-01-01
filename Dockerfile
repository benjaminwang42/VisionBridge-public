FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    curl \
    android-tools-adb \
    iproute2 \
    ca-certificates \
    proxychains4 \
    && rm -rf /var/lib/apt/lists/*

RUN echo "strict_chain\nproxy_dns\nremote_dns_subnet 224\ntcp_read_time_out 15000\ntcp_connect_time_out 8000\n[ProxyList]\nsocks5 127.0.0.1 1055" > /etc/proxychains4.conf

RUN curl -fsSL https://tailscale.com/install.sh | sh

RUN mkdir -p /var/lib/tailscale
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY start.sh /start.sh
RUN chmod +x /start.sh
COPY . .

ENV PORT=8080
EXPOSE 8080

CMD ["/start.sh"]