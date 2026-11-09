"""Pinned, hosted-only survey before implementing native in-game controls."""
import importlib.util,json,os,sys
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
p=Path(__file__).with_name('inspect-reference.py')
spec=importlib.util.spec_from_file_location('integrated_reference',p)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
names=('CharacterMovement','MaxWalkSpeed','MaxWalkSpeedCrouched','MaxAcceleration','GetMaxSpeed',
 'CustomTimeDilation','MaxFlySpeed','MovementMode','SetMovementMode','SetActorEnableCollision',
 'VehicleRiderComponent','GetVehiclePawn','GetDriver','GetSeatIndex','VehicleMovementRef',
 'VehicleMovement','WheeledVehicleMovementComponent','SetThrottleInput','SetBrakeInput','SetSteeringInput',
 'SetActorLocation','SetActorLocationAndRotation','SetWorldLocation','SetPhysicsLinearVelocity',
 'SetEnableGravity','SetSimulatePhysics','bEnableGravity','bSimulatePhysics',
 'ServerMoveToVehicleSeat','VehicleSeatComponent','VehiclePawn','XtrmVehicle','XtrmWheeledVehicle',
 'Health','MaxHealth','CurrentHealth','GetHealth','GetMaxHealth','SetHealth',
 'bCanBeDamaged','CanBeDamaged','SetCanBeDamaged','TakeDamage','ReceiveAnyDamage','OnTakeAnyDamage',
 'DamageReduction','DamageMultiplier','DamageScale','DamageRate','Invincible','Invincibility','GodMode',
 'bInvulnerable','bInvincible','DamageComponent','HealthComponent','bIsInvincible','IsInvincible',
 'Armor','ArmorDamageReduction','ServerApplyDamage','ApplyDamage','Role','LocalRole','RemoteRole','HasAuthority')
m.main(exact_names=names,focus_entries=(0x1c6cc90,0x504f328,0x359be28,0x35a9ab0,0x3a0c86c),
 dispatch_focus=(),output='out/integrated-survey',
 discovery_pattern=r'(?:Invinc|Invulner|GodMode|DamageReduction|DamageMultiplier|DamageScale|DamageRate|MaxFlySpeed|Vehicle.*(?:Gravity|Velocity|Movement|Driver)|CanBeDamaged)',
 priority_names=names,context_limit=240,context_extent=0x900,context_extents={})
report_path=Path('out/integrated-survey/report.json')
report=json.loads(report_path.read_text())
report['purpose']='Static feasibility evidence for in-game movement/vehicle/damage controls; no aiming or recoil; no runtime effect claim'
report_path.write_text(json.dumps(report,indent=2)+'\n')
contexts='\n'.join('FILE '+p.name+'\n'+p.read_text() for p in sorted(Path('out/integrated-survey').glob('*.asm')))
assert len(contexts.encode())<35_000_000
Path('out/integrated-contexts.txt').write_text(contexts)
print('PASS: pinned iOS metadata/context survey; names and offsets alone do not establish runtime effects')
