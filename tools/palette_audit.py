import io,re,sys
PALETTE = {
 # the seven-step ramp
 '#FFFFFF','#DDDDDD','#BBBBBB','#999999','#767676','#545454','#323232',
 # the red family and the yellow family, all measured
 '#CB2129','#DD362D','#A8171E','#B01C23','#8E1218',
 '#FAE23B','#FDF3AE','#EFCF12','#C9A800','#D9BC18','#F7E27A','#5C4D00',
 # measured tints of those two, used as callout grounds
 '#F4F4F4','#EFEFEF','#FDF7D2','#FBE7E8','#F3C9CB','#DD8E92','#FCEFEF','#F7DBDC','#EDF3DF',
 # the success green, a darkened June Bud
 '#4A6B1E','#3D3D3D','#CFCFCF',
 # the brief's remaining accents, legal but currently unused in the game
 '#F7944B','#BAD644','#935CA6','#6375B8','#33C5EE',
 '#FFF','#000',
}
def norm(h):
    h=h.upper()
    if len(h)==4: h='#'+''.join(c*2 for c in h[1:])
    return h[:7]
path=sys.argv[1]
s=io.open(path,encoding='utf-8').read()
css=''.join(re.findall(r'<style[^>]*>(.*?)</style>',s,re.S))
css=re.sub(r'/\*.*?\*/','',css,flags=re.S)          # comments are prose, not paint
bad={}
for line_no,line in enumerate(css.split('\n'),1):
    for h in re.findall(r'#[0-9A-Fa-f]{3,6}\b', line):
        n=norm(h)
        if n not in PALETTE:
            bad.setdefault(n,[]).append(line.strip()[:110])
print(f"--- {path} ---")
if not bad:
    print("  every CSS colour literal is in the palette")
else:
    for h,ctx in sorted(bad.items()):
        print(f"  OFF-PALETTE {h}  x{len(ctx)}")
        for c in ctx[:2]: print(f"       {c}")
