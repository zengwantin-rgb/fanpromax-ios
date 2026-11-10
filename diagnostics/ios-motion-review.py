"""Hosted static inspection only: final speed policy and character initialization."""
import bisect,hashlib,json,os,struct,sys,zipfile
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
sys.path.insert(0,str(Path('analysis_tools').resolve()))
from warning_dispatch_patch import layout
from capstone import Cs,CS_ARCH_ARM64,CS_MODE_ARM
with zipfile.ZipFile(sys.argv[1]) as z:data=z.read('Payload/ExtremeGame.app/ExtremeGame')
assert hashlib.sha256(data).hexdigest()=='cf59f3663bba56b035024e71d814ffceecf86d5d99bd90873c2fd82372e3a0c7'
_,segments,_=layout(data);base=0x100000000
cursor=32;starts=[]
for _ in range(struct.unpack_from('<I',data,16)[0]):
 command,length=struct.unpack_from('<II',data,cursor)
 if command==0x26:
  offset,size=struct.unpack_from('<II',data,cursor+8);rva=0;delta=0;shift=0
  for b in data[offset:offset+size]:
   delta|=(b&127)<<shift
   if b&128:shift+=7;continue
   if delta==0:break
   rva+=delta;starts.append(rva);delta=0;shift=0
 cursor+=length
assert starts
md=Cs(CS_ARCH_ARM64,CS_MODE_ARM);out=Path('out/ios-motion-review');out.mkdir(parents=True)
roots=[0x22c28b8,0x2300a78,0x2300480,0x1c6cc90,0x505566c];functions=[]
for rva in roots:
 index=bisect.bisect_left(starts,rva);assert starts[index]==rva,hex(rva)
 size=starts[index+1]-rva;assert size<=100000,(hex(rva),size)
 segment=next(s for s in segments if s['vmaddr']<=base+rva and base+rva+size<=s['vmaddr']+s['size'])
 offset=segment['offset']+base+rva-segment['vmaddr']
 instructions=list(md.disasm(data[offset:offset+size],base+rva))
 name=hex(rva)[2:]+'.asm'
 (out/name).write_text('\n'.join(hex(i.address-base)+': '+i.mnemonic+' '+i.op_str for i in instructions)+'\n')
 functions.append({'rva':hex(rva),'bytes':size,'file':name,'sha256':hashlib.sha256(data[offset:offset+size]).hexdigest()})
(out/'ios-report.json').write_text(json.dumps({'functions':functions,'input_executed':False,'runtime_cap_value_known':False,'server_behavior_verified':False},indent=2)+'\n')
