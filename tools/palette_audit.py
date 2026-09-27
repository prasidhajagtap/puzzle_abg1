import io,re,sys
PALETTE = {
 # grounds, from the reference's near-black
 '#0C0C14','#16161F','#1E1E2B','#26263A','#2E2E42','#0A0A10',
 # the reference's accents, sampled from the jpg
 '#6018F0','#4A0FC4','#8046F3','#9060FF','#C0F000','#A8D400','#3CA8F0','#FCC000','#FFD95C',
 '#F04830','#F4705C','#F03060','#3A1220','#C99A00',
 # neutrals
 '#9A9AB0','#B8B8CC','#F0F0F0','#FFFFFF',
 '#FFF','#000',
}
def norm(h):
    h=h.upper()
    if len(h)==4: h='#'+''.join(c*2 for c in h[1:])
    return h[:7]
path=sys.argv[1]
s=io.open(path,encoding='utf-8').read()
# BOTH the stylesheet AND the script: HUES, the confetti palette and the
# theme-color meta are colour decisions too, and a CSS-only audit cannot see
# them. That gap is exactly how a stale hue survived a repaint before.
css=''.join(re.findall(r'<style[^>]*>(.*?)</style>',s,re.S))
js=''.join(re.findall(r'<script(?![^>]*src=)[^>]*>(.*?)</script>',s,re.S))
js=re.sub(r'//[^\n]*','',js)
markup=re.sub(r'<style[^>]*>.*?</style>','',s,flags=re.S)
markup=re.sub(r'<script(?![^>]*src=).*?</script>','',markup,flags=re.S)
markup=re.sub(r'<!--.*?-->','',markup,flags=re.S)
css=css+'\n'+js+'\n'+markup
css=re.sub(r'/\*.*?\*/','',css,flags=re.S)          # comments are prose, not paint
bad={}
for line_no,line in enumerate(css.split('\n'),1):
    # &#128161; is an emoji, not a colour. Strip HTML numeric entities
    # before looking for hex, or every icon reads as an off-palette value.
    line = re.sub(r'&#[0-9]+;?', '', line)
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
