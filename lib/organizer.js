const fs = require('fs');
const path = require('path');
const { isAudioFile, parseTrackMetadata } = require('./metadata');
const {
  sanitizePathSegment,
  cleanAlbumTitle,
  cleanArtistName,
  getPrimaryArtist,
  normalizeString,
  generateM3UContent,
} = require('./sonix-format');

/**
 * Classifies track into Sonix OS hierarchy: Artists, Soundtracks, or Singles
 */
function classifySonixTrack(meta, sourceSubfolder = null, albumCounts = {}) {
  const primaryArtist = getPrimaryArtist(meta.artist, sourceSubfolder);
  const album = meta.album;
  const title = meta.title || '';

  // 1. Is it an explicit Soundtrack / Film OST / Multi-Artist Compilation?
  const isExplicitSoundtrack = 
    (meta.albumArtist && /various\s*artists|soundtrack|ost/i.test(meta.albumArtist)) ||
    (album && /\b(soundtrack|ost|original motion picture soundtrack|motion picture|film)\b/i.test(album)) ||
    (meta.genre && /\b(soundtrack|ost|score)\b/i.test(meta.genre));

  if (isExplicitSoundtrack && album) {
    return {
      category: 'Soundtracks',
      subGroup: cleanAlbumTitle(album) || 'Soundtracks',
      albumFolder: null,
      primaryArtist,
      isSingle: false,
    };
  }

  // 2. Check if part of a multi-track album
  const normAlbum = normalizeString(album || '');
  const normTitle = normalizeString(title);
  const albumKey = normAlbum ? `${primaryArtist}::${normAlbum}` : null;
  const isMultiTrackAlbum = albumKey && (albumCounts[albumKey] || 0) > 1;

  // 3. Is it a Single?
  const isNoAlbum = !album || album.trim() === '' || album.toLowerCase() === 'unknown' || album.toLowerCase() === '(no album tag)';
  const isSingleRelease = !isMultiTrackAlbum && (isNoAlbum || (normAlbum && normAlbum === normTitle));

  if (isSingleRelease) {
    return {
      category: 'Singles',
      subGroup: primaryArtist,
      albumFolder: null,
      isSingle: true,
      primaryArtist,
    };
  }

  // 4. Otherwise it's a Studio Album / EP by this artist
  return {
    category: 'Artists',
    subGroup: primaryArtist,
    albumFolder: cleanAlbumTitle(album) || 'Album',
    isSingle: false,
    primaryArtist,
  };
}

/**
 * Computes destination relative directory and file name
 */
function computeDestinationPaths(meta, layoutMode = 'sonix', sourceSubfolder = null, albumCounts = {}) {
  const trackNumStr = meta.trackNumber ? String(meta.trackNumber).padStart(2, '0') : null;
  const ext = meta.ext || '.mp3';

  if (layoutMode === 'sonix') {
    const classification = classifySonixTrack(meta, sourceSubfolder, albumCounts);
    let relDir = '';
    let fileName = '';

    if (classification.category === 'Artists') {
      relDir = path.join('Artists', sanitizePathSegment(classification.subGroup), sanitizePathSegment(classification.albumFolder || 'Singles'));
      fileName = (trackNumStr && !classification.isSingle) ? `${trackNumStr} - ${meta.title}${ext}` : `${meta.title}${ext}`;
    } else if (classification.category === 'Soundtracks') {
      relDir = path.join('Soundtracks', sanitizePathSegment(classification.subGroup));
      fileName = trackNumStr ? `${trackNumStr} - ${meta.title} - ${meta.artist}${ext}` : `${meta.title} - ${meta.artist}${ext}`;
    } else {
      relDir = path.join('Singles', sanitizePathSegment(classification.subGroup));
      fileName = `${meta.title}${ext}`;
    }

    return {
      relDir,
      fileName,
      category: classification.category,
      primaryArtist: classification.primaryArtist,
    };
  }

  // Standard Layout: <Artist>/<Album>/<01 - Title.ext>
  const primaryArtist = getPrimaryArtist(meta.artist, sourceSubfolder);
  const artistFolder = sanitizePathSegment(primaryArtist || 'Unknown Artist');
  const albumFolder = meta.album ? sanitizePathSegment(cleanAlbumTitle(meta.album)) : 'Singles';
  const relDir = path.join(artistFolder, albumFolder);
  const fileName = trackNumStr ? `${trackNumStr} - ${meta.title}${ext}` : `${meta.title}${ext}`;

  return {
    relDir,
    fileName,
    category: 'Standard',
    primaryArtist,
  };
}

/**
 * Recursively find all audio files in directory
 */
async function findAudioFiles(dir, baseDir = dir) {
  let results = [];
  let entries = [];
  try {
    entries = await fs.promises.readdir(dir, { withFileTypes: true });
  } catch (err) {
    return results;
  }

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const subResults = await findAudioFiles(fullPath, baseDir);
      results = results.concat(subResults);
    } else if (entry.isFile() && isAudioFile(fullPath)) {
      // Determine top-level subfolder relative to source base
      const relToSource = path.relative(baseDir, fullPath);
      const parts = relToSource.split(/[/\\]/);
      const topSubfolder = parts.length > 1 ? parts[0] : null;

      results.push({
        fullPath,
        relToSource,
        topSubfolder,
      });
    }
  }

  return results;
}

/**
 * Scans source directory and builds a preview plan
 */
async function scanAndPlan(options) {
  const {
    sourceDir,
    destinationDir,
    playlistDir,
    layoutMode = 'sonix', // 'sonix' or 'standard'
    createSubfolderPlaylists = true,
    createArtistPlaylists = true,
    isSonixPlaylistFormat = true,
  } = options;

  if (!sourceDir || !fs.existsSync(sourceDir)) {
    throw new Error(`Source directory does not exist: ${sourceDir}`);
  }

  const rawAudioFiles = await findAudioFiles(sourceDir);
  const plannedFiles = [];
  const folderCounts = {};
  const subfoldersFound = new Set();
  const artistsFound = new Set();

  // First Pass: Read metadata & count album tracks for accurate Album vs Single determination
  const parsedItems = [];
  const albumCounts = {};

  for (const item of rawAudioFiles) {
    const meta = await parseTrackMetadata(item.fullPath);
    const primaryArtist = getPrimaryArtist(meta.artist, item.topSubfolder);
    const normAlbum = normalizeString(meta.album || '');
    const albumKey = normAlbum ? `${primaryArtist}::${normAlbum}` : null;

    if (albumKey) {
      albumCounts[albumKey] = (albumCounts[albumKey] || 0) + 1;
    }

    parsedItems.push({ item, meta, primaryArtist, albumKey });
  }

  // Second Pass: Compute destination paths
  for (const p of parsedItems) {
    const dest = computeDestinationPaths(p.meta, layoutMode, p.item.topSubfolder, albumCounts);
    const targetPath = path.join(destinationDir, dest.relDir, dest.fileName);

    if (p.item.topSubfolder) {
      subfoldersFound.add(p.item.topSubfolder);
    }
    if (dest.primaryArtist) {
      artistsFound.add(dest.primaryArtist);
    }

    folderCounts[dest.relDir] = (folderCounts[dest.relDir] || 0) + 1;

    plannedFiles.push({
      sourcePath: p.item.fullPath,
      sourceRel: p.item.relToSource,
      sourceSubfolder: p.item.topSubfolder,
      targetDir: path.join(destinationDir, dest.relDir),
      targetPath,
      targetRel: path.join(dest.relDir, dest.fileName),
      category: dest.category,
      primaryArtist: dest.primaryArtist,
      metadata: p.meta,
    });
  }

  // Plan playlists
  const resolvedPlaylistDir = playlistDir || path.join(destinationDir, 'Playlist');
  const plannedPlaylists = [];
  const plannedPlaylistNames = new Set();

  // 1. Playlists by Source Subfolders (e.g. "Sono Lem", "Wangden Sherpa", "hindi")
  if (createSubfolderPlaylists && subfoldersFound.size > 0) {
    for (const subfolder of Array.from(subfoldersFound).sort()) {
      const tracksInSubfolder = plannedFiles.filter(f => f.sourceSubfolder === subfolder);
      if (tracksInSubfolder.length > 0) {
        // Natural sort tracks so album tracks are 01, 02, 03...
        tracksInSubfolder.sort((a, b) => {
          if (a.targetDir === b.targetDir && a.metadata.trackNumber && b.metadata.trackNumber) {
            return a.metadata.trackNumber - b.metadata.trackNumber;
          }
          return a.targetPath.localeCompare(b.targetPath, undefined, { numeric: true, sensitivity: 'base' });
        });

        const plName = sanitizePathSegment(subfolder);
        const plFileName = `${plName}.m3u`;
        const plFullPath = path.join(resolvedPlaylistDir, plFileName);

        const trackEntries = tracksInSubfolder.map(t => ({
          targetPath: t.targetPath,
          relativePath: path.relative(resolvedPlaylistDir, t.targetPath).replace(/\\/g, '/'),
          artist: t.metadata.artist,
          title: t.metadata.title,
          durationSeconds: t.metadata.durationSeconds,
        }));

        plannedPlaylists.push({
          type: 'source_subfolder',
          name: plName,
          fileName: plFileName,
          fullPath: plFullPath,
          sourceSubfolder: subfolder,
          trackCount: trackEntries.length,
          tracks: trackEntries,
        });

        plannedPlaylistNames.add(plName.toLowerCase());
      }
    }
  }

  // 2. Playlists by Artist (Only for primary artists not already covered by subfolder playlists)
  if (createArtistPlaylists && artistsFound.size > 0) {
    for (const artist of Array.from(artistsFound).sort()) {
      if (!artist || artist === 'Unknown Artist') continue;
      // Do not duplicate or overwrite a playlist already created from a source subfolder
      if (plannedPlaylistNames.has(artist.toLowerCase())) continue;

      const tracksForArtist = plannedFiles.filter(f => (f.primaryArtist || '').toLowerCase() === artist.toLowerCase());
      if (tracksForArtist.length > 0) {
        // Natural sort tracks
        tracksForArtist.sort((a, b) => {
          if (a.targetDir === b.targetDir && a.metadata.trackNumber && b.metadata.trackNumber) {
            return a.metadata.trackNumber - b.metadata.trackNumber;
          }
          return a.targetPath.localeCompare(b.targetPath, undefined, { numeric: true, sensitivity: 'base' });
        });

        const plName = sanitizePathSegment(artist);
        const plFileName = `${plName}.m3u`;
        const plFullPath = path.join(resolvedPlaylistDir, plFileName);

        const trackEntries = tracksForArtist.map(t => ({
          targetPath: t.targetPath,
          relativePath: path.relative(resolvedPlaylistDir, t.targetPath).replace(/\\/g, '/'),
          artist: t.metadata.artist,
          title: t.metadata.title,
          durationSeconds: t.metadata.durationSeconds,
        }));

        plannedPlaylists.push({
          type: 'artist',
          name: plName,
          fileName: plFileName,
          fullPath: plFullPath,
          artist,
          trackCount: trackEntries.length,
          tracks: trackEntries,
        });

        plannedPlaylistNames.add(plName.toLowerCase());
      }
    }
  }

  return {
    sourceDir,
    destinationDir,
    playlistDir: resolvedPlaylistDir,
    layoutMode,
    totalAudioFiles: plannedFiles.length,
    subfoldersFound: Array.from(subfoldersFound),
    artistsFound: Array.from(artistsFound),
    folderCounts,
    plannedFiles,
    plannedPlaylists,
  };
}

/**
 * Executes file organization and playlist writing with real-time progress callbacks
 */
async function executePlan(plan, options = {}, onProgress = () => {}) {
  const { operation = 'copy', isSonixPlaylistFormat = true } = options;
  const isMove = operation === 'move';

  const total = plan.plannedFiles.length;
  let copiedCount = 0;
  let skippedCount = 0;
  let errors = [];

  onProgress({
    status: 'start',
    message: `Starting ${isMove ? 'move' : 'copy'} of ${total} files...`,
    total,
    current: 0,
  });

  // 1. Process Audio Files
  for (let i = 0; i < plan.plannedFiles.length; i++) {
    const file = plan.plannedFiles[i];
    try {
      // Ensure target directory exists
      await fs.promises.mkdir(file.targetDir, { recursive: true });

      if (isMove) {
        await fs.promises.rename(file.sourcePath, file.targetPath);
      } else {
        await fs.promises.copyFile(file.sourcePath, file.targetPath);
      }
      copiedCount++;

      onProgress({
        status: 'file_processed',
        current: i + 1,
        total,
        action: isMove ? 'MOVED' : 'COPIED',
        fileName: file.metadata.fileName,
        targetRel: file.targetRel,
        message: `${isMove ? 'Moved' : 'Copied'} ${file.metadata.fileName}`,
      });
    } catch (err) {
      errors.push({ file: file.sourcePath, error: err.message });
      onProgress({
        status: 'file_error',
        current: i + 1,
        total,
        fileName: file.metadata.fileName,
        error: err.message,
        message: `Error copying ${file.metadata.fileName}: ${err.message}`,
      });
    }
  }

  // 2. Generate Playlists
  let playlistsCreated = 0;
  if (plan.plannedPlaylists && plan.plannedPlaylists.length > 0) {
    await fs.promises.mkdir(plan.playlistDir, { recursive: true });

    for (const pl of plan.plannedPlaylists) {
      try {
        const m3uContent = generateM3UContent(pl.tracks, { isSonixFormat: isSonixPlaylistFormat });
        // Write UTF-8 without BOM
        await fs.promises.writeFile(pl.fullPath, m3uContent, { encoding: 'utf8' });
        playlistsCreated++;

        onProgress({
          status: 'playlist_created',
          playlistName: pl.name,
          fileName: pl.fileName,
          trackCount: pl.trackCount,
          message: `Created playlist: ${pl.fileName} (${pl.trackCount} tracks)`,
        });
      } catch (err) {
        errors.push({ playlist: pl.name, error: err.message });
      }
    }
  }

  const summary = {
    totalFiles: total,
    processedCount: copiedCount,
    playlistsCreated,
    operation,
    errors,
    success: errors.length === 0,
  };

  onProgress({
    status: 'complete',
    summary,
    message: `Completed! Processed ${copiedCount}/${total} files. Created ${playlistsCreated} playlists.`,
  });

  return summary;
}

module.exports = {
  computeDestinationPaths,
  scanAndPlan,
  executePlan,
};
