# Ikona projektu w Paseo (szuka assets/favicon.png: kwadrat, <=32 KB).
# UV_CACHE_DIR=$TMPDIR/uvc uv run --with numpy --with pillow python assets/make-favicon.py assets/favicon.png
import sys, numpy as np
from PIL import Image
S=1024; out=sys.argv[1]
y,x=np.mgrid[0:S,0:S].astype(np.float64)+0.5
u=x/S-0.5; v=y/S-0.5
# rounded-square mask (radius 22%)
half=0.5; r=0.22
qx=np.abs(u)-(half-r); qy=np.abs(v)-(half-r)
d=np.hypot(np.maximum(qx,0),np.maximum(qy,0))+np.minimum(np.maximum(qx,qy),0)-r
alpha=np.clip(0.5-d*S,0,1)
# background: deep indigo radial gradient
rr=np.hypot(u+0.08,v+0.12)
c1=np.array([42,36,86])/255; c0=np.array([10,10,22])/255
t=np.clip(rr/0.75,0,1)[...,None]
col=c1*(1-t)+c0*t
# corona glow around center
R=0.235; cx,cy=0.0,0.0
dist=np.hypot(u-cx,v-cy)
glow=np.exp(-np.clip(dist-R,0,None)/0.055)*(dist>=R*0.9)
gold=np.array([255,190,110])/255; violet=np.array([170,140,255])/255
gm=np.clip((dist-R)/0.18,0,1)[...,None]
gcol=gold*(1-gm)+violet*gm
col=col+(gcol*glow[...,None]*0.95)
# moon disc, slightly offset -> bright crescent rim at upper-right
mx,my=-0.018,0.018; mr=R*0.985
md=np.hypot(u-mx,v-my)
moon=np.clip((mr-md)*S/1.5,0,1)[...,None]
mooncol=np.array([8,8,16])/255+ (np.array([30,28,60])/255)*np.clip(1-md/mr,0,1)[...,None]*0.5
# thin bright rim (diamond ring) where sun disc peeks out
sun=np.clip((R-dist)*S/1.5,0,1)[...,None]
rim=sun*(1-moon)
col=col*(1-sun)+ (np.array([255,236,200])/255)*sun  # sun disc
col=col*(1-moon)+mooncol*moon
# diamond-ring sparkle at upper-right
ang=np.array([0.70,-0.71]); px,py=cx+ang[0]*R,cy+ang[1]*R
sd=np.hypot(u-px,v-py)
spark=np.exp(-sd/0.018)*0.9 + np.exp(-(np.abs(u-px)*np.abs(v-py))/0.00012)*np.exp(-sd/0.07)*0.55
col=col+np.array([255,240,215])/255*spark[...,None]
col=np.clip(col,0,1)
img=np.dstack([col*255,alpha*255]).astype(np.uint8)
Image.fromarray(img,'RGBA').resize((192,192),Image.LANCZOS).save(out,optimize=True)
