import { cp, mkdir, rm } from "node:fs/promises";
import { resolve } from "node:path";

const projectDir = process.cwd();
const outputDir = resolve(projectDir, "dist");
await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });
for (const file of ["index.html", "app.js", "styles.css"]) {
  await cp(resolve(projectDir, file), resolve(outputDir, file));
}
console.log(`Built static app in ${outputDir}`);
