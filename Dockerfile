FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    curl \
    android-tools-adb \
    && rm -rf /var/lib/apt/lists/*

# need to install tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]