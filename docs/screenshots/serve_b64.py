#!/usr/bin/env python3
"""HTTP server that serves files as base64 text at /b64/<filename>."""
import base64
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

DIR = os.path.dirname(os.path.abspath(__file__))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/b64/"):
            fname = os.path.basename(self.path[5:])
            fpath = os.path.join(DIR, fname)
            if os.path.isfile(fpath):
                self.send_response(200)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                with open(fpath, "rb") as f:
                    self.wfile.write(base64.b64encode(f.read()))
            else:
                self.send_response(404)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"NOT_FOUND")
        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")

    def log_message(self, *a): pass

HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
