# qwesd READ path — step 3B: on-device license read through real QTEE (2026-10-27)

## What this step proves
On the qtee1 chain (RAM) boot — kernel `7.3.0-rc6-dodge-qtee1+`, `/dev/tee0` present,
`qcomtee: QTEE version 5.2.0`, NO `/dev/qseecom` — the vendor QWES userspace
(`qwes_cli`, bionic) reads and **validates** the already-provisioned Smart-Transmit/QWES
license set through the real QTEE, using our smcinvoke→qcomtee translator:

    qwes_cli  →  our libminkdescriptor.so shim (TZCom_* → MinkCom_*)
              →  libminkadaptor.so  →  libqcomtee  →  /dev/tee0 (qcomtee, QTEE 5.2)
              →  QWES TA (GUID-named, loaded into QTEE memory by UUID)
              →  callbacks serviced by our read-only FS + RPMB listeners
                 (our-built qtee_supplicant)

No `/dev/qseecom`, no smcinvoke, no vendor libminkdescriptor (renamed .vendororig).

## Environment (RAM initramfs, reconstructed by hand)
- sda15 mounted `ro,noload` (staged files); system_a/vendor_a/apex loop-mounted (erofs),
  bound to /system, /vendor, /apex/com.android.runtime; modem_a bound to
  /vendor/firmware_mnt (gives image/ with the GUID TAs).
- LD_LIBRARY_PATH = ours:vendor:/vendor/lib64:/system/lib64 (our shim wins).
- qtee_supplicant dlopens versioned sonames (libfsservice.so.1 / librpmbservice.so.1) —
  created symlinks.

## Listener bring-up
qtee_supplicant came up and registered both services:
- RPMB: probed UFS, found BSG dev, initialised **read-only** (dev=UFS size=32768,
  rel_wr_count=64), registered service 0x2000.
- FS: read-only secure-FS listener (forces opens RO, refuses writes).
Then it blocks in the /dev/tee0 listener-receive loop awaiting QTEE callbacks.

## License read result (described, no identifiers)
- `qwes_cli listfids` → **Success** (EXIT 0): enumerated the installed feature set —
  a group of discrete installed feature IDs plus one contiguous feature-ID range.
- `qwes_cli checkall` → **Success** (EXIT 0): for every installed feature the QWES TA's
  `CheckFeatureEnablement` (= the modem's `IPFM_CheckInstalledLicense`) returned
  **Status 1 = licensed**, 45-byte CBOR response each. This is the exact TA call the
  modem makes during rtsar/Smart-Transmit bring-up.

## Listener I/O during the read (hard-rule compliance)
- RPMB: **31 dispatches, ALL cmd_id=0x102 (read)**. ZERO writes. (The TA cached the
  license DB in QTEE secure RAM after init, so `checkall` needed no fresh storage I/O.)
- FS: only a non-existent read-path miss (`…/persist/data/pfm/licenses/`,
  "Persist partition not mounted") — harmless; license resolved from RPMB.
- **No write / refuse / reject / deny line anywhere in the listener log.**
- **No secure-storage write was needed or attempted. No /dev/qseecom dependency hit.**

## Phone state / integrity
- Trial was a `fastboot boot` of a prebuilt image (nothing flashed); normal reboot returns
  to the flashed gpu1 kernel on boot_a. Modem flag OFF during 3B (MPSS not started).
- All 11 protected partitions (modem_a/b, modemst1/2, fsg, fsc, oplusdycnvbk,
  oplusstanvbk_a/b, qweslicstore_a/b) hash-identical to baseline — nothing written.
  No `persist` partition exists on this device. RPMB accessed read-only only.

## Conclusion
The license reads back and validates through real QTEE via the translator, read-only.
Cleared to attempt step 4 (one modem-ON trial with long-running qwesd; modem asks qwesd
over QMI) under the same hard rules.
