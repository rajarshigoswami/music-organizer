const path = require('path');
const mm = require('music-metadata');
const { cleanArtistName, cleanAlbumTitle, sanitizePathSegment } = require('./sonix-format');

const AUDIO_EXTENSIONS = new Set([
  '.mp3', '.flac', '.m4a', '.wav', '.opus', '.ogg', '.aac', '.wma', '.aiff', '.ape', '.dsf', '.dff'
]);

function isAudioFile(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return AUDIO_EXTENSIONS.has(ext);
}

/**
 * Parses track metadata from file, falling back gracefully to filename clues.
 */
async function parseTrackMetadata(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  const baseName = path.basename(filePath, ext);

  let rawTitle = null;
  let rawArtist = null;
  let rawAlbum = null;
  let rawTrackNo = null;
  let duration = 0;

  try {
    const meta = await mm.parseFile(filePath, { skipCovers: true, duration: true });
    if (meta.common) {
      rawTitle = meta.common.title;
      rawArtist = meta.common.artist || meta.common.albumartist;
      rawAlbum = meta.common.album;
      if (meta.common.track && typeof meta.common.track.no === 'number') {
        rawTrackNo = meta.common.track.no;
      }
    }
    if (meta.format && typeof meta.format.duration === 'number') {
      duration = meta.format.duration;
    }
  } catch (err) {
    // If metadata reading fails, we gracefully continue with filename parsing
  }

  // Parse filename heuristics if track or title missing
  let fallbackTitle = baseName;
  let fallbackTrackNo = null;
  let fallbackArtist = null;

  // Pattern: "01 - Title - Artist" or "01 - Title"
  const trackNumMatch = baseName.match(/^(\d{1,3})\s*[-_.]\s*(.+)$/);
  if (trackNumMatch) {
    fallbackTrackNo = parseInt(trackNumMatch[1], 10);
    fallbackTitle = trackNumMatch[2].trim();
  }

  // Handle multi-part separator: e.g. "Title - Artist" vs "Artist - Title"
  if (!rawArtist && fallbackTitle.includes(' - ')) {
    const parts = fallbackTitle.split(/\s+-\s+/);
    if (parts.length >= 2) {
      const p1 = parts[0].trim();
      const p2 = parts[parts.length - 1].trim();

      // Check against known artists catalog or common singer hints
      const p1Lower = p1.toLowerCase();
      const p2Lower = p2.toLowerCase();
      const isKnownP1 = ['linkin park', 'lucky ali', 'kk', 'adnan sami', 'rabbi', 'abhijeet', 'arijit singh', 'atif aslam', 'shreya ghoshal', 'sonu nigam'].some(a => p1Lower.includes(a));
      const isKnownP2 = ['linkin park', 'lucky ali', 'kk', 'adnan sami', 'rabbi', 'abhijeet', 'arijit singh', 'atif aslam', 'shreya ghoshal', 'sonu nigam'].some(a => p2Lower.includes(a));

      if (isKnownP1) {
        fallbackArtist = p1;
        fallbackTitle = parts.slice(1).join(' - ').trim();
      } else if (isKnownP2) {
        fallbackArtist = p2;
        fallbackTitle = parts.slice(0, parts.length - 1).join(' - ').trim();
      } else {
        // Default convention in "01 - Something - SomethingElse":
        // If track number was present, "01 - Title - Artist" is the most common format in soundtrack folders
        if (fallbackTrackNo) {
          fallbackArtist = p2;
          fallbackTitle = parts.slice(0, parts.length - 1).join(' - ').trim();
        } else {
          fallbackArtist = p1;
          fallbackTitle = parts.slice(1).join(' - ').trim();
        }
      }
    }
  }

  const title = sanitizePathSegment(rawTitle || fallbackTitle || baseName);
  const artist = cleanArtistName(rawArtist || fallbackArtist || 'Unknown Artist');
  const album = cleanAlbumTitle(rawAlbum || '');
  const trackNumber = rawTrackNo || fallbackTrackNo || null;

  return {
    filePath,
    fileName: path.basename(filePath),
    ext,
    title,
    artist,
    album,
    trackNumber,
    durationSeconds: duration,
  };
}

module.exports = {
  AUDIO_EXTENSIONS,
  isAudioFile,
  parseTrackMetadata,
};
