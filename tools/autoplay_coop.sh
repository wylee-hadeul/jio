#!/bin/zsh
# 같이 하기 테스트: 브라우저 창 두 개에서 방장/참가자 봇을 동시에 돌린다. 결과는 build/test/coop
# 사용: tools/autoplay_coop.sh [URL]  (URL 생략 시 로컬 빌드)
set -u
cd "$(dirname "$0")/.."
PORT=8804
OUT="$PWD/build/test/coop"
rm -rf "$OUT" && mkdir -p "$OUT"
URL="${1:-}"
if [[ -z "$URL" ]]; then
	rm -rf build/web && mkdir -p build/web
	godot --headless --export-release "Web" build/web/index.html > "$OUT/export.log" 2>&1 || { echo "익스포트 실패"; exit 1; }
	python3 -m http.server $PORT -d build/web > /dev/null 2>&1 &
	SERVER=$!
	trap "kill $SERVER 2>/dev/null" EXIT
	sleep 1
	URL="http://127.0.0.1:$PORT/index.html"
fi
~/.local/bin/bu-chrome > /dev/null 2>&1
AP_OUT="$OUT" AP_URL="$URL" AP_ROOM="$(( RANDOM % 9000 + 1000 ))" BU_CDP_URL=http://127.0.0.1:9222 browser-use < tools/autoplay_coop.py
! grep -q "FAIL" "$OUT"/*.log && grep -q "DONE" "$OUT/host.log" && grep -q "DONE" "$OUT/client.log"
