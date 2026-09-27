# USB Drive Doctor

A tiny, free, open-source menu bar utility for macOS that tells you *why* an
external drive won't mount — and tries a safe, read-only mount for you.
It never erases, formats, or repairs anything. That's not a feature we turned
off. It's not in the codebase at all.

## Before / After

**Before:** an external drive won't show up on your Mac. You open Terminal,
run `diskutil list` — it hangs for minutes. You try `log show` with a
predicate you have to guess at, squint at raw kernel log lines looking for
`hardware connection lost` or `abortGated`, and run `ioreg -p IOUSB -w0 -l`
to figure out what speed the thing even negotiated at. An hour later you
maybe understand what's wrong. Most people give up long before that.

**After:** a menu bar icon that's already telling you something's wrong. Click
it, see which drive is struggling and why, in plain language. One button for
a safe, read-only mount attempt, with a live countdown instead of a frozen
cursor.

## Why this exists

This tool exists because of one very stubborn night with a 2012 Seagate
Backup Plus Desktop 3TB drive that mounted fine on Windows and on a
Raspberry Pi, but refused to show up on a Mac at all.

The Mac's own tools made this nearly impossible to diagnose:

- `diskutil list`, `diskutil info`, and `diskutil mount` would **hang for
  minutes** whenever the flaky drive was attached — not just for that drive,
  but for the whole disk-arbitration subsystem, so Disk Utility itself froze
  on "Loading disks."
- The real signal was buried in the unified system log: repeated
  `hardware connection lost` events, and USB-streams errors
  (`IOUSBHostStream::abortGated`, `aborting requests` on a `stream`) — which
  only happen when a drive is using **UAS (USB Attached SCSI)**, a protocol
  that only exists at USB 3.0 SuperSpeed and above.
- The fix, once we found it: routing the same drive through a **USB 2.0**
  port or hub. USB 2.0 never uses UAS — it always falls back to the older,
  far more forgiving Bulk-Only Transport. The instant the drive was off
  UAS, the disconnects stopped completely, and a patient read-only mount
  succeeded a while later (walking a large drive's full directory tree over
  USB 2.0 just takes real time — that's not a bug, it's physics).

None of that is discoverable from the Finder. All of it is discoverable from
the log, if you know what to grep for. This app just does that grepping for
you, continuously, and puts a status icon in your menu bar instead of a
Terminal window full of scrollback.

## What it does

- **Lists attached external disks** without ever calling `diskutil list` —
  the exact command that hangs when a flaky drive is attached. It reads
  `/dev` directly instead.
- **Shows per-disk info** (size, protocol, SMART status, partition scheme)
  via `diskutil info <device>`, always wrapped in a timeout so a stuck drive
  can't freeze the app.
- **Shows negotiated USB speed** (2.0 High-Speed vs. 3.0 SuperSpeed vs.
  SuperSpeed+) via `ioreg`, and flags when a struggling drive is on
  SuperSpeed — with a plain-language tip to try USB 2.0 instead.
- **Streams the live diagnostic log**, highlighting the exact phrases that
  mean "this drive is failing" (`hardware connection lost`, `abortGated`,
  `aborting`, `transaction error`, `terminateDevice`), so you can watch a
  problem happen instead of reconstructing it after the fact.
- **Menu bar status at a glance**: the icon itself changes between idle, 
  healthy, and struggling, driven by the live log — no need to open anything
  to know something's wrong.
- **One button: "Try mount (read-only)"** per partition, with a visible
  countdown, that reports success, timeout, disconnection, or failure
  clearly instead of leaving you staring at a spinner.

## Permanent safety invariant

**This app is read-only, forever, by construction — not by a setting.**

There are exactly two `diskutil` invocations anywhere in this codebase:
`diskutil info <device>` (inherently read-only) and
`diskutil mount readOnly <device>` (the `readOnly` flag is hardcoded, never
optional, never exposed as a toggle). There is no erase, format, repair,
First Aid, partition, or "repair volume" code path anywhere in this project,
and there never will be. If you're reviewing a PR against this repo and it
adds one, that PR is wrong, full stop — grep for `erase|format|repair` in
`Sources/` as a sanity check; it should always come back empty except for
this README and code comments describing the rule itself.

If you need to actually fix a corrupted filesystem, use Disk Utility's First
Aid, or `fsck_exfat`/`fsck_msdos`/`ntfsfix` directly — deliberately, with
your eyes open, knowing the risk. This tool's whole reason to exist is to be
the thing you reach for *before* that, when you just need to know what's
wrong and see if a plain read-only mount works.

## Requirements

- macOS 13 (Ventura) or later
- Swift toolchain (Xcode Command Line Tools is enough — no Xcode IDE
  required)

## Build & run

```sh
git clone <this repo>
cd USBDriveDoctor
./build_app.sh
open USBDriveDoctor.app
```

`build_app.sh` runs `swift build -c release` and wraps the resulting binary
into a proper `.app` bundle (with `LSUIElement` set, so it lives in the menu
bar only — no Dock icon, no app menu). For iterative development, just
`swift build && swift run` works too, though you'll get a Dock icon that way.

## Project layout

- `Sources/USBDriveDoctor/ProcessRunner.swift` — subprocess helpers. Every
  external command runs with a hard timeout (`ProcessRunner.run`) or as a
  non-blocking stream (`LineStreamer`), so nothing here can freeze the UI.
- `Sources/USBDriveDoctor/DiskService.swift` — the only place that talks to
  `diskutil`/`ioreg`. See the safety invariant above.
- `Sources/USBDriveDoctor/AppModel.swift` — polls disks, streams the log,
  tracks mount attempts, and derives the overall menu bar status.
- `Sources/USBDriveDoctor/MenuBarContentView.swift` — the compact dropdown.
- `Sources/USBDriveDoctor/ContentView.swift` — the full diagnostic window
  (disk details + live log), opened from the menu bar dropdown.

## Contributing

Issues and PRs welcome. The one rule that isn't up for debate is the safety
invariant above — everything else (more filesystems, more log signatures,
better UI) is fair game.

## License

MIT — see `LICENSE`.
