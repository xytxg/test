"""Local-only, Range-capable media fixtures for simulator tests and screenshots."""
import http.server
import os
import re
import ssl
import sys
import threading
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent / 'Tests' / 'Fixtures' / 'media'
class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)
    def log_message(self, *args): pass
    def send_head(self):
        path = Path(self.translate_path(self.path))
        if not path.is_file(): return super().send_head()
        size = path.stat().st_size
        start, end = 0, size - 1
        match = re.fullmatch(r'bytes=(\d+)-(\d*)', self.headers.get('Range', ''))
        if match:
            start = int(match[1]); end = min(int(match[2]) if match[2] else end, end)
            if start > end:
                self.send_response(416); self.send_header('Content-Range', f'bytes */{size}'); self.send_header('Content-Length', '0'); self.end_headers(); return None
        file = path.open('rb'); file.seek(start)
        self._remaining = end - start + 1
        self.send_response(206 if match else 200)
        self.send_header('Content-Type', self.guess_type(str(path)))
        self.send_header('Content-Length', str(self._remaining))
        self.send_header('Accept-Ranges', 'bytes'); self.send_header('ETag', '"fixture-v1"')
        if match: self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers(); return file
    def copyfile(self, source, outputfile):
        remaining = getattr(self, '_remaining', None)
        if remaining is None: return super().copyfile(source, outputfile)
        try:
            while remaining:
                block = source.read(min(65536, remaining))
                if not block: break
                outputfile.write(block); remaining -= len(block)
        except (BrokenPipeError, ConnectionResetError): pass
class TransportFixture(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        expected_host = "webox-transport.test:8766"
        if self.path != "/register?signature=a%2Bb" or self.headers.get("Host") != expected_host:
            self.send_error(400, "Wrong host or target")
            return
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= 1024:
            self.send_error(400, "Wrong request size")
            return
        body = self.rfile.read(size)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

def start_transport_fixture(folder):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 8766), TransportFixture)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(folder / "server.pem", folder / "server.key")
    def sni(_, name, __):
        if name != "webox-transport.test":
            return ssl.ALERT_DESCRIPTION_UNRECOGNIZED_NAME
    tls.set_servername_callback(sni)
    original_accept = server.get_request
    def accept_tls():
        connection, address = original_accept()
        try:
            return tls.wrap_socket(connection, server_side=True), address
        except BaseException:
            connection.close()
            raise
    server.get_request = accept_tls
    threading.Thread(target=server.serve_forever, daemon=True).start()

if len(sys.argv) == 2:
    start_transport_fixture(Path(sys.argv[1]))
http.server.ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
