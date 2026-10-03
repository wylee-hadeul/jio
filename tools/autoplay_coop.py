# browser-use 표준입력 스크립트. 창 두 개(방장/참가자)로 같이 하기 오토플레이를 돌린다.
import json
import os
import time

out = os.environ["AP_OUT"]
base = os.environ["AP_URL"]
room = os.environ["AP_ROOM"]
TIMEOUT_SEC = 420


def open_window(url):
    t = cdp("Target.createTarget", url="about:blank", newWindow=True)["targetId"]
    switch_tab(t)
    cdp("Emulation.setDeviceMetricsOverride", width=390, height=844, deviceScaleFactor=2, mobile=True)
    cdp("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
    goto_url(url)
    return t


def poll(name, target, state):
    switch_tab(target)
    raw = js("window.__ap ? JSON.stringify({p: window.__ap.pending, d: window.__ap.done, n: window.__ap.logs.length}) : null")
    if not raw:
        return
    st = json.loads(raw)
    if st["p"]:
        capture_screenshot(path=f"{out}/{name}_{st['p']}.png")
        js("window.__ap.pending = null")
    state["done"] = st["d"]
    state["logs"] = js("window.__ap.logs.join('\\n')") or ""


stamp = int(time.time())
host = open_window(f"{base}?autoplay=coophost&aproom={room}&t={stamp}")
hs = {"done": False, "logs": ""}
client = None
cs = {"done": False, "logs": ""}
deadline = time.time() + TIMEOUT_SEC
while time.time() < deadline:
    poll("host", host, hs)
    if client is None and "HOSTING" in hs["logs"]:
        client = open_window(f"{base}?autoplay=coopjoin&room={room}&t={stamp}")
    if client is not None:
        poll("client", client, cs)
    if hs["done"] and cs["done"]:
        break
    time.sleep(0.3)

for name, st in (("host", hs), ("client", cs)):
    with open(f"{out}/{name}.log", "w") as f:
        f.write(st["logs"] + "\n")
    for line in st["logs"].splitlines():
        if any(k in line for k in ("FAIL", "DONE", "PASS")):
            print(f"[{name}] {line}")
for t in (host, client):
    if t:
        close_tab(t)
print("완료" if hs["done"] and cs["done"] else "타임아웃", "| 결과:", out)
