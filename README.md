# Sonix Media & Playlist Organizer

A cross-platform desktop and web application to organize music libraries and generate compatible playlists for the **HiBy R1 / Sonix OS** and standard audio players.

---

## Features

- **Sonix OS Optimizations**:
  - Automatically respects the 64-file per folder limit (`FOLDERORDER_TAG_READS`) by subdividing large collections.
  - Groups multi-artist soundtracks into unified album folders using directory hashing (`album_key`).
  - Cleans display clutter (e.g. `[Deluxe Edition]`, `(Original Motion Picture Soundtrack)`) for 480×800 screens.
  - Automatically generates `#[Sonix Playlist]` compatible `.m3u` playlists (UTF-8 no BOM, relative forward-slash paths).
- **Audiobook Hierarchy Support**: Reorganizes audiobooks into clean `Author/Series/Book` or `Author/Book` 3-tier structures.
- **Cross-Platform UI**: Beautiful glassmorphism interface built with Electron, plus a local browser web mode.
- **Safety First**: Non-destructive preview mode before copying or moving files.

---

## Getting Started

### Prerequisites
- [Node.js](https://nodejs.org/) (v18 or higher recommended)

### Installation
```bash
npm install
```

### Running the Application

- **Desktop (Electron GUI)**:
  ```bash
  npm start
  ```
  *(On Windows, you can also double-click `run-gui.bat`)*

- **Web Browser Mode**:
  ```bash
  npm run web
  ```
  Then open [http://localhost:3000](http://localhost:3000) in your browser.

---

## How to Scan Library on the HiBy R1

1. Safely disconnect or eject the SD card or USB cable from your PC.
2. Power on the HiBy R1.
3. Navigate to: **Settings &rarr; Music &rarr; "Scan music library"**.
4. Playlists in `Playlist/` will be automatically detected and imported into the player's Playlist menu.

---

## License

MIT

