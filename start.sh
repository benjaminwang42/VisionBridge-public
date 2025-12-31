#!/bin/sh

mkdir -p /root/.android
if [ -n "$ADB_PRIVATE_KEY" ] && [ -n "$ADB_PUBLIC_KEY" ]; then
    echo "$ADB_PRIVATE_KEY" > /root/.android/adbkey
    echo "$ADB_PUBLIC_KEY" > /root/.android/adbkey.pub
    chmod 600 /root/.android/adbkey
    chmod 644 /root/.android/adbkey.pub
fi

if [ -n "$TAILSCALE_AUTHKEY" ]; then
    echo "=== Starting Tailscale ==="
    
    if echo "$TAILSCALE_AUTHKEY" | grep -q "^tskey-"; then
        echo "✓ Auth key format appears valid"
    else
        echo "⚠ WARNING: Auth key format may be invalid (should start with 'tskey-')"
        echo "Current key starts with: $(echo "$TAILSCALE_AUTHKEY" | cut -c1-10)..."
    fi
    
    mkdir -p /var/lib/tailscale
    
    echo "Starting tailscaled daemon..."
    tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
    TAILSCALED_PID=$!
    
    echo "Waiting for tailscaled to initialize..."
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
        echo "⚠ WARNING: Cannot reach Tailscale control server (this may cause authentication to fail)"
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
                echo "Status output:"
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
        echo "Checking Tailscale status for debugging..."
        tailscale status || true
        echo "Checking tailscaled logs..."
        echo "This is likely due to:"
        echo "1. Invalid or expired TAILSCALE_AUTHKEY"
        echo "2. Network connectivity issues to Tailscale control server"
        echo "3. Tailscale service outage"
        echo ""
        echo "Please verify your TAILSCALE_AUTHKEY in Railway environment variables"
        echo "and check https://status.tailscale.com/ for service status"
        exit 1
    fi
    
    sleep 3
    
    if [ -n "$PHONE_IP" ]; then
        echo "Connecting to ADB device at ${PHONE_IP}:5555"
        adb connect ${PHONE_IP}:5555
        if [ $? -eq 0 ]; then
            echo "✓ ADB connected successfully"
        else
            echo "ERROR: ADB connection failed"
            exit 1
        fi
    else
        echo "WARNING: PHONE_IP not set, skipping ADB connection"
    fi
else
    echo "ERROR: TAILSCALE_AUTHKEY not provided, but required for this application"
    exit 1
fi

echo "=== Starting FastAPI application on port ${PORT:-8080} ==="
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}
