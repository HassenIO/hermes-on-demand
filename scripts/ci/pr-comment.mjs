#!/usr/bin/env node
// Runs in GitHub Actions. Posts or updates one PR comment, then exits
// non-zero if lint or test failed. Not a VPS script. No extra packages.

import fs from "node:fs";

const MARKER = "<!-- hermes-pr-checks -->";

export function clip(text) {
  const trimmed = (text || "").trim();
  if (!trimmed) return "_no output_";
  const lines = trimmed.split("\n").slice(-40).join("\n");
  return lines.length > 2500 ? lines.slice(-2500) : lines;
}

export function readLog(path) {
  try {
    return clip(fs.readFileSync(path, "utf8"));
  } catch {
    return "_log missing_";
  }
}

export function label(outcome) {
  return outcome === "success" ? "pass" : "fail";
}

export function reportBody({ lint, test, lintLog, testLog, sha }) {
  return [
    MARKER,
    "## PR checks",
    "",
    "| Check | Result |",
    "| --- | --- |",
    `| Lint (\`make lint\`) | ${label(lint)} |`,
    `| Tests (\`make test\`) | ${label(test)} |`,
    "",
    "### Lint",
    "```",
    lintLog,
    "```",
    "",
    "### Tests",
    "```",
    testLog,
    "```",
    "",
    `Commit \`${sha}\`.`,
  ].join("\n");
}

export function checksFailed(lint, test) {
  return lint !== "success" || test !== "success";
}

function api(token, path, options = {}) {
  return fetch(`https://api.github.com${path}`, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      ...(options.headers || {}),
    },
  });
}

async function upsertComment(token, repo, number, body) {
  const list = await api(
    token,
    `/repos/${repo}/issues/${number}/comments?per_page=100`,
  );
  if (!list.ok) {
    throw new Error(`list comments failed: ${list.status}`);
  }
  const comments = await list.json();
  const existing = comments.find((comment) => comment.body && comment.body.includes(MARKER));
  if (existing) {
    const update = await api(token, `/repos/${repo}/issues/comments/${existing.id}`, {
      method: "PATCH",
      body: JSON.stringify({ body }),
    });
    if (!update.ok) {
      throw new Error(`update comment failed: ${update.status}`);
    }
    return;
  }
  const create = await api(token, `/repos/${repo}/issues/${number}/comments`, {
    method: "POST",
    body: JSON.stringify({ body }),
  });
  if (!create.ok) {
    throw new Error(`create comment failed: ${create.status}`);
  }
}

async function main() {
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  const repo = process.env.GITHUB_REPOSITORY;
  const sha = process.env.GITHUB_SHA || "unknown";
  const lint = process.env.LINT_OUTCOME || "failure";
  const test = process.env.TEST_OUTCOME || "failure";
  const eventPath = process.env.GITHUB_EVENT_PATH;
  if (!token || !repo || !eventPath) {
    throw new Error("GITHUB_TOKEN, GITHUB_REPOSITORY, and GITHUB_EVENT_PATH are required");
  }
  const event = JSON.parse(fs.readFileSync(eventPath, "utf8"));
  const number = event.pull_request && event.pull_request.number;
  if (!number) {
    throw new Error("not a pull request event");
  }
  const body = reportBody({
    lint,
    test,
    lintLog: readLog("lint.txt"),
    testLog: readLog("test.txt"),
    sha,
  });
  await upsertComment(token, repo, number, body);
  if (checksFailed(lint, test)) {
    process.exitCode = 1;
  }
}

const isDirectRun = process.argv[1] && process.argv[1].endsWith("pr-comment.mjs");
if (isDirectRun) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}
