# desKTop

**A digital frame for Tezos art on macOS.**

Enter any wallet address or `.tez` domain. desKTop turns your Mac's screen into a rotating gallery of on-chain art. It renders flat to wallpaper memory, so there are no open browser tabs, no background GPU drain, and no battery hit.

---

### Features

- **Flat-by-Default Architecture**: All generative, SVG, loop, and still artworks are composited headlessly and committed directly into the macOS wallpaper canvas (`NSWorkspace`). Drops to 0.0% CPU between rotations.
- **Zero Keys, Zero Custody**: Read-only ledger queries via TzKT REST API, Objkt GraphQL, and Tezos Domains. No wallet connections, no seed phrases, no signing requests, and no telemetry.
- **Smart Dynamic Galleries**: Save filter criteria or follow any creator's minted oeuvre or collector's holdings with a single click. As new pieces are minted on-chain, they stream into your desktop rotation automatically.
- **Multi-Monitor Hardware Binding**: Screens are keyed to persistent hardware UUIDs (`CGDisplayCreateUUIDFromDisplayID`). Playlists stay assigned to their physical monitors across sleep, wake, and docking.
- **Full Tezos Ecosystem Support**: fxhash (gentk v1, v2, v3 project differentiation), Hic et Nunc / Teia, Versum, Objkt collections, and animated GIF/WebP off-thread frame decoding.
- **Battery & Sleep Guardian**: Automatically pauses rotation timers on sleep to eliminate background battery drain.

---

### Installation

Download the latest universal build for Apple Silicon and Intel:

- **[Download desKTop.zip](https://github.com/skullzarmy/desKTop/releases/latest/download/desKTop.zip)**

Unzip and drag `desKTop.app` to your `/Applications` folder.

**Compatibility**: macOS Tahoe (16.0+), macOS Sequoia (15.0+), macOS Sonoma (14.0+).

---

### Building from Source

#### Prerequisites
- macOS 14.0+
- Xcode or Swift 6.0+ command line tools

#### Build and Test
```bash
# Clone the repository
git clone https://github.com/skullzarmy/desKTop.git
cd desKTop

# Run the test suite (11 test suites)
./scripts/test.sh

# Bundle the application (.app)
./scripts/bundle.sh

# Generate release zip
./scripts/bundle.sh --release --zip
```

The resulting `desKTop.app` bundle will be generated in `build/desKTop.app`.

---

### License

This is free and unencumbered software released into the public domain under [The Unlicense](LICENSE).

---

<< a [FAFO~~lab~~](https://fafolab.xyz) joint >>
