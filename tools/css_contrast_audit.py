#!/usr/bin/env python3
"""
Static contrast audit.

The live scanner only measures what it can get on screen. A tooltip that
rests at opacity:0, a leaderboard row that needs an API answer, a state class
that only appears mid-drag - none of those are ever measured, and that is
exactly where the white-on-white bubble hid.

So this reads the stylesheet instead. It resolves every var() against :root,
then for each rule that sets BOTH a colour and a background, measures the
pair. For a rule that sets only a colour it walks the selector back to the
nearest ancestor rule that sets a background, and measures against that.
"""
import io,re,sys

def lin(c):
    c=c/255.0
    return c/12.92 if c<=0.03928 else ((c+0.055)/1.055)**2.4
def lum(h):
    h=h.lstrip('#')
    if len(h)==3: h=''.join(x*2 for x in h)
    r,g,b=[int(h[i:i+2],16) for i in (0,2,4)]
    return .2126*lin(r)+.7152*lin(g)+.0722*lin(b)
def ratio(a,b):
    la,lb=lum(a),lum(b); return (max(la,lb)+.05)/(min(la,lb)+.05)

src=io.open(sys.argv[1],encoding="utf-8").read()
css="\n".join(re.findall(r"<style>(.*?)</style>",src,re.S))
css=re.sub(r"/\*.*?\*/","",css,flags=re.S)

# --- resolve :root ------------------------------------------------------
root=re.search(r":root\{(.*?)\}",css,re.S).group(1)
VAR={}
for m in re.finditer(r"(--[\w-]+)\s*:\s*([^;]+)",root):
    VAR[m.group(1)]=m.group(2).strip()
for _ in range(4):
    for k,v in list(VAR.items()):
        VAR[k]=re.sub(r"var\((--[\w-]+)[^)]*\)",lambda m:VAR.get(m.group(1),m.group(0)),v)

HEX=re.compile(r"#[0-9A-Fa-f]{3,8}\b")
def solid(val):
    """Every opaque colour a background can present, as a list.

    A gradient is not one colour, so returning None for it - which this used
    to do - silently skipped the trophy badge, whose white icon sits on a
    gold-to-lime ramp at 1.66:1 and 1.34:1. Text over a gradient has to clear
    the bar against EVERY stop, so all the stops come back and each is
    measured."""
    v=re.sub(r"var\((--[\w-]+)[^)]*\)",lambda m:VAR.get(m.group(1),""),val).strip()
    if "transparent" in v or "currentcolor" in v.lower(): return None
    if v.startswith("rgba") or v.startswith("hsla"): return None
    h=[x.upper() for x in HEX.findall(v) if len(x) not in (5,9)]
    if not h: return None
    if "gradient" in v: return h              # measure against each stop
    return h[:1] if len(h)==1 else None

# --- collect rules ------------------------------------------------------
rules=[]
for m in re.finditer(r"([^{}]+)\{([^{}]*)\}",css):
    sel=" ".join(m.group(1).split())
    if sel.startswith("@") or sel.startswith(":root"): continue
    d=m.group(2)
    # LAST declaration wins inside a block, not the first. .banked .blabel
    # sets color twice and the first one is dead; taking it reported a
    # failure that does not exist.
    fgm=re.findall(r"(?:^|;)\s*color\s*:\s*([^;]+)",d)
    bgm=re.findall(r"(?:^|;)\s*background(?:-color)?\s*:\s*([^;]+)",d)
    fg=fgm[-1] if fgm else None
    bgs=bgm[-1] if bgm else None
    size=re.search(r"font-size\s*:\s*([\d.]+)px",d)
    bold=re.search(r"font-weight\s*:\s*(\d+|bold)",d)
    rules.append({"sel":sel,
                  "fg":(solid(fg) or [None])[0] if fg else None,
                  "bg":solid(bgs) if bgs else None,
                  "px":float(size.group(1)) if size else None,
                  "bold":bool(bold and (bold.group(1)=="bold" or int(bold.group(1))>=700))})

# a background a selector establishes, for ancestor lookup
bgof={}
for r in rules:
    if r["bg"]:
        for one in r["sel"].split(","):
            bgof[one.strip()]=r["bg"]          # a list, one entry per stop
PAGE=VAR.get("--cream","#FFFFFF").upper()

def ancestor_bg(sel):
    parts=sel.strip().split()
    for i in range(len(parts)-1,-1,-1):
        pre=" ".join(parts[:i])
        if pre and pre in bgof: return bgof[pre],pre
        last=parts[i]
        base=re.split(r"[:\[]",last)[0]
        for cand in (last,base):
            if cand and cand in bgof and cand!=sel: return bgof[cand],cand
    return [PAGE],"page"

fails=[]
for r in rules:
    if not r["fg"]: continue
    for one in r["sel"].split(","):
        one=one.strip()
        if not one: continue
        bgs_=r["bg"]; src_bg=one
        if not bgs_: bgs_,src_bg=ancestor_bg(one)
        if not bgs_: continue
        px=r["px"] or 13.0
        need=3.0 if (px>=24 or (px>=18.66 and r["bold"])) else 4.5
        for bg in bgs_:                        # every stop of a gradient
            cr=ratio(r["fg"],bg)
            if cr<need:
                fails.append((round(cr,2),need,one,r["fg"],bg,src_bg,px))

fails.sort()
print("resolved %d rules, %d root tokens"%(len(rules),len(VAR)))
print("=== rules whose own colour pair fails: %d ==="%len(fails))
for cr,need,sel,fg,bg,src,px in fails:
    print("  %.2f (need %.1f)  %-46s  fg %s on bg %s   [%s, %.0fpx]"%(cr,need,sel[:46],fg,bg,src,px))
sys.exit(1 if fails else 0)
