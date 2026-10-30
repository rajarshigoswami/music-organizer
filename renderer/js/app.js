// State management
let currentPlan = null;
let currentLayout = 'sonix';
let isRunning = false;

// Determine environment: Electron vs Web
const isElectron = typeof window.api !== 'undefined' && window.api.isElectron;

document.addEventListener('DOMContentLoaded', () => {
  const platformText = document.getElementById('platformText');
  if (isElectron) {
    platformText.textContent = 'Electron Desktop';
    // Register progress listener from Electron IPC
    window.api.onProgress(handleProgressEvent);
  } else {
    platformText.textContent = 'Web Browser Mode';
    // Register progress listener from SSE
    setupSSE();
  }
});

// Setup Server-Sent Events for Web mode
function setupSSE() {
  try {
    const evtSource = new EventSource('/api/events');
    evtSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        handleProgressEvent(data);
      } catch (e) {
        // Heartbeat or empty ping
      }
    };
  } catch (err) {
    console.warn('SSE not available:', err);
  }
}

// Navigation Tabs
function switchTab(step) {
  for (let i = 1; i <= 3; i++) {
    const btn = document.getElementById(`tabBtn${i}`);
    const pane = document.getElementById(`pane${i}`);
    if (btn && pane) {
      if (i === step) {
        btn.classList.add('active');
        pane.classList.add('active');
      } else {
        btn.classList.remove('active');
        pane.classList.remove('active');
      }
    }
  }
}

// Layout Selection
function selectLayout(mode) {
  currentLayout = mode;
  document.getElementById('optSonix').classList.toggle('selected', mode === 'sonix');
  document.getElementById('optStandard').classList.toggle('selected', mode === 'standard');
}

// Folder Picker
async function browseFolder(targetInputId) {
  const input = document.getElementById(targetInputId);
  const currentVal = input.value.trim();

  if (isElectron) {
    const selected = await window.api.selectFolder(currentVal);
    if (selected) {
      input.value = selected;
      // Auto-suggest destination / playlist folder if empty
      autoSuggestFolders(targetInputId, selected);
    }
  } else {
    // In web mode, prompt or user can type path directly
    const manualPath = prompt('Enter directory path:', currentVal || 'E:\\music');
    if (manualPath) {
      input.value = manualPath;
      autoSuggestFolders(targetInputId, manualPath);
    }
  }
}

function autoSuggestFolders(changedInputId, val) {
  if (changedInputId === 'sourceDir') {
    const destInput = document.getElementById('destDir');
    if (!destInput.value) {
      // Suggest destination
      if (val.includes('\\')) {
        const parts = val.split('\\');
        parts[parts.length - 1] = parts[parts.length - 1] + '_Organized';
        destInput.value = parts.join('\\');
      } else if (val.includes('/')) {
        const parts = val.split('/');
        parts[parts.length - 1] = parts[parts.length - 1] + '_Organized';
        destInput.value = parts.join('/');
      }
    }
  }
}

// Get user configured options
function getOptions() {
  const sourceDir = document.getElementById('sourceDir').value.trim();
  const destinationDir = document.getElementById('destDir').value.trim();
  const playlistDir = document.getElementById('playlistDir').value.trim() || null;
  const createSubfolderPlaylists = document.getElementById('chkSubfolderPlaylists').checked;
  const createArtistPlaylists = document.getElementById('chkArtistPlaylists').checked;
  const isSonixPlaylistFormat = document.getElementById('chkSonixFormat').checked;
  const opRadios = document.getElementsByName('operationMode');
  let operation = 'copy';
  for (const r of opRadios) {
    if (r.checked) operation = r.value;
  }

  return {
    sourceDir,
    destinationDir,
    playlistDir,
    layoutMode: currentLayout,
    createSubfolderPlaylists,
    createArtistPlaylists,
    isSonixPlaylistFormat,
    operation,
  };
}

// Step 1 -> Step 2: Scan & Preview
async function startScan() {
  const options = getOptions();

  if (!options.sourceDir) {
    alert('Please specify a Source Folder.');
    return;
  }
  if (!options.destinationDir) {
    alert('Please specify a Destination Folder.');
    return;
  }

  const scanBtn = document.getElementById('scanBtn');
  scanBtn.disabled = true;
  scanBtn.innerHTML = `Scanning directory...`;

  try {
    let result;
    if (isElectron) {
      result = await window.api.scanFolder(options);
    } else {
      const response = await fetch('/api/scan', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(options),
      });
      result = await response.json();
    }

    if (!result.success) {
      alert(`Scan failed: ${result.error}`);
      return;
    }

    currentPlan = result.plan;
    renderPreview(currentPlan);
    switchTab(2);
  } catch (err) {
    alert(`Error scanning directory: ${err.message}`);
  } finally {
    scanBtn.disabled = false;
    scanBtn.innerHTML = `
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="11" cy="11" r="8"></circle>
        <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
      </svg>
      Scan &amp; Preview Library
    `;
  }
}

// Render Preview metrics, chips, and table
function renderPreview(plan) {
  document.getElementById('statFiles').textContent = plan.totalAudioFiles;
  document.getElementById('statArtists').textContent = plan.artistsFound.length;
  document.getElementById('statSubfolders').textContent = plan.subfoldersFound.length;
  document.getElementById('statPlaylists').textContent = plan.plannedPlaylists.length;

  // Render Playlists
  const chipsContainer = document.getElementById('playlistChipsContainer');
  chipsContainer.innerHTML = '';

  if (plan.plannedPlaylists.length === 0) {
    chipsContainer.innerHTML = '<span style="color: var(--text-dim); font-size: 0.85rem;">No playlists selected.</span>';
  } else {
    for (const pl of plan.plannedPlaylists) {
      const chip = document.createElement('div');
      chip.className = 'playlist-chip';
      const typeLabel = pl.type === 'source_subfolder' ? 'Folder' : 'Artist';
      chip.innerHTML = `
        <span><strong>[${typeLabel}]</strong> ${escapeHtml(pl.name)}.m3u</span>
        <span class="count">${pl.trackCount} tracks</span>
      `;
      chipsContainer.appendChild(chip);
    }
  }

  // Render Table
  renderTableRows(plan.plannedFiles);
}

function renderTableRows(files) {
  const tbody = document.getElementById('previewTableBody');
  tbody.innerHTML = '';

  if (!files || files.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--text-dim); padding: 2rem;">No audio tracks found in source folder.</td></tr>';
    return;
  }

  // Render up to 500 rows for smooth UI performance
  const displayFiles = files.slice(0, 500);

  for (const file of displayFiles) {
    const tr = document.createElement('tr');
    const catClass = `tag-${(file.category || 'standard').toLowerCase()}`;
    const subfolderDisp = file.sourceSubfolder ? `<code style="color: #38bdf8;">${escapeHtml(file.sourceSubfolder)}</code>` : '<span style="color: var(--text-dim);">(root)</span>';

    tr.innerHTML = `
      <td>${subfolderDisp}</td>
      <td><strong>${escapeHtml(file.metadata.title)}</strong></td>
      <td>${escapeHtml(file.metadata.artist)}</td>
      <td><span class="tag-badge ${catClass}">${file.category}</span></td>
      <td><span style="font-family: monospace; font-size: 0.77rem; color: #a5b4fc;">${escapeHtml(file.targetRel)}</span></td>
    `;
    tbody.appendChild(tr);
  }

  if (files.length > 500) {
    const trMore = document.createElement('tr');
    trMore.innerHTML = `<td colspan="5" style="text-align: center; color: var(--text-muted); padding: 1rem;">... and ${files.length - 500} more tracks.</td>`;
    tbody.appendChild(trMore);
  }
}

function filterPreviewTable() {
  if (!currentPlan) return;
  const query = document.getElementById('tableFilterInput').value.toLowerCase().trim();
  if (!query) {
    renderTableRows(currentPlan.plannedFiles);
    return;
  }

  const filtered = currentPlan.plannedFiles.filter(f => {
    return (
      (f.metadata.title && f.metadata.title.toLowerCase().includes(query)) ||
      (f.metadata.artist && f.metadata.artist.toLowerCase().includes(query)) ||
      (f.sourceSubfolder && f.sourceSubfolder.toLowerCase().includes(query)) ||
      (f.targetRel && f.targetRel.toLowerCase().includes(query))
    );
  });

  renderTableRows(filtered);
}

// Step 2 -> Step 3: Execute
async function startExecution() {
  if (!currentPlan || currentPlan.plannedFiles.length === 0) {
    alert('No planned files to organize.');
    return;
  }

  const options = getOptions();
  switchTab(3);

  // Reset UI
  document.getElementById('progressBarFill').style.width = '0%';
  document.getElementById('progressPercent').textContent = '0%';
  document.getElementById('progressCount').textContent = `0 / ${currentPlan.totalAudioFiles} tracks`;
  document.getElementById('progressStatusText').textContent = `Starting ${options.operation === 'move' ? 'Move' : 'Copy'}...`;
  document.getElementById('terminalLog').innerHTML = '';
  document.getElementById('completionBanner').classList.remove('show');

  isRunning = true;
  appendLog('INFO', `Initializing organization of ${currentPlan.totalAudioFiles} tracks to '${currentPlan.destinationDir}'`);

  try {
    let result;
    if (isElectron) {
      result = await window.api.executePlan(currentPlan, options);
    } else {
      const response = await fetch('/api/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ plan: currentPlan, options }),
      });
      result = await response.json();
    }

    if (!result.success) {
      appendLog('ERROR', `Execution stopped with error: ${result.error}`);
    }
  } catch (err) {
    appendLog('ERROR', `Execution error: ${err.message}`);
  } finally {
    isRunning = false;
  }
}

// Real-time progress handler
function handleProgressEvent(data) {
  if (!data) return;

  const bar = document.getElementById('progressBarFill');
  const countSpan = document.getElementById('progressCount');
  const percentSpan = document.getElementById('progressPercent');
  const statusText = document.getElementById('progressStatusText');
  const subtext = document.getElementById('progressSubtext');

  if (data.status === 'file_processed') {
    const percent = Math.round((data.current / data.total) * 100);
    bar.style.width = `${percent}%`;
    percentSpan.textContent = `${percent}%`;
    countSpan.textContent = `${data.current} / ${data.total} tracks`;
    statusText.textContent = `Processing Track ${data.current} of ${data.total}...`;
    subtext.textContent = `${data.fileName} -> ${data.targetRel}`;

    appendLog(data.action, `${data.fileName} -> ${data.targetRel}`);
  } else if (data.status === 'playlist_created') {
    appendLog('PLAYLIST', `Saved playlist: ${data.fileName} (${data.trackCount} tracks)`);
  } else if (data.status === 'file_error') {
    appendLog('ERROR', data.message);
  } else if (data.status === 'complete') {
    bar.style.width = '100%';
    percentSpan.textContent = '100%';
    statusText.textContent = 'Organization Completed!';
    subtext.textContent = 'All files organized and playlists written.';

    const banner = document.getElementById('completionBanner');
    const summaryText = document.getElementById('completionSummaryText');
    summaryText.textContent = `Successfully processed ${data.summary.processedCount} audio tracks into '${currentPlan.destinationDir}' and created ${data.summary.playlistsCreated} playlists ready for playback!`;
    banner.classList.add('show');
  }
}

function appendLog(badgeType, message) {
  const terminal = document.getElementById('terminalLog');
  const line = document.createElement('div');
  line.className = 'log-line';
  const time = new Date().toLocaleTimeString();

  line.innerHTML = `
    <span style="color: var(--text-dim);">${time}</span>
    <span class="log-badge log-${badgeType}">${badgeType}</span>
    <span>${escapeHtml(message)}</span>
  `;
  terminal.appendChild(line);
  terminal.scrollTop = terminal.scrollHeight;
}

function openTargetFolder() {
  if (currentPlan && currentPlan.destinationDir) {
    if (isElectron) {
      window.api.openPath(currentPlan.destinationDir);
    } else {
      alert(`Destination Folder: ${currentPlan.destinationDir}`);
    }
  }
}

function openPlaylistFolder() {
  if (currentPlan && currentPlan.playlistDir) {
    if (isElectron) {
      window.api.openPath(currentPlan.playlistDir);
    } else {
      alert(`Playlist Folder: ${currentPlan.playlistDir}`);
    }
  }
}

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
