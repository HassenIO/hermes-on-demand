#!/usr/bin/env node
// Runs in GitHub Actions. Requests a Copilot code review when a PR is opened.
// Not a VPS script. No extra packages. Never fails the job: a failed request
// is logged as a workflow warning.

import fs from "node:fs";

export const COPILOT_REVIEWER = "copilot-pull-request-reviewer[bot]";

export function shouldRequest(action) {
  return action === "opened";
}

export function reviewPayload() {
  return { reviewers: [COPILOT_REVIEWER] };
}

export function warning(message) {
  return `::warning title=Copilot review::${message}`;
}

async function requestReview(token, repo, number) {
  const response = await fetch(
    `https://api.github.com/repos/${repo}/pulls/${number}/requested_reviewers`,
    {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
      },
      body: JSON.stringify(reviewPayload()),
    },
  );
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`request failed: ${response.status} ${detail}`);
  }
}

async function main() {
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
  const repo = process.env.GITHUB_REPOSITORY;
  const eventPath = process.env.GITHUB_EVENT_PATH;
  if (!token || !repo || !eventPath) {
    throw new Error("GITHUB_TOKEN, GITHUB_REPOSITORY, and GITHUB_EVENT_PATH are required");
  }
  const event = JSON.parse(fs.readFileSync(eventPath, "utf8"));
  if (!shouldRequest(event.action)) {
    console.log(`Copilot review not requested: event action is ${event.action}`);
    return;
  }
  const number = event.pull_request && event.pull_request.number;
  if (!number) {
    throw new Error("not a pull request event");
  }
  await requestReview(token, repo, number);
  console.log(`Copilot review requested on #${number}`);
}

const isDirectRun = process.argv[1] && process.argv[1].endsWith("request-copilot-review.mjs");
if (isDirectRun) {
  main().catch((err) => {
    console.log(warning(err.message || String(err)));
  });
}
