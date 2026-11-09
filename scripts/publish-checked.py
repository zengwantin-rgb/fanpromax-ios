"""Publish an already checked candidate, with explicit source/job/digest verification."""
import hashlib,json,os,re,subprocess,zipfile
from pathlib import Path
assert os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
repo=os.environ['GITHUB_REPOSITORY'];sha=os.environ['CHECKED_SHA'];run=os.environ['CHECKED_RUN']
assert re.fullmatch('[0-9a-f]{40}',sha) and run.isdigit()
def gh(*args):return subprocess.check_output(['gh',*args],text=True)
def api(path):return json.loads(gh('api',path))
info=api(f'repos/{repo}/actions/runs/{run}')
assert info['head_sha']==sha and info['repository']['full_name']==repo
jobs=api(f'repos/{repo}/actions/runs/{run}/jobs?per_page=100')['jobs']
checked={j['name']:j for j in jobs if j['name'] in ('build','ui')}
assert set(checked)=={'build','ui'} and all(j['conclusion']=='success' for j in checked.values())
# Publishing changes can be newer; every compiled/tested source must remain identical.
subprocess.run(['git','diff','--exit-code',sha,'HEAD','--','apps','src','tests','scripts/build-on-github.sh','scripts/build-external-port.sh','scripts/verify_external.py','scripts/preview-external-ui.sh','scripts/render-brand.swift','scripts/check-ui-capture.swift'],check=True)
root=Path('reports');root.mkdir(exist_ok=True);tag='ios-'+sha[:12]
gh('run','download',run,'--repo',repo,'--name','fanpromax-ui-'+sha,'--dir',str(root))
gh('release','download',tag,'--repo',repo,'--pattern','package-report.json','--pattern','SHA256SUMS','--dir',str(root))
report=json.loads((root/'package-report.json').read_text());assert report['commit']==sha
assert report['archive_crc_verified'] and report['entitlements_verified'] and report['signature_pages_verified']>0
assert not report['full_android_feature_port'] and not report['new_bundle_device_verified']
assert not report['aim_implemented'] and not report.get('recoil_implemented',False)
if report['app_version']=='0.2.0':
 assert report['settings_transfer_implemented'] and report['import_preserves_sampling_state']
 assert not report['settings_transfer_includes_credentials'] and report['aim_and_recoil_excluded']
release=json.loads(gh('release','view',tag,'--repo',repo,'--json','apiUrl'))
asset=api(release['apiUrl'])
ipa=next(a for a in asset['assets'] if a['name']==report['file'])
assert ipa['size']==report['bytes'] and ipa['digest']=='sha256:'+report['sha256']
assert (root/'SHA256SUMS').read_text().strip()==f"{report['sha256']}  {report['file']}"
with zipfile.ZipFile(root/'FanProMAX-UI-preview.zip') as z:
 assert sum(i.file_size for i in z.infolist())<60_000_000
 for name in ('ui-smoke.json','ui-smoke-large-text.json'):
  result=json.loads(z.read('ui-preview/'+name));assert result['passed'] and not result['failures']
assert api(f'repos/{repo}')['private'], 'Keep the project private for publication'
publication={'source_sha':sha,'source_run':int(run),'source_and_ui_jobs_verified':True,'compiled_sources_unchanged':True,'package_digest_verified':True,'repository_private':True,'publisher_run':int(os.environ['GITHUB_RUN_ID']),'publisher_commit':os.environ['GITHUB_SHA'],'ipa_sha256':report['sha256'],'new_bundle_device_verified':False}
(root/'publication-report.json').write_text(json.dumps(publication,indent=2)+'\n')
gh('release','upload',tag,'--repo',repo,'--clobber',str(root/'FanProMAX-UI-preview.zip'),str(root/'publication-report.json'))
gh('release','edit',tag,'--repo',repo,'--draft=false','--prerelease')
print('PASS: verified prior build/UI results, unchanged compiled source and release digest; private prerelease published')
