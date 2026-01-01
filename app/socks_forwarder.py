#!/usr/bin/env python3
"""
TCP port forwarder through SOCKS5 proxy.
Forwards connections from localhost:LOCAL_PORT to REMOTE_HOST:REMOTE_PORT via SOCKS5.
"""
import sys
import socket
import select
import threading
try:
    from socks import socksocket, PROXY_TYPE_SOCKS5
except ImportError:
    from pysocks import socksocket, PROXY_TYPE_SOCKS5

def forward_data(source, dest, label):
    """Forward data from source to destination."""
    try:
        while True:
            data = source.recv(4096)
            if not data:
                break
            dest.sendall(data)
    except Exception as e:
        print(f"Error in {label}: {e}", file=sys.stderr)
    finally:
        try:
            source.close()
            dest.close()
        except:
            pass

def forward_port(local_port, remote_host, remote_port, proxy_host, proxy_port):
    """Create a TCP forwarder through SOCKS5 proxy."""
    try:
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.settimeout(1.0)  # Allow periodic checks for errors
        server_socket.bind(('127.0.0.1', local_port))
        server_socket.listen(5)
        print(f"Forwarding localhost:{local_port} -> {remote_host}:{remote_port} via SOCKS5 {proxy_host}:{proxy_port}", file=sys.stderr, flush=True)
        
        while True:
            try:
                client_socket, addr = server_socket.accept()
                print(f"New connection from {addr}", file=sys.stderr, flush=True)
                
                # Create SOCKS5 connection to remote host
                proxy_socket = socksocket(socket.AF_INET, socket.SOCK_STREAM)
                proxy_socket.set_proxy(PROXY_TYPE_SOCKS5, proxy_host, proxy_port)
                proxy_socket.settimeout(30.0)  # 30 second timeout for connection
                
                try:
                    proxy_socket.connect((remote_host, remote_port))
                    print(f"Connected to {remote_host}:{remote_port} via SOCKS5", file=sys.stderr, flush=True)
                    
                    # Start forwarding in both directions
                    t1 = threading.Thread(target=forward_data, args=(client_socket, proxy_socket, "client->remote"))
                    t2 = threading.Thread(target=forward_data, args=(proxy_socket, client_socket, "remote->client"))
                    t1.daemon = True
                    t2.daemon = True
                    t1.start()
                    t2.start()
                    
                except Exception as e:
                    print(f"Failed to connect to {remote_host}:{remote_port} via SOCKS5: {e}", file=sys.stderr, flush=True)
                    try:
                        client_socket.close()
                    except:
                        pass
                    try:
                        proxy_socket.close()
                    except:
                        pass
                    
            except socket.timeout:
                # Timeout is expected, continue listening
                continue
            except KeyboardInterrupt:
                print("Received interrupt signal, shutting down...", file=sys.stderr, flush=True)
                break
            except Exception as e:
                print(f"Error accepting connection: {e}", file=sys.stderr, flush=True)
                continue
        
    except OSError as e:
        if e.errno == 98:  # Address already in use
            print(f"ERROR: Port {local_port} is already in use", file=sys.stderr, flush=True)
        else:
            print(f"ERROR: Failed to bind to port {local_port}: {e}", file=sys.stderr, flush=True)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Unexpected error: {e}", file=sys.stderr, flush=True)
        sys.exit(1)
    finally:
        try:
            server_socket.close()
        except:
            pass

if __name__ == "__main__":
    if len(sys.argv) != 6:
        print(f"Usage: {sys.argv[0]} LOCAL_PORT REMOTE_HOST REMOTE_PORT PROXY_HOST PROXY_PORT", file=sys.stderr)
        sys.exit(1)
    
    local_port = int(sys.argv[1])
    remote_host = sys.argv[2]
    remote_port = int(sys.argv[3])
    proxy_host = sys.argv[4]
    proxy_port = int(sys.argv[5])
    
    forward_port(local_port, remote_host, remote_port, proxy_host, proxy_port)

