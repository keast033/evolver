#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('fs');
const path = require('path');

function readJson(filePath, fallback) {
  try {
    if (!fs.existsSync(filePath)) return fallback;
    const raw = fs.readFileSync(filePath, 'utf8');
    if (!raw.trim()) return fallback;
    return JSON.parse(raw);
  } catch (_err) {
    return fallback;
  }
}

function readLastJsonl(filePath) {
  try {
    if (!fs.existsSync(filePath)) return null;
    const lines = fs.readFileSync(filePath, 'utf8')
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean);
    if (lines.length === 0) return null;
    return JSON.parse(lines[lines.length - 1]);
  } catch (_err) {
    return null;
  }
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeFile(targetPath, content) {
  ensureDir(path.dirname(targetPath));
  fs.writeFileSync(targetPath, content, 'utf8');
}

function clip(text, maxLen) {
  const s = String(text || '');
  return s.length <= maxLen ? s : s.slice(0, Math.max(0, maxLen - 3)) + '...';
}

function main() {
  const repoRoot = process.cwd();
  const targetProjectRoot = process.env.EVOLVER_TARGET_PROJECT_ROOT
    ? path.resolve(process.env.EVOLVER_TARGET_PROJECT_ROOT)
    : repoRoot;
  const assetsDir = path.join(repoRoot, 'assets', 'gep');
  const genes = (readJson(path.join(assetsDir, 'genes.json'), { genes: [] }).genes || []).filter(Boolean);
  const capsules = (readJson(path.join(assetsDir, 'capsules.json'), { capsules: [] }).capsules || []).filter(Boolean);
  const lastEvent = readLastJsonl(path.join(assetsDir, 'events.jsonl'));
  const lastCapsule = capsules[capsules.length - 1] || null;

  const activeGenes = genes
    .slice()
    .sort((a, b) => String((b.learning_history && b.learning_history[0] && b.learning_history[0].at) || '').localeCompare(String((a.learning_history && a.learning_history[0] && a.learning_history[0].at) || '')))
    .slice(0, 3);

  const ruleLines = [];
  ruleLines.push('---');
  ruleLines.push('description: Runtime guidance synced from Evolver Gene/Capsule/Event assets.');
  ruleLines.push('globs: ["**/*"]');
  ruleLines.push('alwaysApply: false');
  ruleLines.push('---');
  ruleLines.push('');
  ruleLines.push('# Evolver Runtime Rule (Auto-Exported)');
  ruleLines.push('');
  ruleLines.push(`Generated at: ${new Date().toISOString()}`);
  if (lastEvent && lastEvent.id) ruleLines.push(`Last event: ${lastEvent.id}`);
  if (lastCapsule && lastCapsule.id) ruleLines.push(`Last capsule: ${lastCapsule.id}`);
  ruleLines.push('');
  ruleLines.push('## Prioritize');
  for (const g of activeGenes) {
    ruleLines.push(`- ${g.id}: ${clip((g.strategy || []).slice(0, 2).join(' | '), 260)}`);
  }
  ruleLines.push('');
  ruleLines.push('## Guardrails');
  ruleLines.push('- Keep changes reversible and validate before solidify.');
  ruleLines.push('- Respect max_files and forbidden_paths from selected Gene.');
  ruleLines.push('- Prefer reusing existing Gene/Capsule patterns before creating new ones.');
  ruleLines.push('');
  ruleLines.push('## Runtime Focus');
  if (lastCapsule && Array.isArray(lastCapsule.trigger) && lastCapsule.trigger.length > 0) {
    ruleLines.push(`- Latest successful triggers: ${lastCapsule.trigger.slice(0, 8).join(', ')}`);
  } else {
    ruleLines.push('- No successful capsule yet; focus on stable repair-first cycles.');
  }
  ruleLines.push('');
  const ruleContent = ruleLines.join('\n') + '\n';

  const promptLines = [];
  promptLines.push('# Evolver Prompt Snapshot (Auto-Exported)');
  promptLines.push('');
  promptLines.push(`Generated at: ${new Date().toISOString()}`);
  promptLines.push('');
  if (lastEvent) {
    promptLines.push('## Last Evolution Event');
    promptLines.push(`- id: ${lastEvent.id || 'unknown'}`);
    promptLines.push(`- intent: ${lastEvent.intent || 'unknown'}`);
    const evSignals = Array.isArray(lastEvent.signals) ? lastEvent.signals.slice(0, 10).join(', ') : 'none';
    promptLines.push(`- signals: ${evSignals}`);
    promptLines.push('');
  }
  promptLines.push('## Top Gene Strategies');
  for (const g of activeGenes) {
    promptLines.push(`### ${g.id} (${g.category || 'unknown'})`);
    for (const step of (g.strategy || []).slice(0, 6)) {
      promptLines.push(`- ${step}`);
    }
    promptLines.push('');
  }
  const promptContent = promptLines.join('\n') + '\n';

  const flowLines = [];
  flowLines.push('# Evolver Subflow (Auto-Exported)');
  flowLines.push('');
  flowLines.push('1. Run `node index.js` to generate a candidate cycle.');
  flowLines.push('2. Inspect with `node index.js --review`.');
  flowLines.push('3. Approve with `node index.js review --approve` only after validation expectations are met.');
  flowLines.push('4. Re-export runtime assets (this script) to refresh Cursor rules/prompt snapshots.');
  flowLines.push('');
  flowLines.push('## Current Focus Signals');
  if (lastCapsule && Array.isArray(lastCapsule.trigger) && lastCapsule.trigger.length > 0) {
    for (const signal of lastCapsule.trigger.slice(0, 10)) flowLines.push(`- ${signal}`);
  } else {
    flowLines.push('- no_success_capsule_yet');
  }
  flowLines.push('');
  const flowContent = flowLines.join('\n') + '\n';

  const cursorRulePath = path.join(targetProjectRoot, '.cursor', 'rules', 'evolver-runtime.mdc');
  const claudeRulePath = path.join(targetProjectRoot, '.claude', 'rules', 'evolver-runtime.mdc');
  const promptPath = path.join(targetProjectRoot, 'memory', 'prompts', 'evolver-latest.md');
  const flowPath = path.join(targetProjectRoot, 'memory', 'workflows', 'evolver-subflow.md');

  writeFile(cursorRulePath, ruleContent);
  writeFile(claudeRulePath, ruleContent);
  writeFile(promptPath, promptContent);
  writeFile(flowPath, flowContent);

  console.log('[export-runtime-assets] Wrote ' + cursorRulePath);
  console.log('[export-runtime-assets] Wrote ' + claudeRulePath);
  console.log('[export-runtime-assets] Wrote ' + promptPath);
  console.log('[export-runtime-assets] Wrote ' + flowPath);
}

if (require.main === module) {
  main();
}

module.exports = { main };
