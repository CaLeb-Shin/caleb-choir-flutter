#!/usr/bin/env bash
# Commit current changes and push to GitHub. Vercel auto-deploys on push.
# Usage: ./deploy.sh "optional commit message"
set -euo pipefail

cd "$(dirname "$0")"

MSG="${1:-chore: deploy}"
git add -A
git commit -m "$MSG" --allow-empty
git push
echo "Pushed. Vercel will auto-deploy https://caleb-choir-flutter.vercel.app shortly."
