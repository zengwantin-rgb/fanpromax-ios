"""Hosted-only static review of APK movement implementations. Never execute input."""
import hashlib,io,json,os,re,struct,sys,zipfile
from pathlib import Path
from cryptography.hazmat.primitives.ciphers import Cipher,algorithms,modes
from elftools.elf.elffile import ELFFile
from capstone import Cs,CS_ARCH_ARM64,CS_MODE_ARM
assert sys.platform=='darwin' and os.environ['RUNNER_ENVIRONMENT']=='github-hosted'
source=Path(sys.argv[1]);out=Path('out/motion-review');out.mkdir(parents=True)
raw=source.read_bytes();assert hashlib.sha256(raw).hexdigest()=='02d6e9e30f0f25865552c75ae66e625c0466b017114ba9e5051edb60655024d9'
with zipfile.ZipFile(io.BytesIO(raw)) as z:packed=z.read('assets/libfanpro.dat')
key=hashlib.sha256(b'FanProMAX-bundled-payload-2026').digest()
decoder=Cipher(algorithms.AES(key),modes.CTR(packed[8:24])).decryptor();data=decoder.update(packed[24:])+decoder.finalize()
assert hashlib.sha256(data).hexdigest()=='5f4ba230657469e44105de501afb5cd98da7e5b71cdfa6bfeca481180b1bd8b6'
elf=ELFFile(io.BytesIO(data));sections=[s for s in elf.iter_sections() if s['sh_type']!='SHT_NOBITS']
symbols={};labels={};relocations={}
for name in ('.dynsym','.symtab'):
 sec=elf.get_section_by_name(name)
 if sec:
  for sym in sec.iter_symbols():
   if sym['st_value'] and sym.name:
    labels[int(sym['st_value'])]=sym.name
    if sym['st_info']['type']=='STT_FUNC' and sym['st_size']:symbols[int(sym['st_value'])]={'name':sym.name,'address':int(sym['st_value']),'size':int(sym['st_size'])}
for sec in elf.iter_sections():
 if sec['sh_type']!='SHT_RELA':continue
 table=elf.get_section(sec['sh_link'])
 for rel in sec.iter_relocations():
  sym=table.get_symbol(rel['r_info_sym']) if rel['r_info_sym'] else None
  target=int(sym['st_value']) if sym and sym['st_value'] else int(rel['r_addend'])
  if target:relocations[int(rel['r_offset'])]=target
plt=elf.get_section_by_name('.plt');relplt=elf.get_section_by_name('.rela.plt')
if plt and relplt:
 table=elf.get_section(relplt['sh_link'])
 for n,rel in enumerate(relplt.iter_relocations()):labels[int(plt['sh_addr'])+32+n*16]=table.get_symbol(rel['r_info_sym']).name+'@plt'
def read(address,size):
 sec=next((s for s in sections if s['sh_addr']<=address and address+size<=s['sh_addr']+s['sh_size']),None)
 if sec is None:return b''
 at=int(sec['sh_offset'])+address-int(sec['sh_addr']);return data[at:at+size]
feature=re.compile(r'飞车|飞天|加速|蛇皮|漂移|防翻|刹车|gravity|velocity|speed|movement|correction|authoritative',re.I)
def describe(address):
 if address in labels:return labels[address]
 raw=read(address,180).split(b'\0')[0]
 try:s=raw.decode('utf-8')
 except UnicodeError:return ''
 if len(s)>96 or not feature.search(s) or re.search(r'https?://|[A-Za-z0-9+/=_-]{28,}',s):return ''
 return s if all(c.isprintable() for c in s) else ''
md=Cs(CS_ARCH_ARM64,CS_MODE_ARM)
roots=[s for s in symbols.values() if any(x in s['name'] for x in ('更新对象数据','更新地址数据','绘制悬浮窗','_ZN6绘制C2','callWrite','writeRemoteMemory'))]
queue=[(s['address'],0) for s in roots];seen=set();references=[];calls=[];summaries=[]
def add(value,delta):return (value[0],value[1]+delta) if isinstance(value,tuple) else value+delta
for address,depth in queue:
 if address in seen or len(seen)>=70:continue
 sym=symbols.get(address)
 if not sym or sym['size']>100000:continue
 seen.add(address);instructions=list(md.disasm(read(address,sym['size']),address));regs={'x0':('this',0)};lines=[]
 for n,ins in enumerate(instructions):
  parts=ins.op_str.split(', ');note=[]
  if ins.mnemonic in ('adrp','adr') and len(parts)==2 and parts[1].startswith('#'):
   regs[parts[0]]=int(parts[1][1:],0)
  elif ins.mnemonic=='mov' and len(parts)==2:
   if parts[1] in regs:regs[parts[0]]=regs[parts[1]]
   else:regs.pop(parts[0],None)
  elif ins.mnemonic=='add' and len(parts)==3 and parts[1] in regs and parts[2].startswith('#'):
   try:regs[parts[0]]=add(regs[parts[1]],int(parts[2][1:],0))
   except ValueError:regs.pop(parts[0],None)
  elif ins.mnemonic in ('ldr','ldrb','ldrh','str','strb','strh'):
   match=re.search(r'\[(x\d+)(?:, #((?:0x)?[0-9a-f]+))?\]',ins.op_str)
   effective=None
   if match and match[1] in regs:
    effective=add(regs[match[1]],int(match[2] or '0',0))
    if isinstance(effective,tuple):note.append('this_field+'+hex(effective[1]))
    elif describe(effective):note.append(describe(effective))
   if ins.mnemonic.startswith('ldr'):
    regs.pop(parts[0],None)
    if isinstance(effective,int) and effective in relocations:regs[parts[0]]=relocations[effective]
  elif ins.mnemonic in ('bl','b') and ins.op_str.startswith('#'):
   target=int(ins.op_str[1:],0);name=labels.get(target,'')
   if name:note.append(name)
   if ins.mnemonic=='bl':
    args={reg:str(regs[reg]) for reg in ('x0','x1','x2','x3') if reg in regs}
    calls.append({'caller':sym['name'],'pc':hex(ins.address),'target':hex(target),'name':name,'linear_argument_candidates':args})
    if depth<1 and target in symbols and symbols[target]['size']<=1800 and not re.search(r'aim|自瞄|recoil|auth|license|hmac|ssl|http|RSA|AES|EVP|ImGui|_ZNSt',name,re.I):queue.append((target,depth+1))
    for register in ['x'+str(i) for i in range(19)]:regs.pop(register,None)
  elif parts and ins.mnemonic not in ('cmp','tst','tbz','tbnz','cbz','cbnz','ret','stp','stur'):
   if ins.mnemonic not in ('adr','adrp','add','mov','ldr','ldrb','ldrh','str','strb','strh'):regs.pop(parts[0],None)
  if parts and parts[0] in regs and isinstance(regs[parts[0]],int):
   value=regs[parts[0]];name=describe(value)
   if name:
    note.append(name)
    if feature.search(name):references.append({'function':sym['name'],'pc':hex(ins.address),'target':hex(value),'name':name,'instruction_index':n})
  lines.append(hex(ins.address)+': '+ins.mnemonic+' '+ins.op_str+(' ; '+' | '.join(dict.fromkeys(note)) if note else ''))
 filename=hex(address)[2:]+'.asm';(out/filename).write_text('\n'.join(lines)+'\n')
 summaries.append({**sym,'address':hex(address),'file':filename,'instructions':len(instructions),'depth':depth})
report={'apk_sha256':hashlib.sha256(raw).hexdigest(),'payload_sha256':hashlib.sha256(data).hexdigest(),
 'input_executed':False,'network_calls_by_input':False,'functions':summaries,'feature_references':references,
 'direct_calls':calls,'limits':['Full disassembly of selected movement worker and UI roots, with at most one level of bounded direct callees.',
 'Linear register annotations are candidates, not proven control-flow dataflow or runtime addresses.',
 'ELF addresses and Android offsets cannot be transplanted into the iOS binary.',
 'No server behavior, actual speed multiplier or stable flight is established by this static review.']}
(out/'apk-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'functions':len(summaries),'movement_references':len(references),'calls':len(calls),'input_executed':False}))
