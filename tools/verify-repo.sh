#!/usr/bin/env bash
# 本地发布前检查：文件校验、脚本语法、XML、Markdown 相对链接、CRLF、敏感串。
# 用法：bash tools/verify-repo.sh
set -uo pipefail
cd -- "$(dirname -- "$0")/.." || exit 1

fail=0
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fail=1; }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; }

echo "== 1. SHA256SUMS =="
if [ ! -f SHA256SUMS ]; then
  bad "缺少 SHA256SUMS"
else
  if sha256sum -c SHA256SUMS >/tmp/y900-verify-sha.$$ 2>&1; then
    ok "$(wc -l < SHA256SUMS) 个文件校验通过"
  else
    bad "SHA256 校验失败："
    sed 's/^/       /' /tmp/y900-verify-sha.$$
  fi
  rm -f /tmp/y900-verify-sha.$$
fi

echo "== 2. Shell 语法 =="
sh_count=0
while IFS= read -r f; do
  head -n1 "$f" | grep -qE '^#!.*\b(bash|sh)\b' || continue
  sh_count=$((sh_count + 1))
  if bash -n "$f" 2>/tmp/y900-verify-sh.$$; then
    ok "$f"
  else
    bad "$f"; sed 's/^/       /' /tmp/y900-verify-sh.$$
  fi
done < <(find . -path ./.git -prune -o -type f -print | sort)
[ "$sh_count" -eq 0 ] && skip "未发现 shell 脚本"
rm -f /tmp/y900-verify-sh.$$

echo "== 3. Python 语法 =="
py_count=0
while IFS= read -r f; do
  head -n1 "$f" | grep -qE '^#!.*python' || continue
  py_count=$((py_count + 1))
  if python3 -c 'import sys; p=sys.argv[1]; compile(open(p,encoding="utf-8").read(), p, "exec")' "$f" 2>/tmp/y900-verify-py.$$; then
    ok "$f"
  else
    bad "$f"; sed 's/^/       /' /tmp/y900-verify-py.$$
  fi
done < <(find . -path ./.git -prune -o -type f -print | sort)
[ "$py_count" -eq 0 ] && skip "未发现 Python 脚本"
rm -f /tmp/y900-verify-py.$$

echo "== 4. XML 解析 =="
if python3 - <<'PY'
import sys, pathlib, xml.etree.ElementTree as ET
bad = 0
files = sorted(pathlib.Path('config').rglob('*.xml'))
for p in files:
    try:
        ET.parse(p)
        print(f"  \033[32mOK\033[0m   {p}")
    except Exception as e:
        print(f"  \033[31mFAIL\033[0m {p}: {e}")
        bad = 1
sys.exit(bad)
PY
then :; else fail=1; fi

echo "== 5. CRLF 检查（脚本与配置） =="
crlf=0
while IFS= read -r f; do
  if grep -qU $'\r' "$f" 2>/dev/null; then
    bad "含 CRLF：$f"; crlf=1
  fi
done < <(find scripts config -type f 2>/dev/null | sort)
[ "$crlf" -eq 0 ] && ok "脚本与配置均为 LF"

echo "== 6. Markdown 相对链接 =="
python3 - <<'PY'
import re, sys, pathlib, urllib.parse, unicodedata

root = pathlib.Path('.').resolve()
md_files = sorted(p for p in root.rglob('*.md') if '.git' not in p.parts)
link_re = re.compile(r'!?\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
slug_re = re.compile(r'[^\w\s\-]', re.UNICODE)
bad = 0
checked = 0

def slugify(text: str) -> str:
    text = unicodedata.normalize('NFC', text).strip().lower()
    text = re.sub(r'[*`_~]', '', text)
    text = slug_re.sub('', text)
    return text.replace(' ', '-')

def anchors(path: pathlib.Path):
    out = set()
    for line in path.read_text(encoding='utf-8').splitlines():
        m = re.match(r'^(#{1,6})\s+(.*?)\s*#*\s*$', line)
        if m:
            out.add(slugify(m.group(2)))
    return out

def norm(p):
    return unicodedata.normalize('NFC', str(p))

for md in md_files:
    text = md.read_text(encoding='utf-8')
    for m in link_re.finditer(text):
        target = m.group(2).strip()
        if target.startswith(('http://', 'https://', 'mailto:', '#')):
            continue
        target = target.strip('<>')
        path_part, _, anchor = target.partition('#')
        if not path_part:
            dest = md
        else:
            dest = (md.parent / urllib.parse.unquote(path_part)).resolve()
        checked += 1
        if not dest.exists():
            print(f"  \033[31mFAIL\033[0m {md.relative_to(root)} -> {target} (文件不存在)")
            bad = 1
            continue
        if anchor and dest.suffix == '.md':
            want = urllib.parse.unquote(anchor)
            if want not in anchors(dest):
                print(f"  \033[31mFAIL\033[0m {md.relative_to(root)} -> {target} (锚点不存在)")
                bad = 1

print(f"  \033[32mOK\033[0m   检查 {checked} 个相对链接" if not bad else f"  \033[31mFAIL\033[0m 链接检查失败")
sys.exit(bad)
PY
[ $? -eq 0 ] || fail=1

echo "== 7. 敏感串粗筛 =="
hits=$(grep -rInE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}' . \
        --exclude-dir=.git 2>/dev/null || true)
if [ -n "$hits" ]; then
  bad "发现疑似密钥："; printf '%s\n' "$hits" | sed 's/^/       /'
else
  ok "未发现私钥/常见 token 模式"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "全部检查通过。"
else
  echo "存在失败项，请修复后再发布。"
fi
exit "$fail"
