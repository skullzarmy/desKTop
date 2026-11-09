# desKTop

**Native macOS Tezos Art Wallpaper Manager**

[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](http://unlicense.org/)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-lightgrey.svg)](https://apple.com/macos)
[![Tezos](https://img.shields.io/badge/Tezos-Art%20NFTs-2C7DF7.svg)](https://tezos.com)

**desKTop** transforms your Mac desktop into a living, dynamic gallery of your Tezos art collection.

- **Zero Keys, Zero Signatures**: 100% public read-only indexer queries. No wallet connection or seed phrases needed.
- **Tezos Domains & Subdomains**: Enter `alice.tez`, `sub.domain.tez`, or `builder.hack` (auto-expanded to `builder.hack.tez`).
- **Strict Art Filtering**: Automatically filters out fungible tokens, DEX liquidity pools, DeFi positions, and governance tokens.
- **Full Tezos Runtime Ecosystem**: Native support for static images, videos/GIFs, Aleatory (`ALEATORY-001`), Bootloader (`BTLDR`), EditArt parametric pieces, and fxhash.
- **Dual Display Engine**: Still wallpapers via native macOS `NSWorkspace`, plus desktop-level borderless canvas window behind desktop icons.
- **Battery Guardian**: Automatically pauses video and generative WebKit loops on battery or Low Power Mode, falling back to pre-rendered static snapshots.

---

## Architecture & Documentation

Full project specifications and technical roadmap are located in [`docs/PROJECT_REQS_AND_PLAN.md`](../docs/PROJECT_REQS_AND_PLAN.md).

---

## Building from Source

### Prerequisites
- macOS 14.0 Sonoma or later
- Xcode 15.0+ or Swift 5.10+ command line tools

### Build & Run
```bash
# Clone the repository
git clone https://github.com/skullzarmy/desKTop.git
cd desKTop/app

# Build the Swift package
swift build -c release

# Run tests
swift test
```

---

## License

This is free and unencumbered software released into the public domain under [The Unlicense](LICENSE).

---

*a [FAFO~~lab~~](https://fafolab.xyz) joint*
