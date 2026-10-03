#!/bin/zsh
# 웹 익스포트 후 gh-pages 브랜치로 강제 푸시한다.
set -e
cd "$(dirname "$0")"
rm -rf build/web && mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
touch build/web/.nojekyll
REMOTE=$(git remote get-url origin)
cd build/web
rm -rf .git && git init -q && git checkout -q -b gh-pages
git add -A && git commit -qm "deploy: $(date '+%Y-%m-%d %H:%M:%S')"
git push -qf "$REMOTE" gh-pages
rm -rf .git
echo "배포 완료 (반영까지 1~2분)"
