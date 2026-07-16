from PIL import Image, ImageDraw, ImageFont
import os

BASE="/Users/nadiaeldeib/622-project/site"
W,H=1200,630
INK=(32,32,42); CORAL=(255,90,60); MUTED=(122,116,128); WHITE=(255,255,255)

def F(p,s): return ImageFont.truetype(p,s)
f_black=F("/System/Library/Fonts/Supplemental/Arial Black.ttf",78)
f_bold =F("/System/Library/Fonts/Supplemental/Arial Bold.ttf",40)
f_body =F("/System/Library/Fonts/Supplemental/Arial.ttf",26)
f_chip =F("/System/Library/Fonts/Supplemental/Arial Bold.ttf",22)
f_mono =F("/System/Library/Fonts/Menlo.ttc",15)

# --- background: smooth 4-corner gradient (upscale a 2x2) ---
g=Image.new("RGB",(2,2))
g.putpixel((0,0),(255,236,228)); g.putpixel((1,0),(255,221,204))  # TL, TR(coral glow)
g.putpixel((0,1),(251,246,239)); g.putpixel((1,1),(243,236,251))  # BL, BR
card=g.resize((W,H),Image.BICUBIC).convert("RGBA")
d=ImageDraw.Draw(card)

def rounded(img,rad):
    m=Image.new("L",img.size,0)
    ImageDraw.Draw(m).rounded_rectangle([0,0,img.size[0],img.size[1]],rad,fill=255)
    img=img.copy(); img.putalpha(m); return img

def phone(path,w,rot=0):
    im=Image.open(os.path.join(BASE,path)).convert("RGBA")
    h=int(im.height*w/im.width)
    im=im.resize((w,h),Image.LANCZOS)
    im=rounded(im,int(w*0.10))
    b=8
    fr=Image.new("RGBA",(w+2*b,h+2*b),(0,0,0,0))
    ImageDraw.Draw(fr).rounded_rectangle([0,0,w+2*b,h+2*b],int(w*0.10)+b,fill=(28,29,34,255))
    fr.alpha_composite(im,(b,b))
    if rot: fr=fr.rotate(rot,expand=True,resample=Image.BICUBIC)
    return fr

# --- right: fanned phones (paste back ones first) ---
bl=phone("app-shots/shot-bolt.png",206,-9)
gd=phone("app-shots/shot-garden.png",206,9)
ot=phone("app-shots/shot-otter.png",250,0)
card.alpha_composite(bl,(648,112))
card.alpha_composite(gd,(978,112))
card.alpha_composite(ot,(786,72))

# --- left: brand ---
icon=Image.open(os.path.join(BASE,"otterpace-icon.png")).convert("RGBA").resize((70,70),Image.LANCZOS)
icon=rounded(icon,20)
card.alpha_composite(icon,(72,60))
d.text((158,95),"Otterpace",font=f_bold,fill=INK,anchor="lm")

# --- headline ---
d.text((70,205),"RUN HAPPY.",font=f_black,fill=INK)
d.text((70,205+80),"COACH KIND.",font=f_black,fill=CORAL)

# --- tagline (wrapped) ---
tag="A friendly running companion — daily encouragement, in five whole-app themes."
words=tag.split(); lines=[]; cur=""
maxw=470
for wd in words:
    t=(cur+" "+wd).strip()
    if d.textlength(t,font=f_body)<=maxw: cur=t
    else: lines.append(cur); cur=wd
lines.append(cur)
ty=390
for ln in lines:
    d.text((72,ty),ln,font=f_body,fill=(74,70,83)); ty+=34

# --- App Store badge (drawn) + Android chip ---
def appstore_badge(h=56):
    apple=F("/System/Library/Fonts/SFNS.ttf",int(h*0.50))
    small=F("/System/Library/Fonts/SFNS.ttf",int(h*0.20))
    big  =F("/System/Library/Fonts/SFNS.ttf",int(h*0.37))
    tmp=ImageDraw.Draw(Image.new("RGBA",(10,10)))
    tx=int(h*0.30)+int(h*0.55)+8
    tw=max(tmp.textlength("Download on the",font=small), tmp.textlength("App Store",font=big))
    w=int(tx+tw+int(h*0.30))
    b=Image.new("RGBA",(w,h),(0,0,0,0)); bd=ImageDraw.Draw(b)
    bd.rounded_rectangle([0,0,w-1,h-1],int(h*0.17),fill=(0,0,0,255),outline=(90,90,90,255),width=1)
    bd.text((int(h*0.30),int(h*0.50)),"",font=apple,fill=WHITE,anchor="lm")
    bd.text((tx,int(h*0.32)),"Download on the",font=small,fill=WHITE,anchor="lm")
    bd.text((tx,int(h*0.68)),"App Store",font=big,fill=WHITE,anchor="lm")
    return b
badge=appstore_badge(56); bw=badge.width
by=505
card.alpha_composite(badge,(72,by))
# chip
cx=72+bw+16; ctext="Android soon"; cpadx=17
ctw=d.textlength(ctext,font=f_chip); cw=int(cpadx*2+16+8+ctw); ch=56
d.rounded_rectangle([cx,by,cx+cw,by+ch],13,fill=(32,32,42))
d.ellipse([cx+cpadx,by+ch//2-5,cx+cpadx+10,by+ch//2+5],fill=(243,180,48))
d.text((cx+cpadx+10+10,by+ch//2),ctext,font=f_chip,fill=WHITE,anchor="lm")

# --- foot ---
d.text((72,588),"otterpace.com  ·  open source  ·  built with CodeYam",font=f_mono,fill=MUTED)

card.convert("RGB").save(os.path.join(BASE,"og-card.png"),"PNG")
print("wrote og-card.png", os.path.getsize(os.path.join(BASE,"og-card.png")), "bytes")
