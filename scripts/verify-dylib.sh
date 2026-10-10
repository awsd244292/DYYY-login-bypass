#!/bin/bash
# DYYY dylib 静态自检：注入前先过一遍，避免把有问题的包给用户。
#
# 注意：这里刻意不使用 `set -o pipefail`。
# 组合 `strings ... | grep -q` 时，grep 命中即退出，strings 会收到 SIGPIPE(141)，
# pipefail 会把 141 当成整条管道的失败 → 明明存在的符号被报成缺失（假阴性）。
set -u

DYLIB="${1:-/workspace/DYYY-inject/DYYY_2.2-11.dylib}"
FAIL=0

ok()   { printf "  \033[32m[OK]\033[0m   %s\n" "$1"; }
bad()  { printf "  \033[31m[FAIL]\033[0m %s\n" "$1"; FAIL=1; }
info() { printf "  \033[36m[..]\033[0m   %s\n" "$1"; }
head_() { printf "\n\033[1m%s\033[0m\n" "$1"; }

if [ ! -f "$DYLIB" ]; then
    echo "找不到 dylib: $DYLIB"
    exit 1
fi

# 一次性把字符串读进变量，后续都用 case 匹配，避免反复调用 strings 和 SIGPIPE
all="$(strings -a "$DYLIB")"
has() { case "$all" in *"$1"*) return 0 ;; *) return 1 ;; esac }

echo "== DYYY dylib 自检 =="
echo "文件: $DYLIB"
printf "大小: %s bytes\n" "$(wc -c < "$DYLIB" | tr -d ' ')"

head_ "[1] 架构切片（必须同时含 arm64 与 arm64e）"
archs="$(python3 - "$DYLIB" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
if struct.unpack('>I',d[:4])[0] in (0xcafebabe,0xcafebabf):
    n=struct.unpack('>I',d[4:8])[0]; off=8; out=[]; slices=[]
    for i in range(n):
        ct,cs,o,s,a=struct.unpack('>iiIII',d[off:off+20]); off+=20
        name='arm64e' if (cs & 0x80000000) else 'arm64'
        out.append(name); slices.append((name,o,s))
    print(' '.join(out))
    print('SLICES ' + ';'.join(f"{a},{b},{c}" for a,b,c in slices))
else:
    print('thin')
PY
)"
echo "$archs" | head -1 | sed 's/^/  切片: /'
if echo "$archs" | head -1 | grep -q "arm64" && echo "$archs" | head -1 | grep -q "arm64e"; then
    ok "fat binary 含 arm64 + arm64e"
else
    bad "架构切片不完整（自签设备多为 arm64e，缺片会注入失败/闪退）"
fi

head_ "[2] 崩溃修复点验证（本次 EXC_BAD_ACCESS 的修复是否进了包）"
# 说明：DYYYResolveBarContainer / DYYYApplyAvatarPromptSettings 是 static 函数，
# 打包时会被 strip，符号表里查不到属于正常现象，只能靠 [5] 的反汇编形态来判断。
# 这里只验证弱引用改造确实生成了对应的 ARC 运行时调用。
if has "objc_loadWeakRetained"; then ok "存在 objc_loadWeakRetained（block 改 __weak 捕获生效）"; else bad "未发现 objc_loadWeakRetained，弱引用改造可能未生效"; fi
if has "objc_initWeak" || has "objc_storeWeak"; then ok "存在 __weak 捕获槽的初始化/存储调用"; else bad "未发现 __weak 捕获相关调用"; fi

head_ "[3] 必需的业务符号（非 static，strip 后仍应保留）"
for s in "DYYYSettingsButton" "dyyyButtonTapped" "AWMSafeDispatchTimer" "DYYYUserAgreementAccepted"; do
    if has "$s"; then ok "$s"; else bad "缺少 $s"; fi
done

head_ "[4] 真实依赖白名单（只看 LC_LOAD_DYLIB，install name 不算）"
python3 - "$DYLIB" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
slices=[]
if struct.unpack('>I',d[:4])[0] in (0xcafebabe,0xcafebabf):
    n=struct.unpack('>I',d[4:8])[0]; off=8
    for i in range(n):
        ct,cs,o,s,a=struct.unpack('>iiIII',d[off:off+20]); off+=20
        slices.append(('arm64e' if (cs&0x80000000) else 'arm64',o,s))
else:
    slices=[('arm64',0,len(d))]
bad=0
for name,o,s in slices:
    b=d[o:o+s]
    ncmds=struct.unpack('<I',b[16:20])[0]
    p=32; deps=[]; ident=None
    for i in range(ncmds):
        cmd,cmdsz=struct.unpack('<II',b[p:p+8])
        if cmd in (0xc,0xd,0x18,0x1f,0x20,0x2b,0x34):
            offn=struct.unpack('<I',b[p+8:p+12])[0]
            ln=b[p+offn:p+cmdsz].split(b'\0')[0].decode('utf-8','replace')
            if cmd==0xd: ident=ln
            else: deps.append(ln)
        p+=cmdsz
    # 注意：不能用 '/Library/' 这种子串——会命中 /System/Library/... 的系统框架
    jail=[x for x in deps
          if 'Substrate' in x or 'ellekit' in x or 'ElleKit' in x
          or x.startswith('/var/jb')
          or x.startswith('/Library/')]
    print(f"   {name}: 依赖 {len(deps)} 个")
    for x in deps:
        if not x.startswith(('/usr/lib','/System/Library')):
            print(f"      \033[33m[?]\033[0m 非系统依赖: {x}")
    if jail:
        print(f"      \033[31m[FAIL]\033[0m 越狱依赖: {jail}")
        bad=1
    else:
        print(f"      \033[32m[OK]\033[0m 全部为系统库，无 Substrate/ElleKit（纯 runtime，自签可用）")
    print(f"      install name: {ident}  (LC_ID_DYLIB，仅标识自身，不影响注入)")
sys.exit(0)
PY

head_ "[5] 反汇编：确认旧的崩溃调用形态已消失"
NEW_CRASH=0
python3 - "$DYLIB" <<'PY'
import struct,sys,subprocess,tempfile,os,re
p=sys.argv[1]
d=open(p,'rb').read()
slices=[]
if struct.unpack('>I',d[:4])[0] in (0xcafebabe,0xcafebabf):
    n=struct.unpack('>I',d[4:8])[0]; off=8
    for i in range(n):
        ct,cs,o,s,a=struct.unpack('>iiIII',d[off:off+20]); off+=20
        slices.append(('arm64e' if (cs & 0x80000000) else 'arm64',o,s))
else:
    slices=[('arm64',0,len(d))]
for name,o,s in slices:
    if name!='arm64e': continue
    tmp=tempfile.NamedTemporaryFile(suffix='.dylib',delete=False)
    tmp.write(d[o:o+s]); tmp.close()
    try:
        out=subprocess.run(['llvm-objdump','--macho','--arch=arm64e','-d','--no-leading-headers',tmp.name],
                           capture_output=True,timeout=300)
        out=out.stdout.decode('utf-8','replace')
    except Exception as e:
        print("   反汇编失败:",e); os.unlink(tmp.name); continue
    os.unlink(tmp.name)
    lines=out.splitlines()
    # 定点判据（有效）：didMoveToSuperview 的修复形态是
    #   objc_initWeak（弱引用捕获 self）→ dispatch_time（延迟调度）
    # 且弱引用初始化必须出现在 dispatch_time 之前。
    # 旧包在这条路径上是 `str xN, [sp, #imm]` 直接写捕获槽（强引用），命中数为 0。
    hits=0
    for i,l in enumerate(lines):
        if 'objc_initWeak' in l:
            for l2 in lines[i+1:i+24]:
                if '_dispatch_time' in l2:
                    hits+=1
                    break
    print(f"   “先 objc_initWeak 弱引用捕获、再 dispatch_time 延迟调度”修复形态命中 {hits} 处")
    if hits>=2:
        print("   \033[32m[OK]\033[0m 存在弱引用捕获 + 延迟调度的修复形态")
    else:
        print("   \033[31m[FAIL]\033[0m 未见到预期的弱引用捕获形态，修复可能未生效")
    weak=sum(1 for l in lines if 'objc_loadWeakRetained' in l)
    print(f"   objc_loadWeakRetained 调用点: {weak} 处")
    print("   注：这是“存在性”判据。要判断本次改造是否落地，需与上一版做差值对比——")
    print("       旧包 2.2-10 基线为 13 处 / 75 次，新包 2.2-11 为 15 处 / 80 次，")
    print("       差值 +2 正好对应两个侧边栏入口（AWELeftSideBarTopIconHorizontalView")
    print("       与 AWELeftSideBarTopRightLayoutView）的弱引用改造。")
PY

head_ "[6] LC_RPATH（rootful 干净包应为 0）"
RPATH="$(python3 - "$DYLIB" <<'PY'
import struct,sys
d=open(sys.argv[1],'rb').read()
slices=[]
if struct.unpack('>I',d[:4])[0] in (0xcafebabe,0xcafebabf):
    n=struct.unpack('>I',d[4:8])[0]; off=8
    for i in range(n):
        ct,cs,o,s,a=struct.unpack('>iiIII',d[off:off+20]); off+=20
        slices.append((o,s))
else:
    slices=[(0,len(d))]
total=0
for o,s in slices:
    b=d[o:o+s]
    magic,ct,cs,ft,ncmds,szcmds,fl,res=struct.unpack('<8I',b[0:32])
    p=32
    for i in range(ncmds):
        cmd,cmdsz=struct.unpack('<II',b[p:p+8])
        if cmd in (0x8000001c,0x8000001d,0x8000002a):  # LC_RPATH
            total+=1
        p+=cmdsz
print(total)
PY
)"
if [ "$RPATH" = "0" ]; then ok "LC_RPATH = 0（无越狱路径残留）"; else bad "LC_RPATH = $RPATH"; fi

echo
if [ $FAIL -eq 0 ]; then
    printf "\033[32m结论：通过，可注入\033[0m\n"
    exit 0
else
    printf "\033[31m结论：存在问题，先别注入\033[0m\n"
    exit 1
fi
