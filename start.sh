#!/bin/sh

mkdir -p /root/.android
echo "$ADB_PRIVATE_KEY" > /root/.android/adbkey
echo "$ADB_PUBLIC_KEY" > /root/.android/adbkey.pub
chmod 600 /root/.android/adbkey
chmod 644 /root/.android/adbkey.pub

tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
tailscale up --authkey=${TAILSCALE_AUTH_KEY} --hostname=railway-service --accept-dns=false

sleep 5
export ALL_PROXY=socks5://localhost:1055/

adb connect ${PHONE_IP}:5555

cd /app
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}