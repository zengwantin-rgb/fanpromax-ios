"""Find iOS metadata/native getters for read-only weapon and vehicle labels."""
import importlib.util,json,os,sys
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
p=Path(__file__).with_name('inspect-reference.py')
spec=importlib.util.spec_from_file_location('label_reference',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
names=('XtrmWeapon','XtrmWeapon_Gun','XtrmWeaponProcessor','EquippedWeapons','CurrentWeaponIndex',
 'GetWeaponID','GetWeaponId','WeaponID','WeaponId','ItemID','ItemId','GetItemID','GetItemId',
 'WeaponName','GetWeaponName','GetDisplayName','DisplayName','ItemName','GetItemName',
 'WeaponType','GetWeaponType','WeaponData','ItemData','VehicleName','GetVehicleName',
 'VehicleType','GetVehicleType','VehicleID','VehicleId','VehicleData','GetVehicleData',
 'XtrmVehicle','XtrmWheeledVehicle','XtrmMotorbike','XtrmVehiclePawn',
 'Weapon_M416','Weap_M416','M416','M762','AKM','Dacia','ItemDisplayName')
m.main(exact_names=names,focus_entries=(),dispatch_focus=(),output='out/labels',
 discovery_pattern=r'(?:Weapon|Item|Vehicle).*(?:DisplayName|Name|ID|Id|Type)|(?:GetCurrentWeapon|GetEquippedWeapon)',
 priority_names=names,context_limit=150,context_extent=0x900,context_extents={})
report=json.loads(Path('out/labels/report.json').read_text());report['purpose']='Read-only iOS label discovery; no aiming, recoil, writes or input execution'
Path('out/labels/report.json').write_text(json.dumps(report,indent=2)+'\n')
combined=[]
for context in report['bounded_contexts']:
 name=context.get('file',context.get('filename',''))
 if name and (Path('out/labels')/name).is_file():combined.append('FILE '+name+'\n'+(Path('out/labels')/name).read_text())
# Include all explicitly bounded disassembly, never executable bytes.
if not combined:
 combined=['FILE '+p.name+'\n'+p.read_text() for p in sorted(Path('out/labels').glob('*.asm'))]
text='\n'.join(combined);assert len(text.encode())<35_000_000
Path('out/label-contexts.txt').write_text(text)
print('PASS: bounded, pinned iOS static label survey; no game execution or modification')
