#!/bin/bash
set -uo pipefail
D=/tmp/bentoo-fix-distfiles-4006171477
mkdir -p "$D"
C=d61e80b85debf0c56ecdcadf635ffa2660ddfd37
U="https://github.com/zed-industries/zed/archive/${C}.tar.gz"
echo "STEP fetch $U"
curl -sSL --retry 3 --retry-all-errors -o "$D/zed-1.16.0_pre20260806.tar.gz" "$U"
echo "STEP curl-exit=$?"
echo "STEP size=$(stat -c %s "$D/zed-1.16.0_pre20260806.tar.gz" 2>/dev/null)"
echo "STEP file=$(file -b "$D/zed-1.16.0_pre20260806.tar.gz" 2>/dev/null)"
echo "STEP top=$(tar tzf "$D/zed-1.16.0_pre20260806.tar.gz" 2>&1 | head -1)"
echo "STEP df=$(df -h /tmp | tail -1)"
echo "STEP done"
