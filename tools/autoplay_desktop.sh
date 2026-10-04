#!/bin/zsh
# 데스크톱 창(405x720)에서 오토플레이 테스트를 돌리고 스크린샷/로그를 build/test/desktop에 남긴다.
set -u
cd "$(dirname "$0")/.."
OUT="$PWD/build/test/desktop"
TIMEOUT_SEC=${AP_TIMEOUT:-2400}
rm -rf "$OUT" && mkdir -p "$OUT"
if godot --headless --path . --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error"; then
	echo "스크립트 에러로 중단"; exit 1
fi
godot --path . --resolution 405x720 -- --autoplay --shots="$OUT" "$@" > "$OUT/godot.log" 2>&1 &
PID=$!
( sleep $TIMEOUT_SEC; kill $PID 2>/dev/null && echo "타임아웃(${TIMEOUT_SEC}s)으로 강제 종료" ) &
WATCHDOG=$!
wait $PID
CODE=$?
kill $WATCHDOG 2>/dev/null
grep "\[AUTOPLAY\]" "$OUT/godot.log" | grep -E "FAIL|DONE|WARN"
ERRS=$(grep -cE "SCRIPT ERROR|^ERROR" "$OUT/godot.log")
echo "엔진 에러 ${ERRS}건 | 종료 코드 ${CODE} | 결과: $OUT"
[[ $CODE -eq 0 && $ERRS -eq 0 ]]
