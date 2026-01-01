#!/bin/sh

mkdir -p /root/.android

if [ -n "$ADB_PRIVATE_KEY" ] && [ -n "$ADB_PUBLIC_KEY" ]; then
    echo "=== Setting up ADB keys ==="
    
    if printf '%s' "$ADB_PRIVATE_KEY" | tr -d '\n\r ' | base64 -d > /root/.android/adbkey; then
        echo "✓ Successfully decoded ADB_PRIVATE_KEY"
        chmod 600 /root/.android/adbkey
    else
        echo "× ERROR: Failed to decode ADB_PRIVATE_KEY. Check your Base64 string."
        exit 1
    fi
    
    if printf '%s' "$ADB_PUBLIC_KEY" | tr -d '\n\r ' | base64 -d > /root/.android/adbkey.pub; then
        echo "✓ Successfully decoded ADB_PUBLIC_KEY"
        chmod 644 /root/.android/adbkey.pub
    else
        echo "× ERROR: Failed to decode ADB_PUBLIC_KEY."
        exit 1
    fi

    if head -n 1 /root/.android/adbkey | grep -q "BEGIN.*PRIVATE KEY"; then
        echo "✓ Private key format looks correct (PEM header found)"
    else
        echo "⚠ WARNING: Private key header missing. ADB might fail to use this key."
    fi
else
    echo "⚠ WARNING: ADB keys not provided - device authorization will likely fail."
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
    
    # Wait for Tailscale to fully establish routes
    echo "Waiting for Tailscale routes to stabilize..."
    sleep 5
    
    # Show Tailscale status for debugging
    echo "Tailscale status:"
    tailscale status || true
    echo ""
    
    if [ -n "$PHONE_IP" ]; then
        echo "=== Connecting to ADB device: ${PHONE_IP} ==="
        
        # Extract IP and port from PHONE_IP (format: IP:PORT)
        PHONE_HOST=$(echo "${PHONE_IP}" | cut -d: -f1)
        PHONE_PORT=$(echo "${PHONE_IP}" | cut -d: -f2)
        
        echo "Phone IP: ${PHONE_HOST}:${PHONE_PORT}"
        echo "Testing if ${PHONE_HOST} is in Tailscale network..."
        
        # Check if the phone IP is a Tailscale IP (starts with 100.x.x.x)
        if echo "${PHONE_HOST}" | grep -q "^100\."; then
            echo "✓ Phone IP appears to be a Tailscale IP"
        else
            echo "⚠ Phone IP does not appear to be a Tailscale IP (expected 100.x.x.x)"
        fi
        
        adb kill-server 2>/dev/null || true
        sleep 1
        adb start-server
        sleep 3
        
        # Set ADB connection timeout
        export ADB_INSTALL_TIMEOUT=30
        
        echo "Attempting initial ADB connection..."
        proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP} 2>&1 || true
        sleep 5
        
        MAX_AUTH_RETRIES=15
        AUTH_RETRY_COUNT=0
        DEVICE_AUTHORIZED=false
        
        while [ $AUTH_RETRY_COUNT -lt $MAX_AUTH_RETRIES ]; do
            AUTH_RETRY_COUNT=$((AUTH_RETRY_COUNT + 1))
            sleep 4
            
            # Use proxychains for adb devices too
            DEVICE_STATUS=$(proxychains4 -f /etc/proxychains4.conf adb devices 2>/dev/null | grep "${PHONE_IP}" || echo "")
            
            if echo "$DEVICE_STATUS" | grep -q "device$"; then
                echo "✓ ADB connected and authorized successfully"
                DEVICE_AUTHORIZED=true
                break
            elif echo "$DEVICE_STATUS" | grep -q "unauthorized"; then
                echo "⚠ Device is connected but unauthorized (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES)"
                if [ -f /root/.android/adbkey.pub ]; then
                    echo "ADB public key (first 100 chars):"
                    head -c 100 /root/.android/adbkey.pub | tr -d '\n'
                    echo ""
                fi
                echo "Reconnecting..."
                proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP} 2>&1 || true
            elif echo "$DEVICE_STATUS" | grep -q "offline"; then
                echo "⚠ Device is offline (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES), reconnecting..."
                proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP} 2>&1 || true
            elif [ -z "$DEVICE_STATUS" ]; then
                echo "⚠ Device not found (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES), reconnecting..."
                proxychains4 -f /etc/proxychains4.conf adb connect ${PHONE_IP} 2>&1 || true
            fi
        done
        
        echo ""
        echo "Final ADB device status:"
        proxychains4 -f /etc/proxychains4.conf adb devices 2>&1 || adb devices
        
        if [ "$DEVICE_AUTHORIZED" = false ]; then
            echo ""
            echo "⚠ WARNING: ADB device is not authorized or not connected"
            echo "Tailscale status:"
            tailscale status || true
        fi
    fi
else
    echo "ERROR: TAILSCALE_AUTHKEY not provided"
    exit 1
fi

echo "=== Starting FastAPI application ==="
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}