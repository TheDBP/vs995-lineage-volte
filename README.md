# LG V20 (Verizon) — LineageOS 24.0 (Android 17)

Android 17 on a 2016 phone, **with working VoLTE** — which on this device is the difference between
a phone and a tablet that fits in your pocket, because the 2G/3G voice network it shipped with has
been switched off.

For the **LG V20, Verizon** only: `vs995`, Snapdragon 820 (msm8996). LineageOS still carries the
device trees for this phone but nobody builds it on 24.0, so most of this repo is making a 22.2-era
tree work on a 2026 platform, and the rest is getting LG's own 2016 IMS stack to carry calls on it.

**Status:** builds, flashes, runs, makes and receives VoLTE calls with audio both ways. Tested on one
handset. Everything else is LineageOS's own hardware support; only what is listed below is changed.

## Get it

Prebuilt images are on the [Releases](https://github.com/TheDBP/vs995-lineage-volte/releases) page, when
there are any. Each release is the ROM zip plus a matching `-recovery.img`.

| build | what it is |
|---|---|
| `stock` | LineageOS as upstream ships it, plus only what this hardware needs to work: VoLTE, the kernel fixes, the HAL ports. No theming, no extra apps. Flash this if you want the phone working and nothing more, and build against it when reporting a bug. |
| `libre` | the same, plus Nextcloud (Files, Talk, NextPush, DAVx5), K-9 Mail, KDE Connect, TermOne Plus, ConnectBot and OpenVPN, with F-Droid to keep them updated. No Google apps, not rooted. |

No release carries Google apps, or the boot animation, wallpapers and sounds reclaimed from another
phone's firmware; `forge/tools/release.sh` refuses to publish a build with either. Every release does
carry LG's own IMS stack, rebuilt from stock firmware, because that is what VoLTE is on this phone.
It is proprietary manufacturer code and it is the one thing in the image that this repo could not
build from source.

Then: **[FLASHING.md](FLASHING.md)**.

> **Check your model first.** The V20 unlock path differs per carrier variant and this is the Verizon
> one. Do not follow `h918`, `us996` or `h910` guides.

### Three things to know before you flash

- **`/data` is not encrypted, and cannot be.** Not an oversight here. FBE is broken on every LGE
  msm8996 and msm8998 device because LG's KeyMaster trustlet is incompatible with the AOSP
  file-encryption path, and Android 13 removed the older FDE. The LineageOS Directors granted these
  devices an explicit exemption from the charter's encryption requirement. Treat the phone as
  readable by anyone holding it.
- **After a factory reset, VoLTE needs one reboot.** The IMS stack picks its carrier profile from the
  SIM, and on a freshly wiped device the modem publishes the network a few seconds after the stack
  has already started. The choice is saved, so the next boot is correct. Reboot once after setup and
  calls work.

  If the profile picked for your SIM is the wrong one, override it and lock the choice:

  ```sh
  setprop persist.lg.ims.pref_operator TMO     # an operator that ships a profile
  setprop persist.lg.ims.pref_country  US
  setprop persist.lg.ims.pref_locked   true    # stop the automatic choice overwriting it
  ```

  Without the lock the automatic choice is re-applied on the next boot. Leaving the operator empty
  and locked falls back to the profile the handset shipped with.
- **Unlocking requires DirtySanta** and that bootloader leaves a flag the modem reads as "factory
  cable attached", which kills mobile data on *any* ROM including official nightlies. A kernel patch
  here clears it.

## What works, and what does not

What this tree makes work:

- **VoLTE**, outgoing and incoming, two-way audio, on LTE only. LG's stock IMS app rebuilt for
  Android 17 plus a bridge into the modern telephony stack. The carrier profile is chosen from the
  SIM, so it is not tied to Verizon.
- **Mobile data** on a DirtySanta-unlocked handset, per the flag above.
- **Fingerprint**, enrolment and authentication.
- **Boots enforcing**, no permissive domains. The IMS stack runs under real SELinux policy rather
  than the bring-up exemption these ports usually lean on.

What still does not:

- **Encryption.** See above; it is not coming.
- **SMS over IMS.** Texting works over the circuit-switched path, which is what the phone uses
  anyway. Only the IMS path is unfinished: the modem refuses the QMI WMS transport registration.
- **Wi-Fi calling and video calling.** Hidden rather than left to fail. VT needs a media path that
  does not work here; WFC needs an ePDG tunnel that is not ported.
- **RCS**, not from the IMS stack. Google Messages carries RCS over its own backend on plain data, so
  a `full` build gets it.

## What is different from stock LineageOS

Everything below the first line is a default of the `clean`, `libre` and `full` presets. The `stock`
preset takes no options, so it has none of it.

- VoLTE
- Dark theme, themed monochrome icons and a teal accent by default
- Minimal home screen; Google feed (−1 screen) off
- LiveDisplay off, advanced restart in the power menu
- Setup wizard skips the recovery, metrics and backup nags
- 420 dpi and a 1.15× font scale
- Mobile data usable *during* setup, instead of a sign-in page with no way online but Wi-Fi
- CPU governor retune for responsiveness ([below](#responsiveness-tuning))
- `libre` and `full` add apps; `full` adds Google apps

## Build it

```sh
git clone https://github.com/TheDBP/vs995-lineage-volte.git
cd vs995-lineage-volte
mkdir -p 'Stock ROMs' && cp ~/VS9951CA_01_0525_ARB00.kdz 'Stock ROMs/'   # optional, see below
PRESET=clean ./forge/bootstrap.sh
```

Needs Docker and room for a full AOSP checkout plus output. One command builds one image. Output
lands in `build_output/src/out/target/product/vs995/lineage-24.0-*.zip`.

### VoLTE needs LG's firmware, which is not shipped here

The IMS stack is LG's own proprietary app reworked for Android 17, so this repo carries the recipe
and none of the ingredients. Drop LG's stock VS995 KDZ into `Stock ROMs/` (or the repo root) and the
first build does the rest: it unpacks the KDZ, takes what it needs, and rebuilds the stack. Later
builds skip straight past.

Nothing to extract by hand. LG ships firmware as a KDZ holding a DZ holding the partition images,
which nothing in AOSP reads, so the build drives
[kdztools](https://github.com/ehem/kdztools) itself to get the `system` partition out. kdztools is
GPL-3.0 and this tree is Apache-2.0, so it is fetched at build time rather than vendored; set
`KDZTOOLS=` to a local checkout to build without network. An already-unpacked `system.image` is
still accepted if you have one.

Leave it out and the build still works, ships without VoLTE, says so while it runs, and tags itself
`-novolte`. Asking for `volte` explicitly without the firmware stops the build instead of handing you
an image that cannot place a call.

`STOCK_ROM=` and `STOCK_ROM_URL` do **not** feed this. Those belong to the `oem` option, which
reclaims the boot animation, wallpapers and sounds from a *different* phone's stock ROM. The IMS
staging looks for `VS995_Stock_ROM_*.image` in the repo root and nowhere else.

To re-stage after changing anything the IMS build reads, delete
`build_output/src/device/lge/msm8996-common/ims/Ims4-reworked.apk` and build again. A build that
finds that file already there skips staging, so the stock image does not have to be kept around
forever.

Everything the staging produces is gitignored and never committed: the reworked app, LG's IPsec
helper binaries, and the hash that records what they were built from.

What comes out of the firmware is kept in one place: **`stock-blobs-lg-vs995/`**, gitignored, with a
README of its own naming every file and where it came from. LG's IMS app, its 32-bit SIP and QMI
libraries, its IPsec helpers and the stock boot images it needs to deodex all live there and nowhere
else, so it is obvious what is proprietary and easy to delete. Removing that directory makes the next
build pull everything again. Full walkthrough:
**[Building the IMS stack from stock firmware](IMS.md#building-the-ims-stack-from-stock-firmware)**.

### Presets

A preset is just a saved set of options; `device.conf` is authoritative.

| preset | tag | adds over `clean` |
|---|---|---|
| `stock` | `stock` | nothing at all, and unlike the others it takes no common or extra options either. The redistributable baseline, which is why releases are built from it. |
| `clean` | `turbo-clean` | nothing, but it still gets the common options below |
| `libre` | `turbo-libre` | `nextcloud-core`, `k9`, `kdeconnect`, `termoneplus`, `connectbot`, `openvpn`, and `fdroid`, which they all pull in |
| `full` | `turbo` | `gapps` plus everything in `libre` |

Every preset also gets the common options from `device.conf`: dark theme, themed icons, teal accent,
minimal home, LiveDisplay off, advanced restart, setup-wizard nag skip and a container-capable
kernel.

Pick options directly instead with `OPTIONS="gapps fdroid" ./forge/bootstrap.sh`, or add to a preset
for one build with `EXTRA_OPTIONS=`.

`EXTRA_OPTIONS=bringup` gives adb from boot with no authorisation prompt plus persistent logcat,
which is useful when a build does not reach the lock screen. Never hand that image to anyone.

### Options

Every option available on this branch. They live in `forge/options/`, so they work on any device
rather than being wired into this tree. Generated by `forge/tools/gen-option-index.py`; do not edit
by hand.

<!-- options:start device -->

| option | what it does |
|---|---|
| `advanced-restart` | Advanced restart in the power menu. |
| `bringup` | adbd from boot with no authorisation prompt, plus persistent logcat, so a build that never reaches the lock screen can still be traced. **Never hand out an image built with this** — it accepts adb from any host. |
| `connectbot` | ConnectBot: an SSH client with saved hosts, keys and port forwarding. Pulls in `fdroid`. |
| `dark-default` | Default to dark theme. |
| `drm-trace` | Diagnostic: kernel trace of whoever disables a DRM plane or CRTC, for a panel that dies while the framework still thinks it is on. |
| `fdroid` | F-Droid app store + Privileged Extension (silent installs/updates). |
| `firefox` | Firefox (Fennec F-Droid) as the browser, replacing Jelly. Pulls in `fdroid`. Mutually exclusive with `fulguris`. **In no preset**: it overrides Jelly, and stages 320 MB against Fulguris's 9. |
| `fulguris` | Fulguris as the browser, replacing Jelly. Pulls in `fdroid`. A WebView browser, 9 MB where Fennec stages 320 MB. Mutually exclusive with `firefox`. **In no preset**: it overrides Jelly, so a preset carrying it ships the only browser in the image, and its first run asks you to accept terms with nothing else able to open them. |
| `gapps` | Google apps: Play Store and GMS from MindTheGapps, plus Google's versions of the stock apps. |
| `google-feed-off` | Google feed (-1 screen) off by default. |
| `home-defaults` | Home screen defaults: no icon labels, no auto-add. |
| `k9` | K-9 Mail (the Thunderbird for Android codebase) as the mail client. Pulls in `fdroid`. |
| `kdeconnect` | KDE Connect (phone <-> desktop: notifications, clipboard, files, remote input). Pulls in `fdroid`. |
| `linphone` | Linphone: a SIP client, for voice over data where the device has no VoLTE. Pulls in `fdroid`. |
| `linux` | On-device Linux environment (chroot + Docker): container kernel config and cgroup fixes. |
| `livedisplay-off` | LiveDisplay off by default. |
| `minimal-home` | Minimal home screen: hotseat only, no second page. |
| `nav-icons` | Nextbit Robin style nav-bar icons, drawn as scalable tintable vectors. |
| `nextcloud` | Nextcloud bundle: Files, Talk, NextPush, Deck, NC Passwords, Notes, DAVx5, Tasks — the current F-Droid build of each. Pulls in `fdroid`. ~600 MB against `nextcloud-core`'s ~270. Check the partition before adding either. |
| `nextcloud-core` | Nextcloud, the four that make the phone a client: Files, Talk, NextPush, DAVx5 — the current F-Droid build of each. Pulls in `fdroid`. Mutually exclusive with `nextcloud`, which already carries these four. |
| `nfc-off` | NFC off by default. |
| `oem` | The manufacturer's own boot animation, wallpapers and sounds, reclaimed from its stock ROM. Needs that phone's own stock ROM and a pack that understands its layout — see `forge/docs/OEM-ASSETS.md`. |
| `openvpn` | OpenVPN for Android (de.blinkt.openvpn) as a bundled VPN client. Pulls in `fdroid`. |
| `pong-notification` | Pong as the default notification sound (LineageOS default is Argon). |
| `root` | Magisk baked into the boot image, so the zip flashes pre-rooted. Pulls in `termoneplus`. The image flashes pre-rooted, so treat it like one. |
| `setup-mobile-data` | Mobile data usable during setup, instead of a sign-in page with no way online but Wi-Fi. |
| `setupwizard-lineage` | Use Lineage SetupWizard over Google's (WITH_GAPPS). |
| `setupwizard-nag-skip` | Skip recovery/metrics/backup setup pages. |
| `syncthing-fork` | Syncthing-Fork: continuous file sync between your own devices, no server or account. Pulls in `fdroid`. |
| `teal-skin` | Teal accent — fixed #009D94 Monet preset seed. |
| `teal-wallpaper` | Teal-shag default wallpaper (baked into framework-res). |
| `termoneplus` | TermOne Plus terminal emulator (F-Droid build). Pulls in `fdroid`. |
| `themed-icons` | Themed (monochrome) app icons on by default. |
| `volte` | The manufacturer's own IMS stack, rebuilt from its stock firmware, so the phone can place calls over LTE. Turns itself on when the phone's stock firmware is present and off when it is not, marking the build tag `-novolte` — see `forge/options/volte/README.md`. |

<!-- options:end -->
## Under the hood

83 patches across 17 upstream projects, applied at build time from `overlay/patches/`. Nothing is
forked: each patch is a single commit against the upstream tree, replayed every build, one patch per
thing it enables. So upstream stays upstream and every change stays readable.

**VoLTE** is the bulk of it, fifteen patches across `device/lge/msm8996-common` and
`frameworks/opt/telephony`: LG's `Ims4` brought up on Android 17, an `ImsBridge` presenting it to the
modern telephony stack, the IPsec helpers its SIP registration needs, a QMI service rule without
which calls have no audio, the sepolicy to run all of it enforcing, and one real AOSP bug fix (the
compat `ImsService` path crashes the phone process). **[IMS.md](IMS.md)** is the full account,
including the carrier-profile selection and what is still open.

**Making a 22.2-era device tree boot on 24.0** — HIDL manifest entries for interfaces 24.0 deleted,
the IR and LiveDisplay HALs moved to AIDL, lights and fingerprint on the generic Lineage AIDL
services, FCM target level raised, first-stage mount of `/system` from a ramdisk, a tmpfs on
`/metadata`, and the in-kernel low memory killer enabled because this kernel has no PSI for lmkd.

**Kernel** (`kernel/lge/msm8996`) — a 4.4 kernel against a 2026 userspace: `MADV_WIPEONFORK`,
netlink xperms for Android 16+ policy, the `cpuset_v2_mode` mount option, a clang fix, and the
DirtySanta factory-cable flag.

**bpf and connectivity** — the 24.0 bpf loaders assume a 4.14+ kernel and either hang or reboot on
4.9. These let them load what they can and carry on.

**Fingerprint** — the sensor's libhardware module reports API version 2.0, and only
`android.hardware.biometrics.fingerprint@2.0-service` accepts that; despite the name it serves the
current HIDL `@2.1` interface, and the `2.0` is the legacy module version it opens. **FCM target
level 8 drops HIDL fingerprint entirely**, so raising the target level later means writing an AIDL
shim that handles the two APIs' differing `enumerate`.

**Display** — 420 dpi, a 1.15× font scale, the 32dp `status_bar_height` override dropped so the
platform default applies, and an auto-brightness curve.

### Responsiveness tuning

The kernel is LineageOS's msm8996 4.4 (`CONFIG_SCHED_HMP=y`, `interactive`; no WALT, no schedutil),
so tuning is limited to what the `interactive` governor exposes:

| knob | stock | here |
|---|---|---|
| little (cpu0) `go_hispeed_load` | 90 | 85 |
| little `hispeed_freq` | 960000 | 1113600 |
| little `target_loads` | 80 | `80 1113600:85 1401600:90` |
| big (cpu2) `go_hispeed_load` | 90 | 85 |
| big `hispeed_freq` | 1248000 | 1478400 |
| `input_boost_freq` | `0:1324800 2:1324800` | `0:1324800 2:1708800` |
| `input_boost_ms` | 40 | 60 |
| `sched_upmigrate` / `sched_downmigrate` | 95 / 90 | 85 / 75 |

Thermal trip points and core_ctl are left alone: on aged 2016 silicon those low trips do real safety
work. The values read back as set on a running handset; the gain is not measured.

## More

| file | what is in it |
|---|---|
| [IMS.md](IMS.md) | How VoLTE was made to work, and what is still open |
| [FLASHING.md](FLASHING.md) | Step by step flashing |
| `device.conf` | Every knob this build has |

## License

Apache-2.0, see `LICENSE`. The patches under `overlay/patches/` modify Apache-2.0 (AOSP and
LineageOS) code and carry that license.

## Support

This is unpaid work on phones their makers abandoned. If a build saved one from the drawer,
[a donation](https://www.paypal.com/donate/?hosted_button_id=7U8PDZLK7742Q) is greatly appreciated.
