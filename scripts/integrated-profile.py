"""Generate runtime fingerprints only from the pinned original on hosted macOS."""
import hashlib,json,os,struct,sys,zipfile
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
sys.path.insert(0,str(Path('analysis_tools').resolve()))
import warning_dispatch_patch as macho
from capstone import Cs,CS_ARCH_ARM64,CS_MODE_ARM
with zipfile.ZipFile(sys.argv[1]) as z:data=z.read('Payload/ExtremeGame.app/ExtremeGame')
assert hashlib.sha256(data).hexdigest()=='cf59f3663bba56b035024e71d814ffceecf86d5d99bd90873c2fd82372e3a0c7'
_,segments,_=macho.layout(data);base=0x100000000
def read(rva,size):
 s=next(s for s in segments if s['vmaddr']<=base+rva and base+rva+size<=s['vmaddr']+s['size'])
 at=s['offset']+base+rva-s['vmaddr'];return data[at:at+size]
for descriptor,name_at,offset in ((0x7b21568,0x6ba99b5,0x6dc),(0x7b20aa0,0x6ba956f,0x420)):
 assert struct.unpack('<Q',read(descriptor,8))[0]&((1<<36)-1)==base+name_at
 assert struct.unpack('<I',read(descriptor+36,4))[0]==offset
md=Cs(CS_ARCH_ARM64,CS_MODE_ARM)
def instructions(rva,size):return [(x.mnemonic,x.op_str) for x in md.disasm(read(rva,size),base+rva)]
for rva,size,expected in ((0x59a1a3c,0x90,('ldr','x8, [x8, #0x818]')),
 (0x59a1a00,0x3c,('ldr','x8, [x8, #0x820]')),(0x59a4788,0x134,('ldr','x8, [x8, #0x690]'))):
 assert expected in instructions(rva,size),(hex(rva),expected)
assert ('bl',' #0x105517194'.strip()) in instructions(0x59a46f4,0x90)
assert ('ldp','s0, s1, [sp, #0x14]') in instructions(0x59a4788,0x134)
assert ('ldr','x2, [sp, #8]') in instructions(0x59a4788,0x134)
assert instructions(0x59a0718,8)==[('adrp','x8, #0x1080ae000'),('ldr','x0, [x8, #0x820]')]
assert instructions(0x5057580,16)==[('ldr','s0, [x0, #0xbfc]'),('ldr','s1, [x0, #0xc00]'),('ldr','s2, [x0, #0xc04]'),('ret','')]
assert struct.unpack('<Q',read(0x7127e10+0x480,8))[0]&((1<<36)-1)==base+0x1c6cc90
assert instructions(0x2300a78,20)==[('ldr','s0, [x0, #0xbf0]'),('ldr','s1, [x0, #0xbf8]'),('fsub','s1, s1, s0'),('fadd','s0, s0, s1'),('ret','')]
assert ('bl','#0x102300a78') in instructions(0x1c6d384,20)
assert ('fcsel','s9, s8, s0, ls') in instructions(0x1c6d384,20)
entries=(0x2300a78,0x1c6d384,0x5057580,0x1c6cc90,0x59a0718,0x505566c,0x5517194,0x59a1a3c,0x59a1a00,0x59a4788,0x3b7804c)
lines=['#pragma once','#include "PortCore.hpp"','#include <cstring>','namespace fanpro {','inline bool verifyProfile(const nsport::Memory &m) {','unsigned char actual[32];']
for n,rva in enumerate(entries):
 raw=read(rva,32);lines.append('static const unsigned char expected%d[]={%s};'%(n,','.join(hex(v) for v in raw)))
 lines.append('if(!m.bytes(m.base+0x%x,actual,32) || std::memcmp(actual,expected%d,32))return false;'%(rva,n))
lines+=['return true;','}','}'];Path('build/VerifiedProfile.hpp').write_text('\n'.join(lines)+'\n')
Path('out/integrated/profile-report.json').write_text(json.dumps({'executable_sha256':hashlib.sha256(data).hexdigest(),
 'walking_offset':'0x6dc','crouching_offset':'0x420','native_abi_callsite_checked':True,'primitive_component_singleton':'0x80ae820','native_fingerprints':[hex(v) for v in entries],
 'runtime_effect_verified':False},indent=2)+'\n')
print('PASS: pinned property descriptors, native virtual call slots, vector ABI call-site registers and generated runtime fingerprints')
