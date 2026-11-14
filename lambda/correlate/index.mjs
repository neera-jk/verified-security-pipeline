import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";

const s3 = new S3Client({});
const ddb = new DynamoDBClient({});
const TABLE = process.env.TABLE_NAME;

const CATEGORIES = [
  ["NoSQL injection", /nosql|mongo/i],
  ["SQL injection", /(^|[^o])sql/i],
  ["Hardcoded secret", /hard.?coded|secret|password|api.?key|credential/i],
  ["Cross site scripting", /xss|cross.?site/i],
  ["Missing authentication", /auth/i],
];

async function readJson(bucket, key) {
  try {
    const res = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    return JSON.parse(await res.Body.transformToString());
  } catch (err) {
    if (err.name === "NoSuchKey") return null;
    throw err;
  }
}

function collectFindings(node, out = []) {
  if (Array.isArray(node)) {
    node.forEach((item) => collectFindings(item, out));
  } else if (node && typeof node === "object") {
    const keys = Object.keys(node).map((k) => k.toLowerCase());
    if (keys.some((k) => ["severity", "level", "risk", "priority"].includes(k))) out.push(node);
    Object.values(node).forEach((v) => collectFindings(v, out));
  }
  return out;
}

function categories(report) {
  const found = new Set();
  for (const finding of collectFindings(report)) {
    const text = JSON.stringify(finding);
    if (/"status"\s*:\s*"PASS"/i.test(text)) continue;
    for (const [name, pattern] of CATEGORIES) {
      if (pattern.test(text)) { found.add(name); break; }
    }
  }
  return found;
}

export const handler = async (event) => {
  for (const record of event.Records) {
    const bucket = record.s3.bucket.name;
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
    const sha = key.split("/").pop().replace(/\.json$/, "");

    const sast = await readJson(bucket, `sast/${sha}.json`);
    const pentest = await readJson(bucket, `pentest/${sha}.json`);
    if (!sast || !pentest) {
      console.log(`Waiting for the ${sast ? "pentest" : "sast"} report for ${sha}`);
      continue;
    }

    const sastCats = categories(sast);
    const pentestCats = categories(pentest);
    const confirmed = [...sastCats].filter((c) => pentestCats.has(c));
    const suspected = [...new Set([...sastCats, ...pentestCats])].filter((c) => !confirmed.includes(c));
    console.log(`${sha}: ${confirmed.length} Confirmed, ${suspected.length} Suspected`, { confirmed, suspected });

    const verified = { sha, createdAt: new Date().toISOString(), confirmed, suspected };
    await s3.send(new PutObjectCommand({
      Bucket: bucket,
      Key: `verified/${sha}.json`,
      Body: JSON.stringify(verified, null, 2),
      ContentType: "application/json",
    }));

    try {
      await ddb.send(new PutItemCommand({
        TableName: TABLE,
        Item: {
          sha: { S: sha },
          createdAt: { S: verified.createdAt },
          confirmedCount: { N: String(confirmed.length) },
          suspectedCount: { N: String(suspected.length) },
          reportKey: { S: `verified/${sha}.json` },
        },
        ConditionExpression: "attribute_not_exists(sha)",
      }));
      console.log(`Indexed ${sha}`);
    } catch (err) {
      if (err.name === "ConditionalCheckFailedException") {
        console.log(`${sha} is already indexed, skipping`);
      } else {
        throw err;
      }
    }
  }
};
