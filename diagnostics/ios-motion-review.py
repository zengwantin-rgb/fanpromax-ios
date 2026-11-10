"""Hosted static inspection only: final speed policy and character initialization."""
import bisect,hashlib,json,os,struct,sys,zipfile
from pathlib import Path
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
sys.path.insert(0,str(Path('analysis_tools').resolve()))
from warning_dispatch_patch import layout
from capstone import Cs,CS_ARCH_ARM64,CS_MODE_ARM
with zipfile.ZipFile(sys.argv[1]) as z:data=z.read('Payload/ExtremeGame.app/ExtremeGame')
assert hashlib.sha256(data).hexdigest()=='cf59f3663bba56b035024e71d814ffceecf86d5d99bd90873c2fd82372e3a0c7'
_,segments,sections=layout(data);base=0x100000000
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
starts=sorted(set(starts))
md=Cs(CS_ARCH_ARM64,CS_MODE_ARM);out=Path('out/ios-motion-review');out.mkdir(parents=True)
roots=[0x54c2cd8,0x54c4e88,0x54c4f78,0x549d6a8,0x54c2300,0x54910e0,0x22bc520,0x22c28b8,0x2300a78,0x2300480,0x1c6cc90,0x505566c];functions=[]
virtual_targets={}
for slot in (0x5d8,0x5e8):
 address=base+0x7127e10+slot
 segment=next(v for v in segments if v['vmaddr']<=address and address+8<=v['vmaddr']+v['size'])
 at=segment['offset']+address-segment['vmaddr']
 target=(struct.unpack_from('<Q',data,at)[0]&((1<<36)-1))-base
 assert 0<target<0x6100000
 virtual_targets[target]=slot
 roots.append(target)
for rva in roots:
 index=bisect.bisect_left(starts,rva)
 exact=index+1<len(starts) and starts[index]==rva
 size=starts[index+1]-rva if exact else 0x100 if rva in virtual_targets else {0x54c2cd8:0x200,0x54c4e88:0x300,0x54c4f78:0x200,0x549d6a8:0x100,0x54c2300:0x400,0x54910e0:0x500,0x22bc520:0x6400,0x22c28b8:4,0x2300a78:20,0x2300480:0x500,0x1c6cc90:0x800,0x505566c:0x300}[rva]
 assert size<=100000,(hex(rva),size)
 segment=next(s for s in segments if s['vmaddr']<=base+rva and base+rva+size<=s['vmaddr']+s['size'])
 offset=segment['offset']+base+rva-segment['vmaddr']
 instructions=list(md.disasm(data[offset:offset+size],base+rva))
 name=hex(rva)[2:]+'.asm'
 (out/name).write_text('\n'.join(hex(i.address-base)+': '+i.mnemonic+' '+i.op_str for i in instructions)+'\n')
 functions.append({'rva':hex(rva),'bytes':size,'extent_kind':'function_starts' if exact else 'bounded_context_not_proven_function_extent','file':name,'virtual_slot':hex(virtual_targets[rva]) if rva in virtual_targets else None,'sha256':hashlib.sha256(data[offset:offset+size]).hexdigest()})
# Find direct unsigned-offset references; object type is not inferred from an offset.
references=[];contexts=[]
for section in sections:
 if section['name']!='__text':continue
 raw=data[section['offset']:section['offset']+section['size']]
 for index,(word,) in enumerate(struct.iter_unpack('<I',raw[:len(raw)//4*4])):
  if word & 0x3b000000 != 0x39000000:continue
  scale=(word>>30)&3
  if ((word>>10)&4095)*(1<<scale) not in (0xbf0,0xbf8,0x17e8):continue
  pc=section['address']-base+index*4
  decoded=list(md.disasm(raw[index*4:index*4+4],base+pc))
  if not decoded or not any(v in decoded[0].op_str for v in ('#0xbf0]', '#0xbf8]', '#0x17e8]')):continue
  instruction=decoded[0]
  begin=max(0,index*4-256);end=min(len(raw),index*4+260)
  filename='reference-'+hex(pc)[2:]+'.asm'
  contexts.append('CONTEXT '+filename+'\n'+'\n'.join(hex(i.address-base)+': '+i.mnemonic+' '+i.op_str for i in md.disasm(raw[begin:end],section['address']+begin)))
  references.append({'pc':hex(pc),'instruction':instruction.mnemonic+' '+instruction.op_str,'context':filename,'object_identity_proven':False})
(out/'field-contexts.txt').write_text('\n\n'.join(contexts)+'\n')
(out/'field-references.json').write_text(json.dumps(references,indent=2)+'\n')
(out/'ios-report.json').write_text(json.dumps({'functions':functions,'input_executed':False,'runtime_cap_value_known':False,'server_behavior_verified':False},indent=2)+'\n')
