#!/usr/bin/env python3
"""USB serial -> localhost TCP bridge for the Godot rocket simulator.
Usage: python esp32_serial_bridge.py COM5
Linux/macOS example: python esp32_serial_bridge.py /dev/ttyUSB0
Install dependency once: python -m pip install pyserial
"""
import socket
import sys
import time

try:
    import serial
except ImportError:
    print("Missing pyserial. Install it with: python -m pip install pyserial")
    raise SystemExit(1)

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM5"
BAUD = 115200
HOST = "127.0.0.1"
TCP_PORT = 8765

print(f"Opening ESP32 serial port {PORT} at {BAUD} baud...")
try:
    ser = serial.Serial(PORT, BAUD, timeout=1)
except Exception as exc:
    print(f"Could not open {PORT}: {exc}")
    print("Close Arduino Serial Monitor first and check the correct port name.")
    raise SystemExit(1)

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((HOST, TCP_PORT))
server.listen(1)
print(f"Waiting for Godot on {HOST}:{TCP_PORT}. Start the Godot game now.")
conn = None
try:
    while True:
        if conn is None:
            conn, addr = server.accept()
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            print(f"Godot connected: {addr}")
        raw = ser.readline()
        if not raw:
            continue
        line = raw.decode("utf-8", errors="ignore").strip()
        if not line or line.count(",") < 6:
            continue
        try:
            conn.sendall((line + "\n").encode("utf-8"))
        except (BrokenPipeError, ConnectionResetError, OSError):
            print("Godot disconnected; waiting for it to reconnect...")
            try:
                conn.close()
            except OSError:
                pass
            conn = None
except KeyboardInterrupt:
    print("\nBridge stopped.")
finally:
    if conn:
        conn.close()
    server.close()
    ser.close()
