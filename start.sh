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
    
    # Verify SOCKS5 proxy is listening
    echo "Verifying SOCKS5 proxy is ready..."
    if netstat -tuln 2>/dev/null | grep -q ":1055" || ss -tuln 2>/dev/null | grep -q ":1055"; then
        echo "✓ SOCKS5 proxy is listening on port 1055"
    else
        echo "⚠ WARNING: SOCKS5 proxy may not be listening on port 1055"
        echo "Checking if tailscaled process is running..."
        ps aux | grep tailscaled | grep -v grep || echo "tailscaled process not found"
        echo "Note: With userspace-networking, SOCKS5 proxy should be on localhost:1055"
    fi
    
    # Test SOCKS5 proxy directly with curl
    echo "Testing SOCKS5 proxy with curl..."
    if command -v curl >/dev/null 2>&1; then
        # Try to use the SOCKS5 proxy to connect to a Tailscale IP
        TEST_IP=$(tailscale status 2>/dev/null | grep -E "^100\." | head -1 | awk '{print $1}' || echo "")
        if [ -n "${TEST_IP}" ] && [ "${TEST_IP}" != "${PHONE_HOST}" ]; then
            echo "Testing SOCKS5 proxy connectivity to ${TEST_IP}..."
            if curl -s --max-time 5 --socks5-hostname 127.0.0.1:1055 http://${TEST_IP}:80 2>&1 | head -1 | grep -q "HTTP\|connected\|timeout"; then
                echo "✓ SOCKS5 proxy appears to be working"
            else
                echo "⚠ SOCKS5 proxy test inconclusive (expected for non-HTTP services)"
            fi
        fi
    fi
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
        
        # Verify phone device is online in Tailscale
        echo "Checking if phone device is online in Tailscale..."
        PHONE_IN_STATUS=false
        if tailscale status 2>/dev/null | grep -q "${PHONE_HOST}"; then
            PHONE_IN_STATUS=true
            PHONE_STATUS=$(tailscale status 2>/dev/null | grep "${PHONE_HOST}" | awk '{for(i=NF-2;i<=NF;i++) printf "%s ", $i; print ""}' | xargs || echo "unknown")
            echo "Phone device status in Tailscale: ${PHONE_STATUS}"
            if echo "${PHONE_STATUS}" | grep -qi "offline"; then
                echo "⚠ WARNING: Phone device appears offline in Tailscale."
                echo "Waiting up to 30 seconds for device to come online..."
                WAIT_COUNT=0
                while [ $WAIT_COUNT -lt 10 ]; do
                    sleep 3
                    WAIT_COUNT=$((WAIT_COUNT + 1))
                    if tailscale status 2>/dev/null | grep "${PHONE_HOST}" | grep -vq "offline"; then
                        echo "✓ Phone device is now online!"
                        break
                    fi
                    echo "Still waiting... (${WAIT_COUNT}/10)"
                done
            fi
        else
            echo "⚠ WARNING: Phone device ${PHONE_HOST} not found in Tailscale status"
            echo "Available Tailscale devices:"
            tailscale status 2>/dev/null | grep -E "^100\." | head -5 || echo "None found"
        fi
        
        # Test connectivity to phone through Tailscale
        echo "Testing connectivity to ${PHONE_HOST} through Tailscale..."
        if timeout 10 tailscale ping -c 1 ${PHONE_HOST} 2>&1 | grep -q "pong"; then
            echo "✓ Can ping ${PHONE_HOST} through Tailscale"
        else
            echo "⚠ WARNING: Cannot ping ${PHONE_HOST} through Tailscale"
            echo "This may indicate the device is offline or unreachable"
        fi
        
        # Test SOCKS5 proxy with a simple connection test
        echo "Testing SOCKS5 proxy with proxychains..."
        TEST_OUTPUT=$(timeout 10 proxychains4 -f /etc/proxychains4.conf nc -zv -w 5 ${PHONE_HOST} ${PHONE_PORT} 2>&1 || echo "test_failed")
        if echo "${TEST_OUTPUT}" | grep -qi "succeeded\|open\|connected"; then
            echo "✓ SOCKS5 proxy can reach ${PHONE_HOST}:${PHONE_PORT}"
        else
            echo "⚠ SOCKS5 proxy test failed or inconclusive"
            echo "Test output: ${TEST_OUTPUT}"
            echo "This may be normal - ADB uses a custom protocol"
        fi
        echo ""
        
        # Create a local port forward through SOCKS5 proxy
        # This allows ADB server to connect to localhost, which gets forwarded through the proxy
        # Use port 5556 to avoid conflicts with ADB's default port 5555
        FORWARD_LOCAL_PORT=5556
        echo "Setting up TCP port forward: localhost:${FORWARD_LOCAL_PORT} -> ${PHONE_HOST}:${PHONE_PORT} via SOCKS5"
        python3 /app/app/socks_forwarder.py ${FORWARD_LOCAL_PORT} ${PHONE_HOST} ${PHONE_PORT} 127.0.0.1 1055 &
        FORWARDER_PID=$!
        sleep 3
        
        # Verify forwarder is running
        sleep 2
        if kill -0 $FORWARDER_PID 2>/dev/null; then
            echo "✓ Port forwarder is running (PID: $FORWARDER_PID)"
            # Test if the port is listening
            if netstat -tuln 2>/dev/null | grep -q ":${FORWARD_LOCAL_PORT}" || ss -tuln 2>/dev/null | grep -q ":${FORWARD_LOCAL_PORT}"; then
                echo "✓ Port ${FORWARD_LOCAL_PORT} is listening"
            else
                echo "⚠ WARNING: Port ${FORWARD_LOCAL_PORT} may not be listening yet"
            fi
        else
            echo "⚠ ERROR: Port forwarder failed to start"
            echo "Checking forwarder output..."
            wait $FORWARDER_PID 2>&1 || true
        fi
        
        adb kill-server 2>/dev/null || true
        sleep 1
        adb start-server
        sleep 3
        
        # Set ADB connection timeout
        export ADB_INSTALL_TIMEOUT=30
        
        # Connect to the local forwarded port instead of the remote IP directly
        FORWARDED_PHONE_IP="127.0.0.1:${FORWARD_LOCAL_PORT}"
        echo "Attempting ADB connection to forwarded port ${FORWARDED_PHONE_IP}..."
        echo "Running: adb connect ${FORWARDED_PHONE_IP}"
        # Disconnect any existing connection first
        adb disconnect ${FORWARDED_PHONE_IP} 2>&1 || true
        sleep 1
        CONNECT_OUTPUT=$(adb connect ${FORWARDED_PHONE_IP} 2>&1)
        CONNECT_EXIT=$?
        # Give ADB time to complete the connection handshake
        sleep 3
        
        # Check if the error is "No route to host" which suggests proxychains isn't working
        if echo "${CONNECT_OUTPUT}" | grep -q "No route to host"; then
            echo "⚠ ERROR: 'No route to host' detected"
            echo "This error suggests the connection is not being routed through proxychains"
            echo ""
            echo "Debugging information:"
            echo "1. Checking if proxychains library is loaded..."
            ldd $(which adb) 2>/dev/null | head -5 || echo "Cannot check ADB libraries"
            echo ""
            echo "2. Testing proxychains with a simple network command..."
            proxychains4 -f /etc/proxychains4.conf timeout 3 nc -zv 127.0.0.1 22 2>&1 | head -3 || echo "Proxychains test completed"
            echo ""
            echo "3. Verifying proxychains config..."
            cat /etc/proxychains4.conf
            echo ""
        fi
        
        echo "Connection attempt output:"
        echo "${CONNECT_OUTPUT}"
        echo ""
        
        if [ $CONNECT_EXIT -ne 0 ]; then
            echo "⚠ Initial connection attempt failed (exit code: $CONNECT_EXIT)"
            echo "Will retry in the connection loop..."
        else
            echo "✓ Initial connection command completed (checking device status in loop)..."
        fi
        
        # Wait longer for initial connection to stabilize
        sleep 5
        
        MAX_AUTH_RETRIES=15
        AUTH_RETRY_COUNT=0
        DEVICE_AUTHORIZED=false
        
        while [ $AUTH_RETRY_COUNT -lt $MAX_AUTH_RETRIES ]; do
            AUTH_RETRY_COUNT=$((AUTH_RETRY_COUNT + 1))
            sleep 5  # Increased wait time to allow ADB handshake to complete
            
            # Check device status (using forwarded port)
            DEVICES_OUTPUT=$(adb devices 2>/dev/null)
            DEVICE_STATUS=$(echo "$DEVICES_OUTPUT" | grep "${FORWARDED_PHONE_IP}" || echo "")
            
            # Verify forwarder is still running
            if ! kill -0 $FORWARDER_PID 2>/dev/null; then
                echo "⚠ ERROR: Port forwarder process died! Restarting..."
                python3 /app/app/socks_forwarder.py ${FORWARD_LOCAL_PORT} ${PHONE_HOST} ${PHONE_PORT} 127.0.0.1 1055 &
                FORWARDER_PID=$!
                sleep 3
            fi
            
            # Debug: show full device status
            if [ $AUTH_RETRY_COUNT -le 3 ] || [ $((AUTH_RETRY_COUNT % 3)) -eq 0 ]; then
                echo "Device status check (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES):"
                echo "$DEVICES_OUTPUT" | grep -E "(List|${FORWARDED_PHONE_IP})" || echo "No devices found"
            fi
            
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
                adb connect ${FORWARDED_PHONE_IP} 2>&1 || true
            elif echo "$DEVICE_STATUS" | grep -q "offline"; then
                if [ $AUTH_RETRY_COUNT -eq 1 ]; then
                    # First time seeing offline - might still be connecting, wait a bit longer
                    echo "⚠ Device is offline (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES), waiting for connection to establish..."
                    sleep 5
                else
                    # Subsequent offline status - disconnect and reconnect
                    echo "⚠ Device is offline (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES), disconnecting and reconnecting..."
                    adb disconnect ${FORWARDED_PHONE_IP} 2>&1 || true
                    sleep 2
                    adb connect ${FORWARDED_PHONE_IP} 2>&1 || true
                    sleep 5  # Give ADB more time to complete handshake
                fi
            elif [ -z "$DEVICE_STATUS" ]; then
                echo "⚠ Device not found (attempt $AUTH_RETRY_COUNT/$MAX_AUTH_RETRIES), connecting..."
                adb connect ${FORWARDED_PHONE_IP} 2>&1 || true
                sleep 3  # Give ADB time to complete handshake
            fi
        done
        
        echo ""
        echo "Final ADB device status:"
        adb devices 2>&1
        
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