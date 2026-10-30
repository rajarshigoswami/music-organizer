# Learnings & Architecture Transfer: From Sonix Player to Music Organizer

This document chronicles the research, technical constraints, operational discoveries, and architecture distilled from the `sonix-player` scripts into the standalone cross-platform `music-organizer` application located at `Play/music-organizer`.

---

## 1. Context & Origin

The initial media management workflows in `sonix-player` were scripted in PowerShell:
- [`Organize-MusicForSonix.ps1`](./Organize-MusicForSonix.ps1): Script for organizing raw music folders into HiBy R1 / Sonix OS compatible folder structures.
- [`Create-SonixPlaylists.ps1`](./Create-SonixPlaylists.ps1): Script for indexing organized music and remapping legacy folders into Sonix M3U playlists.
- [`Organize-AudiobooksForSonix.ps1`](./Organize-AudiobooksForSonix.ps1): Script for organizing audiobook folders into the 3-tier author/series hierarchy.
- **Sonix Media Guide**: Internal hardware and firmware specifications for Sonix OS.

While these scripts proved the concept, they were Windows-only, required PowerShell execution policy bypasses, lacked an interactive visual interface, and required manual script edits for different folder inputs.

---

## 2. Key Technical Learnings & Sonix OS Constraints

During the analysis and development of the scripts, several critical firmware and hardware constraints were discovered:

### A. The 64-File Limit (`FOLDERORDER_TAG_READS`)
- **Firmware Rule**: In Sonix OS `folderorder.c`, tag reading per folder is capped at 64 files.
- **Consequence**: Any folder with more than 64 files fails tag reading and falls back to raw alphanumeric filename sorting.
- **Learning Applied**: Never keep large flat collections in a single folder. The organizer automatically sub-divides tracks into dedicated album, soundtrack, or artist subfolders.

### B. Multi-Artist Soundtrack Grouping (`album_key`)
- **Firmware Rule**: In multi-artist film releases (e.g., Bollywood soundtracks, game/anime OSTs), tracks rarely have a unified `album_artist` tag. Sonix OS falls back to hashing the parent directory path as the album key.
- **Consequence**: If multi-artist tracks are sorted strictly by individual singer, a single movie album is fractured into multiple single-track entries across the library.
- **Learning Applied**: The organizer classifies multi-artist albums into `Soundtracks/<Movie Name>/` so Sonix OS hashes the single parent folder into a unified album entry.

### C. Display Clutter Stripping (480x800 Screen)
- **Firmware Rule**: The HiBy R1 screen width is 480px. Long metadata strings cause continuous 3-line marquee text scrolling.
- **Learning Applied**: Strip redundant suffix clutter such as `(Original Motion Picture Soundtrack)`, `[Deluxe Edition]`, `[Bonus Track]`, and `(From "Movie")` from titles and folder names.

### D. Sonix Playlist Architecture & Auto-Import
- **Auto-Import Mechanism**: On card mount or player boot, `migrate_folder_once()` in `playlists.c` scans `<sd_root>/Playlist/*.m3u`.
- **Required Header**: Must contain `#EXTM3U` and `#[Sonix Playlist]`. Without this marker, the firmware ignores the file.
- **Path Resolution**: Sonix OS runs on a Linux kernel. Paths in playlists must use Linux-style forward slashes (`/`) and resolve relative to the `Playlist/` directory (e.g. `../Music/Artists/KK/Pal/03 - Yaaron.flac`).
- **Encoding**: Must be UTF-8 **without BOM**; CRLF or LF line endings are accepted.

### E. Filename Heuristics vs Embedded Tags
- Many real-world music folders have blank or partially corrupted ID3/Vorbis tags.
- In soundtrack and Asian music folders, filenames commonly follow `Track - Title - Artist` (e.g., `01 - Yaaron - KK.mp3`), whereas Western studio releases often follow `Artist - Title` or `Track - Title`.
- **Learning Applied**: The metadata engine inspects embedded tags first, and if blank, runs a smart multi-part split recognizing known artist signatures before assigning fallback values.

---

## 3. Architecture of the New App (`music-organizer`)

The new standalone app was architected to be completely independent, cross-platform, and user-friendly.

### Project Structure
```
Play/music-organizer/
├── main.js                  # Electron desktop main process & native folder dialogs
├── preload.js               # Secure IPC bridge between Electron and UI
├── server.js                # Zero-dependency local HTTP & SSE server for Web mode
├── package.json             # NPM project definitions (Electron + music-metadata)
├── run-gui.bat              # One-click Windows desktop launcher
├── README.md                # Usage and deployment documentation
├── LEARNINGS.md             # This learnings document
├── lib/
│   ├── metadata.js          # Audio tag parser (music-metadata) + smart filename heuristics
│   ├── sonix-format.js      # Sonix OS #[Sonix Playlist] formatter and path sanitizers
│   └── organizer.js         # Core library scanner, layout classifier & playlist builder
└── renderer/
    ├── index.html           # Single-page interface (Configure -> Preview -> Execute)
    ├── css/styles.css       # Dark glassmorphism design system & micro-animations
    └── js/app.js            # State management, preview table, and real-time event logs
```

---

## 4. Work Summary by Individual Domain

| Domain | Prior State (In `sonix-player`) | New Implementation (In `music-organizer`) |
| :--- | :--- | :--- |
| **User Interface** | Terminal PowerShell scripts with hardcoded parameters | Dark glassmorphism GUI with folder pickers, metric cards, preview table, and live log terminal |
| **Platform Compatibility** | Windows-only PowerShell 5.1 / 7 | Cross-platform (Windows, macOS, Linux) via Electron, plus a browser web mode |
| **Folder Remapping** | Separate manual script (`Create-SonixPlaylists.ps1`) | Integrated pipeline: scans source subfolders (e.g. `hindi/`, `english/`) and creates remapped playlists pointing to destination paths |
| **Artist Playlists** | Manual array specification | Dynamic scan: automatically indexes all unique artists and builds `<Artist>.m3u` playlists |
| **Metadata Extraction** | Windows COM Object (`Shell.Application`) | Pure JavaScript `music-metadata` supporting FLAC, MP3, M4A, WAV, OGG, Opus, DSF, DFF |
| **Safety & Validation** | Direct copy without interactive dry run | Interactive Step 2 Preview: view all file mappings, playlist contents, and counts before applying changes |
| **Execution Mode** | Script switch (`-Mode Copy/Move`) | Interactive radio selector with default safe **Copy** mode |

---

## 5. Quick Reference: Running the Standalone App

From `Play/music-organizer`:
- **Desktop Electron App**: Double-click `run-gui.bat` or run `npm start`
- **Web Browser Mode**: Run `npm run web` and open `http://localhost:3000`
