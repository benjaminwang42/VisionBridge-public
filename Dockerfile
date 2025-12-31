FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    curl \
    android-tools-adb \
    iproute2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

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