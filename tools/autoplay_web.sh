#!/bin/zsh
# 웹 빌드를 모바일 뷰포트(390x844, 터치 에뮬레이션)로 열어 오토플레이 테스트. 결과는 build/test/web
# 사용: tools/autoplay_web.sh [URL]  (URL 생략 시 로컬 빌드)
set -u
cd "$(dirname "$0")/.."
PORT=8803
OUT="$PWD/build/test/web"
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
AP_OUT="$OUT" AP_URL="$URL?autoplay&t=$(date +%s)" BU_CDP_URL=http://127.0.0.1:9222 browser-use < tools/autoplay_web.py
! grep -q "FAIL" "$OUT/autoplay.log" && grep -q "DONE" "$OUT/autoplay.log"
