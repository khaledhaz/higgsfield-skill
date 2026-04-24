#!/usr/bin/env python3
"""Tiny HTTP server for reference_downloader tests.

Serves a 200 PNG at /ok.png, a 200 JPG at /ok.jpg, a 404 at /missing,
and a 200 text/html at /wrong_type (to exercise content-type rejection).
Run: python3 reference_server.py <port>
"""
import http.server
import socketserver
import sys
import struct
import zlib

def tiny_png():
    sig = b"\x89PNG\r\n\x1a\n"
    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    raw = b"\x00" + bytes([255, 0, 0])
    idat = chunk(b"IDAT", zlib.compress(raw))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend

def tiny_jpg():
    return (
        b'\xff\xd8'  # SOI
        b'\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00'  # APP0
        b'\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t'
        b'\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a'
        b'\x1f\x1e\x1d\x1a\x1c\x1c $.\' ",#\x1c\x1c(7),01444\x1f\''
        b'\t\x08\x08\x08\x0b\n\n\x0c\x14\r\r\x0c\x0b\x0b\x0c\x19\x10'
        b'\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c\x1c\x1c\x1c\x1c'
        b'\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c'
        b'\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c\x1c'
        b'\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00'
        b'\xff\xc4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
        b'\x00\x00\x00\x00\x00\x00\x00\x08'
        b'\xff\xc4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
        b'\x00\x00\x00\x00\x00\x00\x00\x00'
        b'\xff\xda\x00\x08\x01\x01\x00\x00?\x00\x7f\x00'
        b'\xff\xd9'  # EOI
    )

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/ok.png":
            b = tiny_png()
            self.send_response(200); self.send_header("Content-Type", "image/png"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        elif self.path == "/ok.jpg":
            b = tiny_jpg()
            self.send_response(200); self.send_header("Content-Type", "image/jpeg"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        elif self.path == "/wrong_type":
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers(); self.wfile.write(b"<html>")
        else:
            self.send_response(404); self.end_headers()
    def log_message(self, *a, **kw): pass

if __name__ == "__main__":
    port = int(sys.argv[1])
    with socketserver.TCPServer(("127.0.0.1", port), H) as srv:
        srv.serve_forever()
