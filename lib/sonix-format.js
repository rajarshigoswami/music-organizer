const path = require('path');
const fs = require('fs');

/**
 * Sanitizes a string for file/folder naming on FAT32/exFAT/NTFS.
 */
function sanitizePathSegment(name) {
  if (!name || typeof name !== 'string') return 'Unknown';
  let clean = name.replace(/[\\/:*?"<>|]/g, '_');
  clean = clean.replace(/\s+/g, ' ').trim();
  return clean || 'Unknown';
}

/**
 * Cleans album title for HiBy R1 / Sonix display (strips long suffix clutter).
 */
function cleanAlbumTitle(album) {
  if (!album || typeof album !== 'string') return null;
  let a = album.trim();
  a = a.replace(/\s*[([][Oo]riginal [Mm]otion [Pp]icture [Ss]oundtrack[)\]]/gi, '');
  a = a.replace(/\s*[([][Dd]eluxe [Ee]dition[)\]]/gi, '');
  a = a.replace(/\s*[([][Bb]onus [Ee]dition[)\]]/gi, '');
  a = a.replace(/\s*[([][Bb]onus [Tt]rack[)\]]/gi, '');
  a = a.replace(/\s*[([][Ff]rom "[^"]+"[)\]]/gi, '');
  a = a.replace(/\s*[([][Ff]rom [^()]+[)\]]/gi, '');
  a = a.replace(/\s+/g, ' ').trim();
  return sanitizePathSegment(a);
}

/**
 * Cleans artist name (handles multi-artist separators).
 */
function cleanArtistName(artist) {
  if (!artist || typeof artist !== 'string') return 'Unknown Artist';
  // Common Vorbis or ID3 separators: ';' or '/'
  let first = artist.split(/[;/]/)[0].trim();
  first = first.replace(/\s+/g, ' ').trim();
  return sanitizePathSegment(first) || 'Unknown Artist';
}

/**
 * Extracts primary artist name, taking source folder hint into account if available.
 */
function getPrimaryArtist(artist, sourceFolderHint = null) {
  if (!artist || typeof artist !== 'string') {
    return sourceFolderHint ? sanitizePathSegment(sourceFolderHint) : 'Unknown Artist';
  }

  // If sourceFolderHint matches part of the artist string, that's our artist!
  if (sourceFolderHint) {
    const hintClean = sourceFolderHint.trim().toLowerCase();
    if (artist.toLowerCase().includes(hintClean)) {
      return sanitizePathSegment(sourceFolderHint.trim());
    }
  }

  // Split by common multi-artist separators: ;, /, ,, feat., ft., &, with, x
  const splitMatch = artist.split(/\s*(?:[;/]|,\s*(?![^()]*\))|\bfeat\.?\b|\bft\.?\b|\bwith\b|\bx\b|&)\s*/i);
  if (splitMatch && splitMatch.length > 0 && splitMatch[0].trim().length > 0) {
    return sanitizePathSegment(splitMatch[0].trim());
  }

  return cleanArtistName(artist);
}

/**
 * Normalizes string for fuzzy/matching comparisons.
 */
function normalizeString(str) {
  if (!str || typeof str !== 'string') return '';
  let s = str.replace(/\s*[([][Oo]riginal [Mm]otion [Pp]icture [Ss]oundtrack[)\]]/gi, '');
  s = s.replace(/\s*[([][Dd]eluxe [Ee]dition[)\]]/gi, '');
  s = s.replace(/\s*[([][Bb]onus [Ee]dition[)\]]/gi, '');
  s = s.replace(/[\\/:*?"<>|_\-()[\]]/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  return s.toLowerCase();
}

/**
 * Generates Sonix OS compatible M3U content.
 * 
 * @param {Array} tracks Array of { relativePath, title, artist, durationSeconds }
 * @param {Object} options { isSonixFormat: true }
 * @returns {string} M3U text formatted with UTF-8 no BOM & LF
 */
function generateM3UContent(tracks, options = {}) {
  const isSonix = options.isSonixFormat !== false;
  const lines = ['#EXTM3U'];

  if (isSonix) {
    lines.push('#[Sonix Playlist]');
  }

  for (const track of tracks) {
    const dur = Math.round(track.durationSeconds || -1);
    const artist = track.artist || 'Unknown Artist';
    const title = track.title || 'Unknown Title';
    lines.push(`#EXTINF:${dur},${artist} - ${title}`);

    // Ensure forward slashes for Linux/Sonix OS compatibility
    const forwardPath = (track.relativePath || '').replace(/\\/g, '/');
    lines.push(forwardPath);
  }

  // UTF-8 no BOM, ending with newline
  return lines.join('\n') + '\n';
}

module.exports = {
  sanitizePathSegment,
  cleanAlbumTitle,
  cleanArtistName,
  getPrimaryArtist,
  normalizeString,
  generateM3UContent,
};
