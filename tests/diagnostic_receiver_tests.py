"""Run only on GitHub-hosted macOS; all data and tokens below are synthetic."""
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import uuid
import zlib

assert sys.platform == 'darwin' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
spec = importlib.util.spec_from_file_location('receiver', Path(__file__).parents[1]/'diagnostics/receiver.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.store = r.Store(self.temp.name)
        self.server = r.Receiver(('127.0.0.1', 0), {'upload_token': 'a'*64, 'probe_token': 'b'*64}, self.store)
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.base = 'http://127.0.0.1:'+str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()
        self.temp.cleanup()

    def body(self, version='integrated-telemetry-test'):
        return {'schema': 1, 'report_id': str(uuid.uuid4()), 'session_id': str(uuid.uuid4()), 'snapshot': {'version': version, 'time': 1, 'context': {'speed_eligible': True}, 'motion_windows': []}}

    def request(self, path, body=None, token='a'*64):
        headers = {'Authorization': 'Bearer '+token, 'Content-Type': 'application/json'}
        req = urllib.request.Request(self.base+path, data=json.dumps(body).encode() if body is not None else None, headers=headers)
        try:
            response = urllib.request.urlopen(req, timeout=3)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return response.status, json.load(response)

    def test_authenticated_store_and_no_read_api(self):
        doc = self.body()
        code, ack = self.request('/v1/diagnostics', doc)
        self.assertEqual(code, 201)
        self.assertEqual(ack['report_id'], doc['report_id'])
        self.assertEqual(json.loads((Path(self.temp.name)/'latest.json').read_text())['snapshot'], doc['snapshot'])
        self.assertEqual(self.request('/latest.json')[0], 404)
        self.assertEqual(self.request('/v1/diagnostics')[0], 404)
        self.assertEqual(self.request('/health')[0], 200)

    def test_bad_token_and_rate_limit(self):
        self.assertEqual(self.request('/v1/diagnostics', self.body(), 'wrong')[0], 401)
        self.assertEqual(self.request('/v1/diagnostics', self.body())[0], 201)
        self.assertEqual(self.request('/v1/diagnostics', self.body())[0], 429)

    def test_probe_never_overwrites_phone_data(self):
        doc = self.body()
        self.assertEqual(self.request('/v1/diagnostics', doc)[0], 201)
        self.assertEqual(self.request('/v1/diagnostics', self.body('connectivity-probe'), 'b'*64)[0], 201)
        self.assertEqual(self.request('/v1/diagnostics', self.body(), 'b'*64)[0], 400)
        self.assertEqual(json.loads((Path(self.temp.name)/'latest.json').read_text())['report_id'], doc['report_id'])

    def test_payload_limits_and_validation(self):
        doc = self.body()
        doc['snapshot']['unknown_account_field'] = 'secret'
        with self.assertRaises(ValueError):
            r.decode_body(json.dumps(doc).encode(), False)
        doc = self.body()
        doc['snapshot']['time'] = float('nan')
        with self.assertRaises(ValueError):
            r.decode_body(json.dumps(doc).encode(), False)
        doc = self.body()
        doc['report_id'] = '../../file'
        with self.assertRaises(ValueError):
            r.decode_body(json.dumps(doc).encode(), False)
        doc = self.body()
        doc['snapshot']['motion_windows'] = [{}]*91
        with self.assertRaises(ValueError):
            r.decode_body(json.dumps(doc).encode(), False)
        self.assertEqual(self.request('/v1/diagnostics', {'padding': 'x'*r.MAX_BODY})[0], 413)

    def test_duplicate_and_storage_retention(self):
        doc = self.body()
        self.store.add(doc)
        self.store.add(doc)
        with sqlite3.connect(Path(self.temp.name)/'reports.sqlite3') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM reports').fetchone()[0], 1)
            self.assertEqual(json.loads(zlib.decompress(db.execute('SELECT body FROM reports').fetchone()[0])), doc)
            db.execute('UPDATE reports SET received=0')
        self.store.add(self.body())
        with sqlite3.connect(Path(self.temp.name)/'reports.sqlite3') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM reports').fetchone()[0], 1)


unittest.main()
