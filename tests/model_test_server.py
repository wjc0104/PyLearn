"""Controlled HTTP fixture for simulator UI tests; no real service or API key."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json


class ModelFixture(BaseHTTPRequestHandler):
    def reply(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply(200, {'data': [{'id': name} for name in ['ui-original', 'ui-second', 'ui-unavailable']]})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
        if body.get('model') == 'ui-unavailable':
            self.reply(403, {'error': {'message': 'fixture unavailable'}})
        else:
            self.reply(200, {'choices': [{'message': {'content': 'OK'}}]})

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 18764), ModelFixture).serve_forever()
