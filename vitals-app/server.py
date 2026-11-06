import http.server
import socketserver
import urllib.request
import urllib.error
import urllib.parse
import sys
import os

PORT = 8080
FALLBACK_IPS = [
    os.environ.get("WATCH_IP", "").strip(),
    "192.168.0.196",
    "vitals.local",
    "192.168.4.1"
]
FALLBACK_IPS = [ip for ip in FALLBACK_IPS if ip]

class SmartProxyHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Enable CORS for all local requests
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Target-IP')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200, "ok")
        self.end_headers()

    def resolve_candidates(self, path):
        parsed = urllib.parse.urlparse(path)
        qs = urllib.parse.parse_qs(parsed.query)
        target = self.headers.get('X-Target-IP') or (qs.get('target', [None])[0])

        clean_qs = {k: v for k, v in qs.items() if k != 'target'}
        new_query = urllib.parse.urlencode(clean_qs, doseq=True)
        clean_path = parsed.path + (('?' + new_query) if new_query else '')

        candidates = []
        if target and target.strip():
            candidates.append(target.strip())
        for ip in FALLBACK_IPS:
            if ip not in candidates:
                candidates.append(ip)
        return candidates, clean_path

    def do_GET(self):
        if self.path.startswith('/api/') or self.path.startswith('/log.csv'):
            candidates, clean_path = self.resolve_candidates(self.path)
            last_err = None
            for ip in candidates:
                target_url = f"http://{ip}{clean_path}"
                try:
                    req = urllib.request.Request(target_url, headers={'User-Agent': 'PulseGuard-Proxy'})
                    with urllib.request.urlopen(req, timeout=2.5) as resp:
                        data = resp.read()
                        self.send_response(resp.status)
                        for header, val in resp.getheaders():
                            if header.lower() not in ['content-length', 'access-control-allow-origin', 'transfer-encoding']:
                                self.send_header(header, val)
                        self.send_header('Content-Length', str(len(data)))
                        self.send_header('X-Proxied-To', ip)
                        self.end_headers()
                        self.wfile.write(data)
                        return
                except Exception as e:
                    last_err = e
                    continue

            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            err_msg = f'{{"error": "Device unreachable across {candidates}: {str(last_err)}"}}'
            self.wfile.write(err_msg.encode('utf-8'))
            return

        return super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/'):
            candidates, clean_path = self.resolve_candidates(self.path)
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)
            last_err = None
            for ip in candidates:
                target_url = f"http://{ip}{clean_path}"
                try:
                    req = urllib.request.Request(
                        target_url,
                        data=post_data,
                        headers={'Content-Type': self.headers.get('Content-Type', 'application/x-www-form-urlencoded')}
                    )
                    with urllib.request.urlopen(req, timeout=3.5) as resp:
                        data = resp.read()
                        self.send_response(resp.status)
                        self.send_header('Content-Length', str(len(data)))
                        self.send_header('X-Proxied-To', ip)
                        self.end_headers()
                        self.wfile.write(data)
                        return
                except Exception as e:
                    last_err = e
                    continue

            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(f'{{"error": "{str(last_err)}"}}'.encode('utf-8'))
            return

        return super().do_POST()

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", PORT), SmartProxyHandler) as httpd:
        print(f"========================================================")
        print(f"   PulseGuard Proxy Server running at http://localhost:{PORT}")
        print(f"   Auto-Discovery Watch Candidates: {FALLBACK_IPS}")
        print(f"========================================================")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopping server.")
