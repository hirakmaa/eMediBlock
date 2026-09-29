#!/bin/bash
# eMediBlock - GitHub upload
# Double-click this file. Nothing to copy, nothing to type.

cd "$(dirname "$0")" || exit 1

echo "============================================"
echo "  eMediBlock  ->  github.com/hirakmaa"
echo "============================================"
echo

# --- identity (only if not already set) ---
if [ -z "$(git config --global user.name)" ]; then
  git config --global user.name "Hirak Mazumdar"
  echo "set git user.name"
fi
if [ -z "$(git config --global user.email)" ]; then
  git config --global user.email "hirakm.tech.ece@gmail.com"
  echo "set git user.email"
fi

# --- repo ---
if [ ! -d .git ]; then
  git init -q
  git branch -M main
  echo "step 1/5  git repository created"
else
  echo "step 1/5  git repository already here"
fi

git add .
echo "step 2/5  files staged"

if git diff --cached --quiet 2>/dev/null; then
  echo "step 3/5  nothing new to commit"
else
  git commit -q -m "eMediBlock: contracts, attack suite, benchmarks and reproducibility artifact"
  echo "step 3/5  committed"
fi

git remote remove origin 2>/dev/null
git remote add origin https://github.com/hirakmaa/eMediBlock.git
echo "step 4/5  remote set"

echo
echo "step 5/5  uploading - a browser window may open, log in to GitHub there"
echo

if git push -u origin main; then
  git tag -f -a v1.0.0 -m "Version submitted with the manuscript revision" >/dev/null 2>&1
  git push -f origin v1.0.0 >/dev/null 2>&1
  echo
  echo "============================================"
  echo "  DONE."
  echo "  Open: https://github.com/hirakmaa/eMediBlock"
  echo "  You should see 36 files and a v1.0.0 release."
  echo "============================================"
else
  echo
  echo "============================================"
  echo "  UPLOAD FAILED."
  echo
  echo "  Most likely reason: the repository does not"
  echo "  exist yet on GitHub."
  echo
  echo "  Go to  https://github.com/new"
  echo "    Repository name : eMediBlock"
  echo "    Select          : Private"
  echo "    Tick NOTHING else"
  echo "  Press Create repository, then run this"
  echo "  file again."
  echo "============================================"
fi

echo
echo "Press any key to close."
read -n 1 -s
