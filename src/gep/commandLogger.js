const fs = require('fs');
const path = require('path');
const { getMemoryDir } = require('./paths');

/**
 * 命令日志记录器 - 记录每次 evolver 命令执行的详细信息
 */

let currentLogContext = {
  command: '',
  startTime: null,
  outputs: [],
};

/**
 * 初始化命令日志上下文
 */
function initCommandLog(command, args) {
  const fullCommand = `node index.js ${command || 'run'}${args.length > 0 ? ' ' + args.join(' ') : ''}`;
  currentLogContext = {
    command: fullCommand,
    startTime: new Date(),
    outputs: [],
    args: args,
    commandType: command || 'run',
  };
}

/**
 * 添加输出内容到日志上下文
 */
function logOutput(category, content) {
  if (!currentLogContext.startTime) return;
  
  currentLogContext.outputs.push({
    category,
    content,
    timestamp: new Date(),
  });
}

/**
 * 记录选中的 Gene 信息
 */
function logSelectedGene(geneId, geneCategory, geneSummary) {
  logOutput('gene_selection', {
    gene_id: geneId,
    category: geneCategory,
    summary: geneSummary,
  });
}

/**
 * 记录信号信息
 */
function logSignals(signals) {
  if (!signals || signals.length === 0) return;
  logOutput('signals', signals);
}

/**
 * 记录会话内容摘要
 */
function logSessionSummary(summary) {
  logOutput('session_summary', summary);
}

/**
 * 记录执行结果
 */
function logResult(success, details) {
  logOutput('result', {
    success,
    details,
  });
}

/**
 * 记录 Cursor 会话桥接信息
 */
function logCursorBridge(bridgeInfo) {
  if (!bridgeInfo) return;
  logOutput('cursor_bridge', {
    source_file: bridgeInfo.sourceFile,
    bridge_file: bridgeInfo.bridgeFile,
    record_count: bridgeInfo.count,
  });
}

/**
 * 将当前命令日志写入到每日 markdown 文件
 */
function flushCommandLog() {
  if (!currentLogContext.startTime) return;

  try {
    const memoryDir = getMemoryDir();
    const now = new Date();
    const dateStr = now.toISOString().split('T')[0]; // YYYY-MM-DD
    const logFile = path.join(memoryDir, `${dateStr}.md`);

    // 确保目录存在
    fs.mkdirSync(memoryDir, { recursive: true });

    // 检查文件是否存在，如果不存在则创建头部
    let needsHeader = false;
    if (!fs.existsSync(logFile)) {
      needsHeader = true;
    }

    const endTime = new Date();
    const duration = Math.round((endTime - currentLogContext.startTime) / 1000);
    
    // 构建日志内容
    let logContent = '';
    
    if (needsHeader) {
      logContent += `# Evolver 执行日志 - ${dateStr}\n\n`;
      logContent += `> 本文件自动记录 Evolver 每次执行的命令、结果和关键信息\n\n`;
      logContent += `---\n\n`;
    }

    const timeStr = now.toTimeString().split(' ')[0]; // HH:MM:SS
    logContent += `## [${timeStr}] ${currentLogContext.command}\n\n`;
    
    // 执行信息
    logContent += `**执行时间**: ${currentLogContext.startTime.toISOString()}\n`;
    logContent += `**耗时**: ${duration}秒\n\n`;

    // 处理各类输出
    const geneSelection = currentLogContext.outputs.find(o => o.category === 'gene_selection');
    const signals = currentLogContext.outputs.find(o => o.category === 'signals');
    const sessionSummary = currentLogContext.outputs.find(o => o.category === 'session_summary');
    const cursorBridge = currentLogContext.outputs.find(o => o.category === 'cursor_bridge');
    const result = currentLogContext.outputs.find(o => o.category === 'result');

    // Cursor 会话桥接信息
    if (cursorBridge && cursorBridge.content) {
      logContent += `### Cursor 会话桥接\n\n`;
      logContent += `- **源文件**: \`${cursorBridge.content.source_file || 'N/A'}\`\n`;
      logContent += `- **桥接文件**: \`${cursorBridge.content.bridge_file || 'N/A'}\`\n`;
      logContent += `- **记录数**: ${cursorBridge.content.record_count || 0}\n\n`;
    }

    // 信号信息
    if (signals && Array.isArray(signals.content) && signals.content.length > 0) {
      logContent += `### 检测到的信号\n\n`;
      signals.content.forEach(sig => {
        logContent += `- \`${sig}\`\n`;
      });
      logContent += `\n`;
    }

    // Gene 选择
    if (geneSelection && geneSelection.content) {
      logContent += `### 选中的 Gene\n\n`;
      logContent += `- **ID**: \`${geneSelection.content.gene_id || 'N/A'}\`\n`;
      logContent += `- **类别**: ${geneSelection.content.category || 'N/A'}\n`;
      if (geneSelection.content.summary) {
        logContent += `- **摘要**: ${geneSelection.content.summary}\n`;
      }
      logContent += `\n`;
    }

    // 会话摘要
    if (sessionSummary && sessionSummary.content) {
      logContent += `### 会话内容摘要\n\n`;
      if (typeof sessionSummary.content === 'string') {
        logContent += `${sessionSummary.content}\n\n`;
      } else {
        logContent += `\`\`\`json\n${JSON.stringify(sessionSummary.content, null, 2)}\n\`\`\`\n\n`;
      }
    }

    // 执行结果
    if (result && result.content) {
      logContent += `### 执行结果\n\n`;
      logContent += `- **状态**: ${result.content.success ? '✅ 成功' : '❌ 失败'}\n`;
      if (result.content.details) {
        logContent += `- **详情**: ${result.content.details}\n`;
      }
      logContent += `\n`;
    }

    logContent += `---\n\n`;

    // 追加到文件
    fs.appendFileSync(logFile, logContent, 'utf8');
    
    console.log(`[CommandLogger] 日志已记录到: ${logFile}`);
  } catch (error) {
    console.warn('[CommandLogger] 写入日志失败:', error.message || error);
  } finally {
    // 重置上下文
    currentLogContext = {
      command: '',
      startTime: null,
      outputs: [],
    };
  }
}

module.exports = {
  initCommandLog,
  logOutput,
  logSelectedGene,
  logSignals,
  logSessionSummary,
  logResult,
  logCursorBridge,
  flushCommandLog,
};
