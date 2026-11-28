#!/bin/bash
set -eux

# This instance has no outbound access at all, so nothing can be installed here.
# Everything below uses only what ships on the Amazon Linux 2023 image.

# Port 22 belongs to the decoy, so the real sshd must give it up. There is no
# other way in: to change this instance you destroy and recreate it.
systemctl stop sshd || true
systemctl disable sshd || true

mkdir -p /opt/honeypot

cat > /opt/honeypot/honeypot.py <<'PYEOF'
#!/usr/bin/env python3
"""Team 13 honeypot.

Port 22 answers like an SSH server, records who connected and what they sent,
then hangs up. Port 2222 serves that record back as plain text, and the
security group only lets the main instance reach it.
"""
import datetime
import os
import socket
import threading

LOG = "/var/log/team13-honeypot.log"
BANNER = b"SSH-2.0-OpenSSH_8.7\r\n"
_lock = threading.Lock()


def log(message):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with _lock:
        with open(LOG, "a") as handle:
            handle.write(stamp + " " + message + "\n")


def handle_decoy(conn, addr):
    peer = addr[0]
    try:
        conn.settimeout(5)
        conn.sendall(BANNER)
        raw = conn.recv(512)
        seen = raw.decode("utf-8", "replace").strip().replace("\n", " ")[:200]
        log("attempt from " + peer + " client=" + (seen if seen else "none"))
    except Exception as err:
        log("attempt from " + peer + " ended=" + type(err).__name__)
    finally:
        try:
            conn.close()
        except Exception:
            pass


def serve_log():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", 2222))
    sock.listen(16)
    while True:
        conn, _ = sock.accept()
        try:
            conn.settimeout(5)
            conn.recv(2048)
            if os.path.exists(LOG):
                with open(LOG, "rb") as handle:
                    body = handle.read()
            else:
                body = b"no attempts recorded yet\n"
            head = (
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: text/plain; charset=utf-8\r\n"
                "Content-Length: " + str(len(body)) + "\r\n"
                "Connection: close\r\n\r\n"
            )
            conn.sendall(head.encode("ascii") + body)
        except Exception:
            pass
        finally:
            try:
                conn.close()
            except Exception:
                pass


def serve_decoy():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", 22))
    sock.listen(64)
    log("decoy listening on port 22, log server on port 2222")
    while True:
        conn, addr = sock.accept()
        worker = threading.Thread(target=handle_decoy, args=(conn, addr))
        worker.daemon = True
        worker.start()


threading.Thread(target=serve_log, daemon=True).start()
serve_decoy()
PYEOF

chmod 755 /opt/honeypot/honeypot.py

cat > /etc/systemd/system/team13-honeypot.service <<'UNITEOF'
[Unit]
Description=Team 13 honeypot decoy and log server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/honeypot/honeypot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNITEOF

chmod 644 /etc/systemd/system/team13-honeypot.service
systemctl daemon-reload
systemctl enable --now team13-honeypot

echo "honeypot ready $(date)" > /var/log/team13-honeypot-ready
