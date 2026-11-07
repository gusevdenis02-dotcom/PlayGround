#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/dist"
PORT="${PORT:-3000}"

run_timed() {
  /usr/bin/time -p "$@"
}

run_timed bash -c 'cd "$1"' _ "$PROJECT_DIR"
cd "$PROJECT_DIR"
run_timed npm install --no-audit --no-fund
if [[ ! -f "$BUILD_DIR/index.html" || index.html -nt "$BUILD_DIR/index.html" || app.js -nt "$BUILD_DIR/app.js" || styles.css -nt "$BUILD_DIR/styles.css" ]]; then
  run_timed npm run build
fi
run_timed mkdir -p "${OPENCODE_WEB_DIR:?}"
run_timed node --input-type=module -e 'import { writeFile } from "node:fs/promises"; await writeFile("/home/runner/work/_temp/omgithub-web/deployment-output.json", JSON.stringify({ project: process.cwd(), directory: `${process.cwd()}/dist` }, null, 2) + "\n")'
export PORT
run_timed bash -c 'cd "$1" && exec node "$2/server.mjs"' _ "$BUILD_DIR" "$PROJECT_DIR"
