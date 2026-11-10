"""Hosted-only synthetic execution of the pinned native cap helper and selection."""
import hashlib,json,math,os,struct,sys,zipfile
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
sys.path.insert(0,str(Path('analysis_tools').resolve()))
from warning_dispatch_patch import layout
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM
from unicorn.arm64_const import UC_ARM64_REG_X19,UC_ARM64_REG_S8,UC_ARM64_REG_S9,UC_ARM64_REG_CPACR_EL1
with zipfile.ZipFile(sys.argv[1]) as z:data=z.read('Payload/ExtremeGame.app/ExtremeGame')
assert hashlib.sha256(data).hexdigest()=='cf59f3663bba56b035024e71d814ffceecf86d5d99bd90873c2fd82372e3a0c7'
_,segments,_=layout(data);base=0x100000000

def read(rva,size):
 s=next(s for s in segments if s['vmaddr']<=base+rva and base+rva+size<=s['vmaddr']+s['size'])
 at=s['offset']+base+rva-s['vmaddr'];return data[at:at+size]

def execute(computed,cap):
 emu=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
 for rva,size in ((0x2300a78,20),(0x1c6d384,16)):
  emu.mem_map((base+rva)&~4095,4096);emu.mem_write(base+rva,read(rva,size))
 actor=0x40000000;emu.mem_map(actor,4096)
 emu.mem_write(actor+0xbf0,struct.pack('<f',500));emu.mem_write(actor+0xbf8,struct.pack('<f',cap))
 emu.reg_write(UC_ARM64_REG_CPACR_EL1,3<<20);emu.reg_write(UC_ARM64_REG_X19,actor)
 emu.reg_write(UC_ARM64_REG_S8,struct.unpack('<I',struct.pack('<f',computed))[0])
 emu.emu_start(base+0x1c6d384,base+0x1c6d394,count=20)
 return struct.unpack('<f',struct.pack('<I',emu.reg_read(UC_ARM64_REG_S9)))[0]

cases=[]
for cap in (650.0,800.0,1000.0):
 for computed in (640.0,900.0):
  normal=execute(computed,cap)
  for multiplier in (1.0,1.6,2.0,3.0):
   old=execute(computed*multiplier,cap)
   corrected=execute(computed*multiplier,cap*multiplier)
   expected=normal*multiplier
   assert math.isclose(corrected,expected,abs_tol=0.001),(computed,cap,multiplier,corrected,expected)
   cases.append({'synthetic_computed':computed,'synthetic_cap':cap,'multiplier':multiplier,'unscaled_cap_result':old,'scaled_cap_result':corrected,'expected':expected})
assert execute(640*3,800)==800
assert execute(640*3,800*3)==1920
Path('out/integrated/speed-cap-emulation.json').write_text(json.dumps({'passed':True,'cases':cases,
 'scope':'Original AArch64 leaf helper and clamp selection with synthetic state. Not full GetMaxSpeed, movement simulation, actual device values, or server acceptance.',
 'full_game_executed':False,'server_acceptance_verified':False},indent=2)+'\n')
print('PASS: pinned native clamp requires scaling its independent cap; 24 synthetic cases, no live-game claim')
