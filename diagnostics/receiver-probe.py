"""Probe the deployed receiver only from hosted macOS, using a separate synthetic-data token."""
import json
import os
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request
import uuid

assert sys.platform == 'darwin' and os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
endpoint = os.environ['DIAGNOSTIC_ENDPOINT']
token = os.environ['DIAGNOSTIC_PROBE_TOKEN']
assert endpoint.startswith('https://') and endpoint.endswith('/v1/diagnostics')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(NoRedirect)


def request(url, body=None, credential=None):
    headers = {'Content-Type': 'application/json'}
    if credential:
        headers['Authorization'] = 'Bearer '+credential
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        response = opener.open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, json.loads(response.read(4096))


doc = {'schema': 1, 'report_id': str(uuid.uuid4()), 'session_id': str(uuid.uuid4()), 'snapshot': {'version': 'connectivity-probe-v1', 'time': time.time()}}
assert request(endpoint.rsplit('/v1/', 1)[0]+'/health')[0] == 200
assert request(endpoint, doc)[0] == 401
code, ack = request(endpoint, doc, token)
assert code == 201 and ack.get('accepted') is True and ack.get('probe') is True and ack.get('report_id') == doc['report_id']
assert request(endpoint, credential=token)[0] == 404
root = Path('out/receiver');root.mkdir(parents=True, exist_ok=True)
(root/'receiver-probe.json').write_text(json.dumps({'passed': True, 'https_reachable': True, 'unauthenticated_upload_rejected': True, 'authenticated_probe_acknowledged': True, 'public_read_api_absent': True, 'device_verified': False, 'time': time.time()}, indent=2)+'\n')
print('PASS: deployed HTTPS receiver, authentication, matching ACK and no public read API; synthetic probe only, no phone data accessed')
