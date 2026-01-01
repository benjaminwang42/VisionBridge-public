#!/bin/sh

mkdir -p /root/.android
if [ -n "$ADB_PRIVATE_KEY" ] && [ -n "$ADB_PUBLIC_KEY" ]; then
    echo "=== Setting up ADB keys ==="
    printf '%s\n' "$ADB_PRIVATE_KEY" > /root/.android/adbkey
    printf '%s\n' "$ADB_PUBLIC_KEY" > /root/.android/adbkey.pub
    
    chmod 600 /root/.android/adbkey
    chmod 644 /root/.android/adbkey.pub

    echo "=== Verifying ADB key format ==="
    if head -n 1 /root/.android/adbkey | grep -q "BEGIN.*PRIVATE KEY"; then
        echo "✓ Private key format looks correct"
    else
        echo "⚠ WARNING: Private key may be malformed"
        echo "Actual First line: $(head -n 1 /root/.android/adbkey)"
    fi

    if [ -f /root/.android/adbkey.pub ]; then
        echo "Public key first 50 chars: $(head -c 50 /root/.android/adbkey.pub)"
    fi
    
    if [ -f /root/.android/adbkey ] && [ -f /root/.android/adbkey.pub ]; then
        PRIVATE_KEY_SIZE=$(wc -c < /root/.android/adbkey)
        PUBLIC_KEY_SIZE=$(wc -c < /root/.android/adbkey.pub)
        echo "✓ ADB keys written successfully (private: ${PRIVATE_KEY_SIZE} bytes, public: ${PUBLIC_KEY_SIZE} bytes)"
        PUBLIC_KEY_PREVIEW=$(head -c 50 /root/.android/adbkey.pub)
        echo "   Public key preview: ${PUBLIC_KEY_PREVIEW}..."
    else
        echo "⚠ WARNING: ADB keys may not have been written correctly"
    fi
else
    echo "⚠ WARNING: ADB_PRIVATE_KEY or ADB_PUBLIC_KEY not set - device authorization may be required"
fi

if [ -n "$TAILSCALE_AUTHKEY" ]; then
    echo "=== Starting Tailscale ==="
    
    if echo "$TAILSCALE_AUTHKEY" | grep -q "^tskey-"; then
        echo "✓ Auth key format appears valid"
    else
        echo "⚠ WARNING: Auth key format may be invalid"
    fi
    
    mkdir -p /var/lib/tailscale
    tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
    TAILSCALED_PID=$!
    
    for i in 1 2 3 4 5; do
        if kill -0 $TAILSCALED_PID 2>/dev/null; then
            sleep 1
        else
            echo "ERROR: tailscaled process died unexpectedly"
            exit 1
        fi
    done
    
    echo "Testing network connectivity to Tailscale control server..."
    if curl -s --max-time 5 https://controlplane.tailscale.com > /dev/null 2>&1; then
        echo "✓ Network connectivity to Tailscale control server: OK"
    else
        echo "⚠ WARNING: Cannot reach Tailscale control server"
    fi
    
    MAX_RETRIES=5
    RETRY_COUNT=0
    AUTH_SUCCESS=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Attempting Tailscale authentication (attempt $RETRY_COUNT/$MAX_RETRIES)..."
        AUTH_OUTPUT=$(tailscale up --authkey="${TAILSCALE_AUTHKEY}" --hostname=railway-service --accept-dns=false 2>&1)
        AUTH_EXIT_CODE=$?
        
        if [ $AUTH_EXIT_CODE -eq 0 ]; then
            echo "Tailscale authentication command completed successfully"
            sleep 5
            if tailscale status > /dev/null 2>&1; then
                echo "✓ Tailscale connected successfully!"
                AUTH_SUCCESS=true
                break
            else
                echo "Authentication command succeeded but status check failed, retrying..."
                tailscale status || true
            fi
        else
            echo "Authentication attempt $RETRY_COUNT failed (exit code: $AUTH_EXIT_CODE)"
            echo "Error output: $AUTH_OUTPUT"
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                WAIT_TIME=$((RETRY_COUNT * 3))
                echo "Waiting ${WAIT_TIME} seconds before retry..."
                sleep $WAIT_TIME
            fi
        fi
    done
    
    if [ "$AUTH_SUCCESS" = false ]; then
        echo "ERROR: Tailscale authentication failed after $MAX_RETRIES attempts"
        exit 1
    fi
    
    sleep 3
    
    if [ -n "$PHONE_IP" ]; then
        echo "=== Connecting to ADB device: ${PHONE_IP} ==="
        adb kill-server 2>/dev/null || true
        sleep 2
        
        proxychains4 -f /etc/proxychains4.conf adb start-server
        proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP}
        
        MAX_AUTH_RETRIES=10
        AUTH_RETRY_COUNT=0
        DEVICE_AUTHORIZED=false
        
        while [ $AUTH_RETRY_COUNT -lt $MAX_AUTH_RETRIES ]; do
            AUTH_RETRY_COUNT=$((AUTH_RETRY_COUNT + 1))
            sleep 3
            DEVICE_STATUS=$(proxychains4 -f /etc/proxychains4.conf adb devices | grep "${PHONE_IP}" || echo "")
            
            if echo "$DEVICE_STATUS" | grep -q "device$"; then
                echo "✓ ADB connected and authorized successfully"
                DEVICE_AUTHORIZED=true
                break
            elif echo "$DEVICE_STATUS" | grep -q "unauthorized"; then
                echo "⚠ Device is connected but unauthorized (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES)"
                if [ -f /root/.android/adbkey.pub ]; then
                    head -c 100 /root/.android/adbkey.pub | tr -d '\n'
                    echo ""
                fi
                proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP} > /dev/null 2>&1
            elif echo "$DEVICE_STATUS" | grep -q "offline"; then
                echo "⚠ Device is offline (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES), reconnecting..."
                proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP} > /dev/null 2>&1
            elif [ -z "$DEVICE_STATUS" ]; then
                echo "⚠ Device not found (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES), reconnecting..."
                proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP} > /dev/null 2>&1
            fi
        done
        
        echo ""
        echo "Final ADB device status:"
        proxychains4 -f /etc/proxychains4.conf adb devices
        
        if [ "$DEVICE_AUTHORIZED" = false ]; then
            echo ""
            echo "⚠ WARNING: ADB device is not authorized or not connected"
        fi
    fi
else
    echo "ERROR: TAILSCALE_AUTHKEY not provided"
    exit 1
fi

echo "=== Starting FastAPI application ==="
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}