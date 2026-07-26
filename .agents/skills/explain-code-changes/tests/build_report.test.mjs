import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { excludePaths, parseUnifiedDiff } from "../scripts/snapshot_diff.mjs";
import {
  buildReport,
  findExternalReferences,
  stripAuthoringComments
} from "../scripts/build_report.mjs";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const skillDirectory = path.join(testDirectory, "..");
const mermaidStub = path.join(testDirectory, "fixtures", "mermaid-stub.js");

async function snapshot() {
  const patch = await readFile(path.join(testDirectory, "fixtures", "sample.patch"), "utf8");
  const files = parseUnifiedDiff(patch);
  return {
    metadata: {
      reportId: "test-report",
      repository: "example/repository",
      baseRef: "main",
      baseCommit: "aaaaaaa",
      headRef: "feature/withdrawal",
      headCommit: "bbbbbbb",
      generatedAt: "2026-07-25T12:00:00.000Z",
      changedFiles: files.length,
      additions: files.reduce((total, file) => total + file.additions, 0),
      deletions: files.reduce((total, file) => total + file.deletions, 0)
    },
    files
  };
}

function codeChanges() {
  return {
    groups: [
      {
        id: "public-visibility",
        title: "退会者を公開対象から除外",
        members: [
          { file: "backend/app/models/user.rb", hunks: [0] },
          { file: "backend/app/models/profile.rb" }
        ]
      },
      {
        id: "regression-test",
        title: "回帰テストを追加",
        members: [{ file: "spec/models/user_spec.rb" }]
      }
    ],
    annotations: [
      { lineId: "backend/app/models/user.rb:0:4", text: "公開可否の入口をUserへ集約している" }
    ],
    findings: [
      {
        id: "finding-cache",
        groupId: "public-visibility",
        lineId: "backend/app/models/profile.rb:0:3",
        severity: "critical",
        category: "正確性",
        title: "キャッシュ済みデータで退会状態が再評価されない",
        detail: "キャッシュ期限まで退会者の情報を返す可能性がある。",
        suggestion: "返却直前に公開可否を再評価する。",
        file: "backend/app/models/profile.rb",
        line: 20
      },
      {
        id: "finding-coverage",
        groupId: "regression-test",
        lineId: null,
        severity: "warning",
        category: "テスト",
        title: "直接URL経由の確認が無い",
        detail: "一覧の除外しか検証していない。",
        suggestion: "直接URLでの参照不可も検証する。",
        file: "spec/models/user_spec.rb",
        line: 2
      }
    ]
  };
}

function chapters(overrides = {}) {
  return {
    summary: "<p>退会したコーチの情報が退会後も見えていた問題を塞いだ。</p>",
    "user-impact": '<div class="before-after"><div><h4>変更前</h4></div><div><h4>変更後</h4></div></div>',
    overview: '<pre class="mermaid">flowchart LR\n  a[利用者] --> b[公開プロフィール]</pre>',
    "code-changes":
      '<section data-group="public-visibility"><p>公開可否の判定をUserへ集約した。</p></section>' +
      '<section data-group="regression-test"><p>退会者が一覧に出ないことを固定した。</p></section>',
    ...overrides
  };
}

const CODE_REVIEW = [
  "## 正確性",
  "- Profile.active のサブクエリ化により <script>alert(1)</script> のような入力も安全に扱える",
  "## テスト",
  "- 直接URL経由の確認が無い"
].join("\n");

async function build(options = {}) {
  return buildReport({
    snapshot: options.snapshot ?? (await snapshot()),
    codeChanges: options.codeChanges ?? codeChanges(),
    chapters: options.chapters ?? chapters(),
    codeReview: "codeReview" in options ? options.codeReview : CODE_REVIEW,
    title: options.title ?? "退会者の公開情報を非表示にする変更",
    mermaidPath: options.mermaidPath ?? mermaidStub
  });
}

test("パッチから安定した行IDとファイル状態を読み取る", async () => {
  const files = parseUnifiedDiff(
    await readFile(path.join(testDirectory, "fixtures", "sample.patch"), "utf8")
  );

  assert.deepEqual(
    files.map((file) => file.path),
    ["backend/app/models/user.rb", "backend/app/models/profile.rb", "spec/models/user_spec.rb"]
  );
  assert.equal(files[2].status, "added");

  const added = files[0].hunks[0].lines.find((line) => line.type === "added" && line.content.includes("publicly_visible"));
  assert.equal(added.id, "backend/app/models/user.rb:0:4");
  assert.equal(added.newNumber, 12);
  assert.equal(added.oldNumber, null);

  const removed = files[1].hunks[0].lines.find((line) => line.type === "removed");
  assert.equal(removed.oldNumber, 20);
  assert.equal(removed.newNumber, null);
});

test("除外パス配下のファイルをレビュー対象から外す", () => {
  const files = [
    { path: "tmp/code_review_a.html" },
    { path: "tmp/explain/x/diff-snapshot.json" },
    { path: "app/tmp_helper.rb" },
    { path: "backend/app/models/user.rb" }
  ];

  assert.deepEqual(
    excludePaths(files, ["tmp"]).map((file) => file.path),
    ["app/tmp_helper.rb", "backend/app/models/user.rb"]
  );
  assert.equal(excludePaths(files, []).length, 4);
});

test("章断片が無い章はセクションごとレポートから消える", async () => {
  const withAll = await build();
  assert.match(withAll, /data-chapter="user-impact"/);
  assert.match(withAll, /data-chapter="overview"/);

  const withoutOverview = await build({ chapters: chapters({ overview: undefined }) });
  assert.doesNotMatch(withoutOverview, /data-chapter="overview"/);
  assert.doesNotMatch(withoutOverview, /変更の全体像/);
  assert.match(withoutOverview, /data-chapter="user-impact"/);
});

test("要旨とコード解説は省略できない", async () => {
  await assert.rejects(
    () => build({ chapters: chapters({ summary: undefined }) }),
    /章 "summary" は省略できません/
  );
});

test("内部品質レビューを飛ばした組み立てを拒否する", async () => {
  await assert.rejects(() => build({ codeReview: undefined }), /code-review の出力がありません/);
  await assert.rejects(() => build({ codeReview: "   \n  " }), /code-review の出力がありません/);
});

test("レビューの生出力をレポートへ添付し、そのまま表示しない値へ変換する", async () => {
  const html = await build();

  assert.match(html, /<summary>内部品質レビューの生出力<\/summary>/);
  assert.match(html, /## 正確性/);
  assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
});

test("差分の取りこぼしと二重割り当てを検出する", async () => {
  const missing = codeChanges();
  missing.groups[1].members = [];
  await assert.rejects(() => build({ codeChanges: missing }), /どのグループにも属さない hunk/);

  const duplicated = codeChanges();
  duplicated.groups[1].members = [{ file: "backend/app/models/profile.rb" }];
  await assert.rejects(() => build({ codeChanges: duplicated }), /両方に属しています/);
});

test("章断片の外部リソース参照を拒否する", async () => {
  await assert.rejects(
    () => build({ chapters: chapters({ overview: '<img src="https://example.com/a.png">' }) }),
    /外部リソースを参照しています/
  );
  assert.equal(findExternalReferences('<img src="./local.png">').length, 0);
  assert.equal(findExternalReferences("<style>@import url(//cdn.example.com/a.css);</style>").length, 1);
});

test("左右分割diffで削除を左、追加を右へ置き、行IDを持たせる", async () => {
  const html = await build();
  const rowEnd = html.indexOf("config_active.where");
  const row = html.slice(html.lastIndexOf('<div class="diff-row">', rowEnd), rowEnd);

  assert.match(row, /data-type="removed" data-line-id="backend\/app\/models\/profile\.rb:0:2"/);
  assert.match(row, /data-type="added" data-line-id="backend\/app\/models\/profile\.rb:0:3"/);
  assert.ok(
    row.indexOf('data-type="removed"') < row.indexOf('data-type="added"'),
    "削除が追加より左に来る"
  );
});

test("行に紐付く指摘は差分行へ、紐付かない指摘は変更意図の先頭へ出す", async () => {
  const html = await build();

  const lineFinding = html.indexOf("キャッシュ済みデータで退会状態が再評価されない");
  const extraStart = html.lastIndexOf('<div class="diff-extra">', lineFinding);
  assert.ok(extraStart > -1, "行に紐付く指摘が差分行の直後に出る");

  const groupFinding = html.indexOf("直接URL経由の確認が無い");
  const groupFindings = html.lastIndexOf('<div class="group-findings">', groupFinding);
  const panelStart = html.lastIndexOf('data-tab-panel="regression-test"', groupFinding);
  assert.ok(groupFindings > panelStart, "行に紐付かない指摘は変更意図の先頭に出る");
  assert.ok(html.indexOf('<div class="diff"', panelStart) > groupFinding, "差分より前に出る");
});

test("注釈は差分行の直後に一度だけ出す", async () => {
  const html = await build();
  const occurrences = html.split("公開可否の入口をUserへ集約している").length - 1;
  assert.equal(occurrences, 1);
});

test("執筆指示コメントを成果物から取り除き、CSSとJSは保つ", async () => {
  const html = await build();
  assert.doesNotMatch(html, /省略基準/);
  assert.doesNotMatch(html, /<!--/);
  assert.match(html, /\.diff-cell/);
  assert.match(html, /function buildFeedback/);

  const preserved = stripAuthoringComments(
    "<!-- 指示 -->\n<style>a{content:'<!--'}</style><script>const a = 1;</script><p>本文</p>"
  );
  assert.doesNotMatch(preserved, /指示/);
  assert.match(preserved, /const a = 1;/);
  assert.match(preserved, /<p>本文<\/p>/);
});

test("レポートのメタデータを埋め込み、スクリプト終端を許さない", async () => {
  const injected = await snapshot();
  const changes = codeChanges();
  changes.groups[0].title = "</script><script>globalThis.compromised = true</script>";

  const html = await buildReport({
    snapshot: injected,
    codeChanges: changes,
    chapters: chapters(),
    codeReview: CODE_REVIEW,
    title: "テスト",
    mermaidPath: mermaidStub
  });

  const meta = JSON.parse(html.match(/const meta = (\{.*?\});\n/s)[1]);
  assert.equal(meta.reportId, "test-report");
  assert.equal(meta.title, "テスト");
  assert.equal(Object.keys(meta.lines).length > 0, true);
  assert.doesNotMatch(html, /<\/script><script>globalThis\.compromised/);
});

test("Mermaidを同梱し、生成物が外部通信しない", async () => {
  const html = await buildReport({
    snapshot: await snapshot(),
    codeChanges: codeChanges(),
    chapters: chapters(),
    codeReview: CODE_REVIEW,
    mermaidPath: path.join(skillDirectory, "assets", "vendor", "mermaid.min.js")
  });

  assert.match(html, /globalThis\["mermaid"\]/);
  const markup = html.replace(/<script\b[\s\S]*?<\/script>/gi, "");
  assert.deepEqual(findExternalReferences(markup), []);
});

test("CLIが章ディレクトリからレポートを生成する", async () => {
  const workspace = await mkdtemp(path.join(tmpdir(), "explain-code-changes-"));
  const chapterDirectory = path.join(workspace, "chapters");
  await mkdir(chapterDirectory, { recursive: true });

  await writeFile(path.join(workspace, "diff-snapshot.json"), JSON.stringify(await snapshot()), "utf8");
  await writeFile(path.join(workspace, "code-changes.json"), JSON.stringify(codeChanges()), "utf8");
  await writeFile(path.join(workspace, "code-review.md"), CODE_REVIEW, "utf8");
  for (const [name, fragment] of Object.entries(chapters({ overview: undefined }))) {
    if (fragment) await writeFile(path.join(chapterDirectory, `${name}.html`), fragment, "utf8");
  }

  const { spawnSync } = await import("node:child_process");
  const outputPath = path.join(workspace, "report.html");
  const result = spawnSync(
    process.execPath,
    [
      path.join(skillDirectory, "scripts", "build_report.mjs"),
      "--diff", path.join(workspace, "diff-snapshot.json"),
      "--code-changes", path.join(workspace, "code-changes.json"),
      "--chapters", chapterDirectory,
      "--code-review", path.join(workspace, "code-review.md"),
      "--title", "退会者の公開情報を非表示にする変更",
      "--output", outputPath
    ],
    { encoding: "utf8" }
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /省略した章: overview/);

  const html = await readFile(outputPath, "utf8");
  assert.match(html, /退会者の公開情報を非表示にする変更/);
  assert.match(html, /data-tab="public-visibility"/);
});
