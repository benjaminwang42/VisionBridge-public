#!/bin/sh

mkdir -p /root/.android

if [ -n "$ADB_PRIVATE_KEY" ] && [ -n "$ADB_PUBLIC_KEY" ]; then
    printf '%s' "$ADB_PRIVATE_KEY" | tr -d '\n\r ' | base64 -d > /root/.android/adbkey || exit 1
    chmod 600 /root/.android/adbkey

    printf '%s' "$ADB_PUBLIC_KEY" | tr -d '\n\r ' | base64 -d > /root/.android/adbkey.pub || exit 1
    chmod 644 /root/.android/adbkey.pub
fi

if [ -n "$TAILSCALE_AUTHKEY" ]; then
    mkdir -p /var/lib/tailscale
    tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
    sleep 2
    tailscale up --authkey="${TAILSCALE_AUTHKEY}" --hostname=railway-service --accept-dns=false || exit 1

    if [ -n "$PHONE_IP" ]; then
        PHONE_HOST=$(echo "${PHONE_IP}" | cut -d: -f1)
        PHONE_PORT=$(echo "${PHONE_IP}" | cut -d: -f2)

        FORWARD_LOCAL_PORT=5556
        python3 /app/app/socks_forwarder.py ${FORWARD_LOCAL_PORT} ${PHONE_HOST} ${PHONE_PORT} 127.0.0.1 1055 &
        FORWARDER_PID=$!
        sleep 2
        if ! kill -0 $FORWARDER_PID 2>/dev/null; then
            exit 1
        fi

        adb kill-server 2>/dev/null || true
        sleep 1
        adb start-server
        sleep 2

        export ADB_INSTALL_TIMEOUT=30
        FORWARDED_PHONE_IP="127.0.0.1:${FORWARD_LOCAL_PORT}"
        adb disconnect ${FORWARDED_PHONE_IP} 2>&1 || true
        sleep 1
        adb connect ${FORWARDED_PHONE_IP} 2>&1 || true
    fi
else
    exit 1
fi

exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
