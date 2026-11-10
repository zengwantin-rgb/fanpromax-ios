"""Authenticated, write-only diagnostic receiver. No device control or public log API."""
import argparse
from contextlib import contextmanager
import hashlib
import hmac
import json
import math
import os
from pathlib import Path
import re
import socket
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import zlib

MAX_BODY = 512 * 1024
MAX_STORAGE = 128 * 1024 * 1024
UUID = re.compile(r"^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")
TOP_FIELDS = set('''version phase time context last_motion_window motion_windows cleanup_outcome
last_speed_write_time local_verified_frames character_ready_frames eligible_speed_frames
profile_ready last_failure last_failure_time profile_error speed_requested selected_multiplier
speed_field_outcome flight_requested flight_outcome flight_motion_windows flight_calls
flight_lease_active invincibility_implemented damage_reduction_implemented task_count
speed_field_writes_confirmed walking_lease_active crouching_lease_active character_cap_lease_active
measured_speed_multiplier_verified server_acceptance_verified aim_included recoil_included'''.split())


def bounded(value, depth=0):
    if depth > 8:
        return False
    if isinstance(value, dict):
        return len(value) <= 100 and all(isinstance(k, str) and len(k) <= 100 and bounded(v, depth+1) for k, v in value.items())
    if isinstance(value, list):
        return len(value) <= 90 and all(bounded(v, depth+1) for v in value)
    if isinstance(value, str):
        return len(value) <= 1024
    if isinstance(value, (float, int)):
        return math.isfinite(value)
    return value is None


def decode_body(raw, probe):
    def invalid_constant(_):
        raise ValueError('nonfinite')
    doc = json.loads(raw, parse_constant=invalid_constant)
    if not isinstance(doc, dict) or set(doc) != {'schema', 'report_id', 'session_id', 'snapshot'}:
        raise ValueError('envelope')
    if doc['schema'] != 1 or not all(isinstance(doc[k], str) and UUID.fullmatch(doc[k]) for k in ('report_id', 'session_id')):
        raise ValueError('identity')
    snapshot = doc['snapshot']
    if not isinstance(snapshot, dict) or not bounded(snapshot) or not set(snapshot).issubset(TOP_FIELDS):
        raise ValueError('snapshot')
    version = snapshot.get('version')
    if not isinstance(version, str) or not version.startswith('connectivity-probe' if probe else 'integrated-'):
        raise ValueError('version')
    if not isinstance(snapshot.get('time'), (int, float)):
        raise ValueError('time')
    return doc


class Store:
    def __init__(self, folder):
        self.folder = Path(folder)
        self.folder.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = threading.Lock()
        with self.connect() as db:
            db.execute('PRAGMA auto_vacuum=INCREMENTAL')
            db.execute('CREATE TABLE IF NOT EXISTS reports (id TEXT PRIMARY KEY, received REAL, body BLOB)')
            db.execute('CREATE INDEX IF NOT EXISTS received_index ON reports(received)')

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.folder/'reports.sqlite3')
        try:
            with db:
                yield db
        finally:
            db.close()

    def expire(self):
        with self.lock, self.connect() as db:
            db.execute('DELETE FROM reports WHERE received < ?', (time.time() - 7*86400,))
            if not db.execute('SELECT 1 FROM reports LIMIT 1').fetchone():
                (self.folder/'latest.json').unlink(missing_ok=True)
            db.commit()
            db.execute('PRAGMA incremental_vacuum(128)')

    def add(self, doc):
        raw = json.dumps(doc, separators=(',', ':'), allow_nan=False).encode()
        packed = zlib.compress(raw, 3)
        received = time.time()
        with self.lock, self.connect() as db:
            cursor = db.execute('INSERT OR IGNORE INTO reports VALUES(?, ?, ?)', (doc['report_id'], received, packed))
            if cursor.rowcount == 0:
                return
            db.execute('DELETE FROM reports WHERE received < ?', (received - 7*86400,))
            rows = db.execute('SELECT id, length(body) FROM reports ORDER BY received DESC').fetchall()
            total = 0
            remove = []
            for index, (identity, length) in enumerate(rows):
                total += length
                if index >= 2048 or total > MAX_STORAGE:
                    remove.append((identity,))
            db.executemany('DELETE FROM reports WHERE id=?', remove)
            db.commit()
            db.execute('PRAGMA incremental_vacuum(128)')
            latest = {'received_at': received, **doc}
            temp = self.folder/'latest.json.tmp'
            temp.write_text(json.dumps(latest, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
            temp.replace(self.folder/'latest.json')


class Receiver(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 8

    def __init__(self, address, config, store):
        self.tokens = {kind: hashlib.sha256(config[kind].encode()).digest() for kind in ('upload_token', 'probe_token')}
        self.store = store
        self.slots = threading.BoundedSemaphore(8)
        self.rate_lock = threading.Lock()
        self.last_upload = 0
        self.last_expiry = 0
        super().__init__(address, Handler)

    def service_actions(self):
        now = time.monotonic()
        if now - self.last_expiry >= 60:
            self.last_expiry = now
            try:
                self.store.expire()
            except (OSError, sqlite3.Error):
                print('receiver retention maintenance deferred', flush=True)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        # Never print request headers, body, peer IP, pairing token or diagnostic values.
        print('receiver request failed', flush=True)


class Handler(BaseHTTPRequestHandler):
    server_version = 'FanProDiagnosticReceiver/1'

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def log_message(self, *args):
        pass

    def reply(self, code, value):
        body = json.dumps(value, separators=(',', ':')).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self):
        self.reply(200, {'service': 'fanpro-diagnostics', 'schema': 1}) if self.path == '/health' else self.reply(404, {'error': 'not_found'})

    def do_POST(self):
        if self.path != '/v1/diagnostics':
            return self.reply(404, {'error': 'not_found'})
        auth = self.headers.get_all('Authorization', [])
        if len(auth) != 1 or not auth[0].startswith('Bearer ') or len(auth[0]) > 200:
            return self.reply(401, {'error': 'unauthorized'})
        supplied = hashlib.sha256(auth[0][7:].encode()).digest()
        probe = hmac.compare_digest(supplied, self.server.tokens['probe_token'])
        if not (probe or hmac.compare_digest(supplied, self.server.tokens['upload_token'])):
            return self.reply(401, {'error': 'unauthorized'})
        lengths = self.headers.get_all('Content-Length', [])
        if self.headers.get('Transfer-Encoding') or self.headers.get('Content-Encoding') or len(lengths) != 1 or not lengths[0].isascii() or not lengths[0].isdigit():
            return self.reply(400, {'error': 'length_required'})
        length = int(lengths[0])
        if not 0 < length <= MAX_BODY:
            return self.reply(413, {'error': 'too_large'})
        if self.headers.get('Content-Type', '').split(';')[0].lower().strip() != 'application/json':
            return self.reply(415, {'error': 'json_required'})
        if not probe:
            with self.server.rate_lock:
                now = time.monotonic()
                if now - self.server.last_upload < 2:
                    return self.reply(429, {'error': 'retry_later'})
                self.server.last_upload = now
        try:
            raw = self.rfile.read(length)
            if len(raw) != length:
                return self.reply(400, {'error': 'incomplete'})
            doc = decode_body(raw, probe)
        except (ValueError, TypeError, RecursionError, OverflowError, socket.timeout):
            return self.reply(400, {'error': 'invalid_report'})
        try:
            if not probe:
                self.server.store.add(doc)
        except (OSError, sqlite3.Error):
            return self.reply(503, {'error': 'storage_unavailable'})
        self.reply(201, {'accepted': True, 'report_id': doc['report_id'], 'probe': probe})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    parser.add_argument('--data', required=True)
    parser.add_argument('--port', type=int, default=18767)
    args = parser.parse_args()
    os.umask(0o077)
    config = json.loads(Path(args.config).read_text())
    if any(not isinstance(config.get(k), str) or not re.fullmatch(r'[0-9a-f]{64}', config[k]) for k in ('upload_token', 'probe_token')) or config['upload_token'] == config['probe_token']:
        raise ValueError('two independent 256-bit tokens required')
    receiver = Receiver(('127.0.0.1', args.port), config, Store(args.data))
    print('diagnostic receiver started on loopback; no public data-reading API', flush=True)
    receiver.serve_forever()


if __name__ == '__main__':
    main()
