# 백룸

Godot 4.6 모바일 웹 3D 공포 방탈출. 노란 방에 떨어진 주인공이 지수의 쪽지를 따라 19개 층을 지나 탈출한다. 최대 4명 같이 하기.

- 플레이: https://wylee-hadeul.github.io/jio/
- 배포: `./deploy.sh` (웹 익스포트 → `gh-pages`)

## 구조
- `scripts/levels.gd` — 레벨 목록(테마/퍼즐/괴물 수)과 시드 기반 맵 생성기. 레벨 0만 손으로 만든 맵
- `scripts/level.gd` — 레이아웃으로 벽/바닥/천장/물체를 짓고 길찾기 제공
- `shaders/backrooms.gdshader` — 조명 노드 없이 형광등/어둠/손전등(최대 4개)/안개/테마 무늬를 계산
- `scripts/main.gd` — 조사, 퍼즐, 숫자 발견, 잡힘, 다음 층, 엔딩
- `scripts/coop.gd`, `scripts/net.gd` — 같이 하기(PeerJS 중계 + WebRTC). 방장이 '그것'을 움직이고, 누구든 보고 있으면 멈춤

퍼즐: 숨은 숫자(위/뒤/목소리/어둠/아래/처음, 거울 뒤집기), 열쇠, 밸브+승강기, 차단기+천장 출구, 개수 세기, 번호 문 수수께끼, 추격, 풍선, 어긋난 벽(눈 감고 통과)

## 오토플레이 테스트
봇이 실제 터치 입력으로 레이아웃의 정답 순서(`solution`)를 따라 모든 층을 공략하고, 스크린샷/로그를 남긴다.

```bash
./tools/autoplay_desktop.sh [--from=N]   # 데스크톱 창 → build/test/desktop/
./tools/autoplay_web.sh [URL]            # 웹 빌드 + 모바일 에뮬레이션 → build/test/web/
./tools/autoplay_coop.sh [URL]           # 창 두 개로 같이 하기 → build/test/coop/
```

## 폰트
Gowun Batang (SIL OFL, KS X 1001 한글로 서브셋, `fonts/OFL.txt`)
