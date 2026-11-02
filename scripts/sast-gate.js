// Reads the SAST JSON report, writes a Markdown summary, and exits 1 if any HIGH or CRITICAL finding exists.
// It does not assume the scanner's exact JSON shape. It walks the whole report and treats any object
// with a severity, level, risk or priority field as a finding.

const fs = require("fs");

const reportPath = process.argv[2] || "sast-report.json";
const summaryPath = process.argv[3] || "sast-summary.md";

function writeSummary(text) {
  fs.writeFileSync(summaryPath, text);
  console.log(text);
}

let raw;
try {
  raw = fs.readFileSync(reportPath, "utf8");
} catch (err) {
  writeSummary("## SAST gate failed\n\nNo report was found at `" + reportPath + "`. Check the Run SAST step in the workflow log.\n");
  process.exit(1);
}

function parseReport(text) {
  try {
    return JSON.parse(text);
  } catch (err) {
    const starts = [text.indexOf("{"), text.indexOf("[")].filter((i) => i >= 0);
    if (starts.length === 0) throw err;
    return JSON.parse(text.slice(Math.min(...starts)));
  }
}

let data;
try {
  data = parseReport(raw);
} catch (err) {
  writeSummary("## SAST gate failed\n\nThe report at `" + reportPath + "` is not valid JSON. Check the scanner's output format.\n");
  process.exit(1);
}

const SEVERITY_KEYS = ["severity", "level", "risk", "priority"];
const TITLE_KEYS = ["type", "title", "name", "rule", "ruleId", "vulnerability", "message", "description"];
const FILE_KEYS = ["file", "filePath", "filename", "path", "location"];

function pick(obj, keys) {
  for (const key of Object.keys(obj)) {
    if (keys.some((k) => k.toLowerCase() === key.toLowerCase())) {
      const value = obj[key];
      if (typeof value === "string" || typeof value === "number") return String(value);
    }
  }
  return "";
}

const findings = [];

function walk(node) {
  if (Array.isArray(node)) {
    node.forEach(walk);
    return;
  }
  if (node && typeof node === "object") {
    const severity = pick(node, SEVERITY_KEYS).toUpperCase();
    if (severity) {
      findings.push({
        severity,
        title: pick(node, TITLE_KEYS) || "Unnamed finding",
        file: pick(node, FILE_KEYS),
        line: pick(node, ["line", "lineNumber"]),
      });
    }
    Object.values(node).forEach(walk);
  }
}

walk(data);

const high = findings.filter((f) => f.severity === "HIGH" || f.severity === "CRITICAL");
const medium = findings.filter((f) => f.severity === "MEDIUM");

function row(f) {
  const where = f.file ? f.file + (f.line ? ":" + f.line : "") : "";
  return "| " + f.severity + " | " + f.title.replace(/\|/g, "/") + " | " + where + " |";
}

let text = high.length > 0 ? "## SAST gate blocked this pull request\n\n" : "## SAST gate passed\n\n";
text += "HIGH or CRITICAL findings " + high.length + ", MEDIUM findings " + medium.length + ", total findings " + findings.length + ".\n\n";

const shown = high.concat(medium);
if (shown.length > 0) {
  text += "| Severity | Finding | Location |\n|---|---|---|\n";
  text += shown.slice(0, 50).map(row).join("\n") + "\n";
}
if (high.length === 0 && medium.length > 0) {
  text += "\nMEDIUM findings do not block the merge, but please review them.\n";
}

writeSummary(text);
process.exit(high.length > 0 ? 1 : 0);
