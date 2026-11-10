import json,os,re,subprocess
from pathlib import Path
assert os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
repo=os.environ['GITHUB_REPOSITORY'];sha=os.environ['GITHUB_SHA'];run=os.environ['GITHUB_RUN_ID'];tag='integrated-'+sha[:12]
def gh(*args):return subprocess.check_output(['gh',*args],text=True)
def api(path):return json.loads(gh('api',path))
assert repo=='zengwantin-rgb/fanpromax-ios'
assert not api(f'repos/{repo}')['private'], 'User explicitly requested public repository'
info=api(f'repos/{repo}/actions/runs/{run}');assert info['head_sha']==sha
jobs=api(f'repos/{repo}/actions/runs/{run}/jobs')['jobs'];completed={j['name']:j for j in jobs if j['name'] in ('build','ui')}
assert set(completed)=={'build','ui'} and all(j['conclusion']=='success' for j in completed.values())
root=Path('reports');root.mkdir()
gh('run','download',run,'--repo',repo,'--name','integrated-ui-'+sha,'--dir',str(root))
ui=json.loads((root/'report.json').read_text());assert ui['passed'] and not ui['failures']
gh('release','download',tag,'--repo',repo,'--pattern','package-report.json','--pattern','SHA256SUMS','--dir',str(root))
p=json.loads((root/'package-report.json').read_text());assert p['commit']==sha
assert p['signatures_verified'] and p['archive_crc_verified'] and p['original_resources_preserved'] and p['original_text_uuid_encryption_preserved']
assert not any(p[k] for k in ('aim_included','recoil_included','invincibility_implemented','damage_reduction_implemented','server_acceptance_verified','device_verified'))
url=json.loads(gh('release','view',tag,'--repo',repo,'--json','apiUrl'))['apiUrl'];release=api(url)
asset=next(a for a in release['assets'] if a['name']==p['file'])
assert asset['size']==p['bytes'] and asset['digest']=='sha256:'+p['sha256']
assert (root/'SHA256SUMS').read_text().strip()==p['sha256']+'  '+p['file']
(root/'publication-report.json').write_text(json.dumps({'commit':sha,'run':run,'build_and_ui_verified':True,'asset_digest_verified':True,'repository_visibility':'public_user_requested','device_verified':False},indent=2)+'\n')
gh('release','upload',tag,'--repo',repo,str(root/'publication-report.json'))
gh('release','edit',tag,'--repo',repo,'--draft=false','--prerelease')
print('PASS: hosted build/UI, user-requested public repository and exact source/asset digest verified before publication')
