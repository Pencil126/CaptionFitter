// Fails when the English and Traditional Chinese versions of the site drift apart:
// a UI string or a docs page that exists in one language but not the other.
import { readFileSync, readdirSync } from "node:fs";

const root = new URL("../", import.meta.url);
const problems = [];

function keys(object, prefix = "") {
  return Object.entries(object).flatMap(([key, value]) =>
    value && typeof value === "object"
      ? keys(value, `${prefix}${key}.`)
      : [`${prefix}${key}`],
  );
}

function compare(label, english, chinese) {
  const en = new Set(english);
  const zh = new Set(chinese);
  for (const item of en)
    if (!zh.has(item)) problems.push(`${label}: "${item}" is missing in zh-TW`);
  for (const item of zh)
    if (!en.has(item)) problems.push(`${label}: "${item}" is missing in en`);
}

const strings = (code) =>
  JSON.parse(readFileSync(new URL(`i18n/locales/${code}.json`, root), "utf8"));
compare("i18n/locales", keys(strings("en")), keys(strings("zh-TW")));

const docs = (code) =>
  readdirSync(new URL(`content/${code}/docs`, root)).filter((f) =>
    f.endsWith(".md"),
  );
compare("content/*/docs", docs("en"), docs("zh-TW"));

// Each page's sidebar position must match too.
const order = (code, file) =>
  readFileSync(new URL(`content/${code}/docs/${file}`, root), "utf8").match(
    /^order:\s*(\d+)/m,
  )?.[1];
for (const file of docs("en").filter((f) => docs("zh-TW").includes(f))) {
  if (order("en", file) !== order("zh-TW", file)) {
    problems.push(
      `content/*/docs/${file}: "order" differs between en and zh-TW`,
    );
  }
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
console.log("English and Traditional Chinese match.");
