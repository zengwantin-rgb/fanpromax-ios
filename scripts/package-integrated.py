"""Add one new module to the exact user-supplied game; never execute game binaries."""
import hashlib,importlib.util,json,os,plistlib,shutil,subprocess,sys
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
p=module('integrated_package_base','integrated-package-base.py');loader=module('integrated_load_command','integrated-load-command.py')
source=Path(sys.argv[1]);dylib=Path(sys.argv[2]);out=Path('out/integrated')
assert p.digest(source)==p.EXPECTED_SHA256
root=Path('build/integrated-package');root.mkdir();p.extract(source,root);app=root/p.APP
binaries={}
for path in app.rglob('*'):
 if path.is_file():
  with path.open('rb') as f:magic=f.read(4)
  if magic==p.MACH_MAGIC:binaries[path]=p.macho_info(path);path.chmod(0o755)
executable=app/'ExtremeGame';assert binaries[executable]['uuid']==p.EXPECTED_UUID
original_resources=p.resource_digests(root,set(binaries));app_ent=p.entitlements(app)
dependencies={path:loader.dependency_names(path) for path in binaries}
frameworks=sorted(app.rglob('*.framework'),key=lambda path:len(path.parts),reverse=True)
accounted={executable}
for bundle in frameworks:
 info=plistlib.loads((bundle/'Info.plist').read_bytes());accounted.add(bundle/info['CFBundleExecutable'])
assert accounted==set(binaries),'Unhandled nested executable'
patch=loader.add_dependency(executable)
embedded=app/'Frameworks/FanProIntegrated.dylib';assert not embedded.exists();shutil.copy2(dylib,embedded);embedded.chmod(0o755)
subprocess.run(['codesign','--verify','--strict',str(embedded)],check=True)
for bundle in frameworks:p.sign(bundle,p.entitlements(bundle),Path('build/integrated-framework-entitlements.plist'))
p.sign(app,app_ent,Path('build/integrated-app-entitlements.plist'))
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
for path,identity in binaries.items():
 assert p.macho_info(path)==identity,'Original executable text/UUID/encryption changed'
 assert loader.dependency_names(path)==dependencies[path]+([loader.LIBRARY] if path==executable else [])
assert p.resource_digests(root,set(binaries)|{embedded})==original_resources
assert p.entitlements(app)==app_ent
ipa=out/'NEW_STATE-FanProMAX-integrated-i3.ipa';p.package(root,ipa)
report={'commit':os.environ['GITHUB_SHA'],'version':'integrated-i3','file':ipa.name,'bytes':ipa.stat().st_size,'sha256':p.digest(ipa),
 'module_sha256':p.digest(embedded),'module_load_command':patch,'original_text_uuid_encryption_preserved':True,
 'original_resources_preserved':True,'original_entitlements_preserved':True,'signatures_verified':True,'archive_crc_verified':True,
 'aim_included':False,'recoil_included':False,'character_speed_field_experiment':True,'vehicle_flight_experiment':True,
 'invincibility_implemented':False,'damage_reduction_implemented':False,'server_acceptance_verified':False,'device_verified':False}
(out/'package-report.json').write_text(json.dumps(report,indent=2)+'\n');(out/'SHA256SUMS').write_text(report['sha256']+'  '+ipa.name+'\n')
print('PASS: module loaded by one declared dependency; original executable text/resources/permissions preserved, signatures and full IPA CRC verified')
