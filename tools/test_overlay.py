"""Run the overlay inside a real, headless ScoreSight on a synthetic hockey
scoreboard video (scores, clock, period, penalties with jersey numbers, a
misread) and record what the overlay shows. See the README.

    SCORESIGHT_SRC=/path/to/scoresight python tools/test_overlay.py WORKDIR
"""
import os, sys, json, subprocess, time, signal, urllib.request, shutil
from pathlib import Path
import numpy as np, cv2
SRC = Path(os.environ.get("SCORESIGHT_SRC", "")).resolve()  # a ScoreSight 0.3.0+ source checkout
HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC / "scripts" / "ci"))
import e2e_test as e, app_harness
from PIL import Image, ImageDraw
d = Path(sys.argv[1]).resolve()/"run"; shutil.rmtree(d, ignore_errors=True)
for x in ("data/overlays","logs","out","shots"): (d/x).mkdir(parents=True, exist_ok=True)
si = e._load_synthetic_images()
W,H,FPS = 1280,720,30
BOX = {  # name: (x,y,w,h, digit height, settings)
 "Time": (440,30,400,140,90,{}), "Home Score": (120,220,200,140,90,{}), "Away Score": (960,220,200,140,90,{}),
 "Period": (590,230,100,120,70,{"format_regex":"^\\d{1}$"}),
}
T = {"type":1,"format_regex":"^(?:(?:[0-5]?\\d:[0-5]\\d)|(?:[0-5]?\\d\\.\\d))$"}
for side,x0 in (("Home",60),("Away",860)):
    for n,y in ((1,420),(2,540)):
        BOX[f"{side} Pen {n} Player"]=(x0,y,120,90,50,{})
        BOX[f"{side} Pen {n}"]=(x0+140,y,240,90,50,dict(T))
def clk(s): return f"{s//60}:{s%60:02d}"
# one dict per second of video
secs=[]; c=130
def add(n, **kw):
    global c
    for i in range(n):
        st={"Time":clk(c),"Home Score":"1","Away Score":"0","Period":"1"}
        for k,v in kw.items(): st[k]=v(i) if callable(v) else v
        secs.append(st); c-=1
add(5)
add(6, **{"Away Pen 1":lambda i: clk(120-i),"Away Pen 1 Player":"17"})
add(6, **{"Away Pen 1":lambda i: clk(114-i),"Away Pen 1 Player":"17","Home Pen 1":lambda i: clk(120-i),"Home Pen 1 Player":"8"})
add(6, **{"Home Pen 1":lambda i: clk(13-i),"Home Pen 1 Player":"8"})
add(3)
add(4, **{"Home Score":"2"})
c=1200; add(4, **{"Home Score":"2","Period":"2"})
add(4, **{"Home Score":"2","Period":"4","Time":lambda i: f"{45-i}.3"})
add(4, **{"Home Score":"2","Period":"5","Time":"0:00"})
GLITCH_SEC, GLITCH_FRAMES = 28, 8   # home score flashes 7 during the quiet scene
def frame(st):
    f=np.full((H,W),16,np.uint8)
    for name,(x,y,w,h,dh,_) in BOX.items():
        t=st.get(name,"")
        if not t: continue
        im=si.seven_segment(t,height=dh,fg=235,bg=16,pad=0)
        l=x+(w-im.shape[1])//2; tp=y+(h-im.shape[0])//2
        f[tp:tp+im.shape[0], l:l+im.shape[1]]=im
    return cv2.cvtColor(f,cv2.COLOR_GRAY2BGR)
video=d/"hockey.avi"; wr=cv2.VideoWriter(str(video),cv2.VideoWriter_fourcc(*"MJPG"),FPS,(W,H))
for i,st in enumerate(secs):
    fr=frame(st); gl=frame({**st,"Home Score":"7"})
    for k in range(FPS): wr.write(gl if (i==GLITCH_SEC and k<GLITCH_FRAMES) else fr)
wr.release()
cv2.imwrite(str(d/"shots"/"board-both-penalties.png"), frame(secs[13]))
print("video seconds:", len(secs))
st=e.app_settings(video, d/"out", "http://127.0.0.1:9/x"); st["enable_out_api"]=False; st["save_csv"]=False; st["save_xml"]=False
st["boxes"]=[{"name":n,"rect":{"x":x,"y":y,"width":w,"height":h},"settings":{**e.BOX_SETTINGS,**s},"mini_rects":[]} for n,(x,y,w,h,dh,s) in BOX.items()]
e.settings_path(d/"data").write_text(json.dumps(st))
shutil.copy(HERE/"usc-scorebug.html", d/"data"/"overlays"/"usc-scorebug.html")
env=app_harness.app_env(d/"data", d/"logs")
p=subprocess.Popen([sys.executable,str(SRC/"src"/"main.py"),"--profile",e.PROFILE,"--port","18124"],env=env,cwd=str(SRC),stdout=open(d/"app.txt","w"),stderr=subprocess.STDOUT)
JS="""()=>{const g=id=>document.getElementById(id);const pen=id=>{const n=g(id);return n.classList.contains('on')?(n.querySelector('.num').textContent+' '+n.querySelector('.time').textContent+(n.classList.contains('warn')?' WARN':'')).trim():''};
const S=window.ScoreSight||{fields:{}};const raw={};for(const k in S.fields){raw[k]=S.fields[k].good?S.fields[k].value:'~'+S.fields[k].state}
return {dom:{w:Math.round(document.querySelector('.bug').getBoundingClientRect().width),h:g('homeScore').textContent,a:g('awayScore').textContent,clock:g('clock').textContent,period:g('period').textContent,
 ppH:g('teamHome').classList.contains('onpp'),ppA:g('teamAway').classList.contains('onpp'),hp1:pen('hp1'),hp2:pen('hp2'),ap1:pen('ap1'),ap2:pen('ap2'),stale:document.body.classList.contains('stale')},raw,conn:!!S.connected,tr:S.transport}}"""
log=[]
try:
    for _ in range(100):
        time.sleep(0.3)
        try: urllib.request.urlopen("http://127.0.0.1:18124/overlay/state",timeout=1).read(); break
        except Exception: pass
    from playwright.sync_api import sync_playwright
    with sync_playwright() as pw:
        b=pw.chromium.launch(executable_path=os.environ.get("CHROMIUM") or None)
        pg=b.new_page(viewport={"width":1920,"height":1080}); errs=[]
        pg.on("console", lambda m: errs.append(m.text) if m.type=="error" else None); pg.on("pageerror", lambda x: errs.append(str(x)))
        pg.goto("http://127.0.0.1:18124/overlay/custom/usc-scorebug.html?home=USC&away=CAL&homeColor=990000&awayColor=003262")
        want={"usc-power-play":lambda D:D["ppH"] and D["ap1"] and not D["hp1"],
              "even-strength-two-penalties":lambda D:D["ap1"] and D["hp1"] and not D["ppH"] and not D["ppA"],
              "cal-power-play-last-10s":lambda D:D["ppA"] and "WARN" in D["hp1"],
              "second-period":lambda D:D["period"]=="2nd" and D["clock"].startswith("19:"),
              "overtime-tenths":lambda D:D["period"]=="OT" and "." in D["clock"],
              "shootout":lambda D:D["period"]=="SO"}
        got={}; t0=time.time(); so_seen=0; prev_so=False
        while time.time()-t0<170:
            r=pg.evaluate(JS); r["t"]=round(time.time()-t0,2); log.append(r); D=r["dom"]
            for k,fn in want.items():
                if k not in got and fn(D):
                    pg.wait_for_timeout(150); pg.screenshot(path=str(d/"shots"/f"{k}.png"),omit_background=True); got[k]=r["t"]
            so=D["period"]=="SO"
            if so and not prev_so: so_seen+=1
            prev_so=so
            if so_seen>=2 and len(got)==len(want): break
            pg.wait_for_timeout(100)
        print("errors:",errs[:3]); print("transport:",log[-1]["tr"],"connected:",log[-1]["conn"]); print("screens:",got)
        b.close()
finally:
    p.send_signal(signal.SIGTERM)
    try: print("app exit", p.wait(20))
    except Exception: p.kill()
json.dump(log, open(d/"log.json","w"))
bg=Image.new("RGB",(1920,1080)); dr=ImageDraw.Draw(bg)
for y in range(1080): dr.line([(0,y),(1920,y)],fill=(40+y//12,70+y//10,95+y//9))
for f in (d/"shots").glob("*.png"):
    if f.name.startswith("board"): continue
    ov=Image.open(f).convert("RGBA"); im=bg.copy(); im.paste(ov,(0,0),ov); im.crop((0,0,1000,230)).save(f)

# --- checks -------------------------------------------------------------------
doms=[r["dom"] for r in log]
checks={
 "the bug keeps one width": len({D["w"] for D in doms})==1,
 "USC power play shown with only a CAL penalty": any(D["ppH"] and D["ap1"] and not D["hp1"] for D in doms),
 "no PP badge at even strength": any(D["ap1"] and D["hp1"] and not D["ppH"] and not D["ppA"] for D in doms),
 "never both PP badges": not any(D["ppH"] and D["ppA"] for D in doms),
 "PP only for the team with fewer penalties": all((not D["ppH"]) or (D["ap1"] and not D["hp1"]) for D in doms),
 "penalty time turns gold in the last 10 s": any("WARN" in D["hp1"] for D in doms),
 "jersey numbers shown": any(D["ap1"].startswith("#17") for D in doms),
 "periods 1st, 2nd, OT, SO": {"1st","2nd","OT","SO"} <= {D["period"] for D in doms},
 "tenths under a minute": any("." in D["clock"] for D in doms),
 "the misread 7 reached the overlay client": any(r["raw"].get("Home Score")=="7" for r in log),
 "the misread 7 was never shown": not any(D["h"]=="7" for D in doms),
 "the goal was shown": any(D["h"]=="2" for D in doms),
 "all six scenes captured": len(got)==len(want),
 "no page errors": not errs,
}
for name, ok in checks.items(): print(("[ok  ] " if ok else "[FAIL] ")+name)
print("PASSED" if all(checks.values()) else "FAILED"); sys.exit(0 if all(checks.values()) else 1)
