// Command line wrapper around the provided SAST scanner.
// Usage: node tools/sast/cli.js <folder>
// Prints the scan results as JSON so a script or a CI job can read them.

import path from "path";
import fs from "fs";
import { scanDirectory } from "./scanner.js";

const folderArgument = process.argv[2];

if (!folderArgument) {
    console.error("Usage: node cli.js <folder to scan>");
    process.exit(2);
}

const folderToScan = path.resolve(folderArgument);

if (!fs.existsSync(folderToScan)) {
    console.error("Folder not found: " + folderToScan);
    process.exit(2);
}

const results = await scanDirectory(folderToScan);
console.log(JSON.stringify(results, null, 2));