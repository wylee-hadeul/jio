# browser-use 표준입력 스크립트. 오토플레이 핸드셰이크(window.__ap)에 맞춰 스크린샷을 찍고 로그를 모은다.
import json
import os
import time

out = os.environ["AP_OUT"]
url = os.environ["AP_URL"]
TIMEOUT_SEC = 600

# 탭이 백그라운드면 requestAnimationFrame이 멈춰 게임이 진행되지 않으므로 별도 창으로 연다.
target = cdp("Target.createTarget", url="about:blank", newWindow=True)["targetId"]
switch_tab(target)
cdp("Emulation.setDeviceMetricsOverride", width=390, height=844, deviceScaleFactor=2, mobile=True)
cdp("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
goto_url(url)

done = False
deadline = time.time() + TIMEOUT_SEC
while time.time() < deadline:
    raw = js("window.__ap ? JSON.stringify({p: window.__ap.pending, d: window.__ap.done}) : null")
    if raw:
        st = json.loads(raw)
        if st["p"]:
            capture_screenshot(path=f"{out}/{st['p']}.png")
            js("window.__ap.pending = null")
            continue
        if st["d"]:
            done = True
            break
    time.sleep(0.3)

logs = js("window.__ap ? window.__ap.logs.join('\\n') : ''") or ""
with open(f"{out}/autoplay.log", "w") as f:
    f.write(logs + "\n")
for line in logs.splitlines():
    if any(k in line for k in ("FAIL", "DONE", "WARN")):
        print(line)
close_tab(target)
print(("완료" if done else "타임아웃"), "| 결과:", out)
