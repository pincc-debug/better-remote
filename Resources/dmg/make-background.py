# Generates background.png / background@2x.png (Pillow, Noto Sans CJK). Combine on macOS:
#   tiffutil -cathidpicheck background.png background@2x.png -out background.tiff

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math
S=2; W,H=660*S,400*S
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
bg=Image.new("RGB",(W,H))
c1=(238,236,250); c2=(231,245,240); c3=(244,246,250)
px=bg.load()
for y in range(H):
  for x in range(W):
    t=(x/W*0.7+y/H*0.3)
    px[x,y]=lerp(c1,c2,t) if t<0.6 else lerp(c2,c3,(t-0.6)/0.4)
img=bg.convert("RGBA")
# soft blobs
bl=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(bl)
for (cx,cy,r,col) in [(90,60,170,(196,186,240,120)),(600,350,200,(170,226,205,120)),(560,40,120,(200,215,250,90)),(110,380,130,(185,225,215,70))]:
  d.ellipse([(cx-r)*S,(cy-r)*S,(cx+r)*S,(cy+r)*S],fill=col)
img=Image.alpha_composite(img,bl.filter(ImageFilter.GaussianBlur(60*S)))
# glass shapes
g=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(g)
def glass(box,r):
  b=[v*S for v in box]
  d.rounded_rectangle(b,r*S,fill=(255,255,255,70),outline=(255,255,255,150),width=S)
glass((24,250,124,330),18); glass((560,28,640,118),20)
img=Image.alpha_composite(img,g)
# faint monitor+phone motif top centre
m=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(m); col=(70,90,95,40)
d.rounded_rectangle([290*S,46*S,358*S,90*S],6*S,outline=col,width=2*S)
d.line([324*S,90*S,324*S,99*S],fill=col,width=2*S); d.line([312*S,100*S,336*S,100*S],fill=col,width=2*S)
d.rounded_rectangle([352*S,66*S,374*S,104*S],5*S,outline=col,width=2*S)
for i,rr in enumerate([10,17,24]):
  d.arc([(386-rr)*S,(66-rr)*S,(386+rr)*S,(66+rr)*S],200,250,fill=(70,90,95,40-i*8),width=2*S)
img=Image.alpha_composite(img,m)
# arrow
a=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(a)
p0,p1,p2=(250,185),(330,140),(410,185)
pts=[]
for i in range(61):
  t=i/60; x=(1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0]; y=(1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1]; pts.append((x*S,y*S))
acol=(88,110,200,230)
for i in range(0,60,2): d.line([pts[i],pts[i+1]],fill=acol,width=int(4*S))
for q in pts[:-1:2]: pass
ex,ey=pts[-1]; px_,py_=pts[-6]; ang=math.atan2(ey-py_,ex-px_); L=16*S
for s in (1,-1):
  d.line([(ex,ey),(ex-L*math.cos(ang+s*0.5),ey-L*math.sin(ang+s*0.5))],fill=acol,width=int(4*S))
d.ellipse([ex-3*S,ey-3*S,ex+3*S,ey+3*S],fill=acol)
img=Image.alpha_composite(img,a)
# text
d=ImageDraw.Draw(img)
f=ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",15*S,index=2)
t="拖到应用程序文件夹即可安装"; w=d.textlength(t,font=f)
pill=[(W-w)/2-18*S,342*S,(W+w)/2+18*S,374*S]
d.rounded_rectangle(pill,16*S,fill=(255,255,255,140),outline=(255,255,255,200),width=S)
d.text((W/2,358*S),t,font=f,fill=(60,72,90,255),anchor="mm")
img=img.convert("RGB")
img.save("background@2x.png"); img.resize((660,400),Image.LANCZOS).save("background.png")
# mockup
mk=img.resize((660,400),Image.LANCZOS).convert("RGBA")
fs=ImageFont.truetype("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",12,index=2); dm=ImageDraw.Draw(mk)
for fn,cx,lab in [("app_icon.png",170,"Better Remote.app"),("apps_icon.png",490,"Applications")]:
  ic=Image.open(fn).convert("RGBA").resize((128,128),Image.LANCZOS); mk.alpha_composite(ic,(cx-64,200-64))
  dm.text((cx,276),lab,font=fs,fill=(30,30,30),anchor="mm")
mk.convert("RGB").save("preview-mockup.png")
