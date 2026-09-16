import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const require = createRequire(import.meta.url);
const { parse: parseYAML } = require('yaml');

function hookRunDirectory(path) {
  const boundary = path.indexOf(`${sep}hooks-output${sep}`);
  return boundary < 0 ? null : path.slice(0, boundary);
}

function configurationSummary(path) {
  const config = parseYAML(readFileSync(path, 'utf8'));
  const initial = config.steps.find((step) => step.name === 'Phase 1 - Setup Initial Sandboxes');
  const wait = config.steps.find((step) => step.name === 'Phase 1 - Wait for Sandboxes');
  const desiredPodCount = wait?.measurements?.[0]?.params?.desiredPodCount;
  if (wait) assert.ok(Number.isFinite(desiredPodCount), `Missing desiredPodCount: ${path}`);
  return {
    tuningSets: config.tuningsets,
    desiredPodCount,
    initialPhases: initial?.phases,
    churnSteps: config.steps.filter((step) => step.name?.startsWith('Phase 2 - Recreate')).map((step) => ({ name: step.name, phases: step.phases })),
  };
}

function junitSummary(path) {
  const xpath = "concat(string((//testsuite)[1]/@time),'|',count(//failure),'|',count(//error),'|',sum(//testcase[contains(@name,'Phase 1 - Setup Initial Sandboxes') or contains(@name,'Phase 1 - Wait for Sandboxes')]/@time))";
  const [suiteSeconds, failureElements, errorElements, initialSetupAndWaitSeconds] = execFileSync('xmllint', ['--nonet', '--xpath', xpath, path], { encoding: 'utf8' }).trim().split('|').map(Number);
  const failureCases = execFileSync('xmllint', ['--nonet', '--xpath', 'string(//testcase[failure or error][1])', path], { encoding: 'utf8' }).trim();
  return { suiteSeconds, failureElements, errorElements, initialSetupAndWaitSeconds, firstFailure: failureCases };
}

function csvCell(value) {
  return `"${String(value ?? '').replaceAll('"', '""')}"`;
}

function metricRows(document, source) {
  if (!Array.isArray(document.dataItems)) return [];
  return document.dataItems.flatMap((item, itemIndex) => {
    const labels = item.labels ?? {};
    return Object.entries(item.data ?? {}).map(([statistic, value]) => ({
      source, itemIndex, metric: labels.Metric ?? '',
      labels: JSON.stringify(labels), unit: item.unit ?? '', statistic,
      value: typeof value === 'object' ? JSON.stringify(value) : value,
    }));
  });
}

function startupRows(document, source) {
  assert.ok(Array.isArray(document.dataItems), `Missing dataItems: ${source}`);
  return document.dataItems.map((item) => {
    assert.ok(['ms', 's'].includes(item.unit), `Unknown unit in ${source}: ${item.unit}`);
    const divisor = item.unit === 'ms' ? 1000 : 1;
    const values = ['Perc50', 'Perc90', 'Perc99'].map((key) => {
      const value = item.data?.[key];
      assert.ok(Number.isFinite(value), `Missing ${key}: ${source}`);
      return value / divisor;
    });
    assert.ok(values[0] <= values[1] && values[1] <= values[2], `Unordered percentiles: ${source}`);
    return { source, metric: item.labels.Metric, p50_s: values[0], p90_s: values[1], p99_s: values[2] };
  });
}

function selfTest() {
  const document = { dataItems: [{ labels: { Metric: 'schedule_to_run' }, unit: 'ms', data: { Perc50: 1000, Perc90: 2000, Perc99: 3000 } }] };
  assert.equal(startupRows(document, 'test')[0].p99_s, 3);
  assert.equal(metricRows(document, 'test').length, 3);
  assert.equal(csvCell('a,"b'), '"a,""b"');
  assert.deepEqual(metricRows({}, 'metadata'), []);
  assert.throws(() => startupRows({ dataItems: [{ ...document.dataItems[0], unit: 'unknown' }] }, 'test'));
  assert.throws(() => startupRows({ dataItems: [{ ...document.dataItems[0], data: { Perc50: 4, Perc90: 2, Perc99: 3 } }] }, 'test'));
  assert.equal(parseYAML('desiredPodCount: 35000').desiredPodCount, 35000);
  assert.equal(hookRunDirectory('/artifacts/tier-initial/hooks-output/post-test.log'), '/artifacts/tier-initial');
  assert.equal(hookRunDirectory('/artifacts/tier/report.json'), null);
  assert.equal(execFileSync('xmllint', ['--nonet', '--xpath', 'count(//failure)', '-'], { input: '<testsuites><testsuite><testcase><failure>timeout</failure></testcase></testsuite></testsuites>', encoding: 'utf8' }).trim(), '1');
  console.log('Extractor self-tests passed');
}

const { values: options } = parseArgs({ options: {
  'self-test': { type: 'boolean' },
  root: { type: 'string' },
  output: { type: 'string' },
  revision: { type: 'string' },
} });

if (options['self-test']) {
  selfTest();
} else {
  const scriptDir = dirname(fileURLToPath(import.meta.url));
  const outputDir = resolve(options.output ?? scriptDir);
  const root = resolve(options.root ?? join(scriptDir, '..'));
  const files = [];
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name, 'en'))) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) visit(path);
      else if (entry.isFile()) files.push(path);
    }
  };
  for (const directory of ['artifacts', 'artifacts_pods', 'manifests/agentic-sandbox/reports']) visit(join(root, directory));
  const metrics = [];
  const startup = [];
  const jsonFiles = [];
  const invalidJson = [];
  const configs = files.filter((path) => path.includes('/generatedConfig_'));
  for (const path of files.filter((path) => path.endsWith('.json'))) {
    const source = relative(root, path);
    const content = readFileSync(path);
    try {
      const document = JSON.parse(content);
      const rows = metricRows(document, source);
      metrics.push(...rows);
      jsonFiles.push({ source, sha256: createHash('sha256').update(content).digest('hex'), metricValues: rows.length });
      if (path.split('/').at(-1).startsWith('PodStartupLatency_')) startup.push(...startupRows(document, source));
    } catch (error) {
      invalidJson.push({ source, error: error.message });
    }
  }
  const reportSources = [...new Set(startup.map((row) => row.source))];
  const diagnosticDirectories = files.map(hookRunDirectory).filter((directory) => directory !== null);
  const runDirectories = [...new Set([...configs.map(dirname), ...reportSources.map((source) => dirname(join(root, source))), ...diagnosticDirectories])].sort();
  const runs = runDirectories.map((directory) => ({
    directory: relative(root, directory),
    fileCount: files.filter((path) => path.startsWith(`${directory}/`)).length,
    hookFiles: files.filter((path) => hookRunDirectory(path) === directory).map((path) => relative(root, path)),
    startupReports: reportSources.filter((source) => dirname(join(root, source)) === directory),
    junitFiles: files.filter((path) => dirname(path) === directory && path.endsWith('/junit.xml')).map((path) => relative(root, path)),
    configuration: configs.filter((path) => dirname(path) === directory).map((path) => relative(root, path)),
    configDetails: configs.filter((path) => dirname(path) === directory).map(configurationSummary),
    junit: files.filter((path) => dirname(path) === directory && path.endsWith('/junit.xml')).map(junitSummary),
  }));
  const writeCSV = (name, rows, columns) => writeFileSync(join(outputDir, name), [columns.map(csvCell).join(','), ...rows.map((row) => columns.map((column) => csvCell(row[column])).join(','))].join('\n') + '\n');
  mkdirSync(outputDir, { recursive: true });
  writeCSV('metrics.csv', metrics, ['source', 'itemIndex', 'metric', 'labels', 'unit', 'statistic', 'value']);
  writeCSV('startup.csv', startup, ['source', 'metric', 'p50_s', 'p90_s', 'p99_s']);
  writeFileSync(join(outputDir, 'inventory.json'), JSON.stringify({
    sourceRevision: options.revision ?? null,
    roots: ['artifacts', 'artifacts_pods', 'manifests/agentic-sandbox/reports'],
    fileCount: files.length, jsonCount: jsonFiles.length, metricValueCount: metrics.length,
    startupReportCount: reportSources.length, invalidJson, runs, jsonFiles,
  }, null, 2) + '\n');
  const notes = ['# Extracted Startup Reports', '',
    'Generated by `node submission/analyze.mjs`. Values are seconds, directly converted',
    'from each report. These are per-run summaries, not independent trials, confidence',
    'intervals, or proof that a run completed successfully. Do not add component',
    'percentiles. Report filenames do not establish tested software versions.', '',
    `Source revision: ${options.revision ?? 'local working tree (not pinned)'}.`, '',
    `Inventory: ${files.length} files, ${jsonFiles.length} parsed JSON files, ${metrics.length} metric values, ${reportSources.length} startup reports.`, '',
    '| Run / Source | Metric | P50 (s) | P90 (s) | P99 (s) |',
    '| --- | --- | ---: | ---: | ---: |'];
  for (const row of startup.filter((row) => ['create_to_schedule', 'schedule_to_run', 'pod_startup'].includes(row.metric))) {
    notes.push(`| [${dirname(row.source)}](${encodeURI(relative(outputDir, join(root, row.source)))}) | ${row.metric} | ${row.p50_s.toFixed(4)} | ${row.p90_s.toFixed(4)} | ${row.p99_s.toFixed(4)} |`);
  }
  notes.push('', '## Runs Without A Startup Report', '');
  for (const run of runs.filter((run) => run.startupReports.length === 0)) notes.push(`- ${run.directory}: ${run.fileCount} files; completion and failure cause require independent evidence.`);
  notes.push('', '## JUnit Outcomes', '', 'Failure counts include both overall and individual test cases; they are not counts of failed Pods.', '', '| Run | Failure Elements | Error Elements | Initial Setup + Wait (s) | Suite (s) |', '| --- | ---: | ---: | ---: | ---: |');
  for (const run of runs) for (const junit of run.junit) notes.push(`| ${run.directory} | ${junit.failureElements} | ${junit.errorElements} | ${junit.initialSetupAndWaitSeconds.toFixed(3)} | ${junit.suiteSeconds.toFixed(3)} |`);
  notes.push('', '## Parse Or Schema Errors', '', ...invalidJson.map((entry) => `- ${entry.source}: ${entry.error}`));
  if (invalidJson.length === 0) notes.push('None.');
  writeFileSync(join(outputDir, 'extracted-results.md'), notes.join('\n') + '\n');
  console.log(JSON.stringify({ files: files.length, json: jsonFiles.length, metricValues: metrics.length, startupReports: reportSources.length, runs: runs.length, runsWithoutStartup: runs.filter((run) => run.startupReports.length === 0).length, invalidJson }, null, 2));
  if (invalidJson.length) process.exitCode = 1;
}