#!/bin/sh

mkdir -p /root/.android
if [ -n "$ADB_PRIVATE_KEY" ] && [ -n "$ADB_PUBLIC_KEY" ]; then
    echo "$ADB_PRIVATE_KEY" > /root/.android/adbkey
    echo "$ADB_PUBLIC_KEY" > /root/.android/adbkey.pub
    chmod 600 /root/.android/adbkey
    chmod 644 /root/.android/adbkey.pub
fi

tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
sleep 5

tailscale up --authkey="${TAILSCALE_AUTHKEY}" --hostname=railway-service --accept-dns=false
sleep 5

if [ -n "$PHONE_IP" ]; then
    adb kill-server 2>/dev/null || true
    proxychains4 -f /etc/proxychains4.conf adb start-server
    proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP}:5555
fi

exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080}