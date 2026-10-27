# qwesd READ path — step 3 (part A): bionic bring-up + corrected symbol diff

Date: 2026-10-27 (Europe/Copenhagen)
Kernel under test for this part: `7.3.0-rc6-dodge-gpu1` (no qcomtee; `/dev/tee0` absent) — used
only to validate the userspace closure/link/wiring BEFORE the qtee1 trial boot. No trial boot
has occurred yet. All of this runs OUTSIDE the repo, in `/root/qwesrun` on the phone.

## Faithful bionic environment (off-Android, mainline kernel)

The vendor QWES binaries are bionic AArch64 with `PT_INTERP=/system/bin/linker64`, which is a
symlink into the Android Runtime APEX. To run them on the mainline rootfs we reconstructed the
loader environment from read-only loop mounts of the stock partition images (copies in a scratch
dir; no protected partition touched):

- `system_a.img` (erofs, ro) -> `/mnt/sysimg`; bound at absolute `/system`.
- `vendor_a.img` (erofs, ro) -> `/mnt/venimg`; bound at absolute `/vendor` (gives `/vendor/lib64`).
- Extracted `com.android.runtime.apex` -> `apex_payload.img`; mounted ro at
  `/apex/com.android.runtime` so the bionic core (`libc.so`/`libdl.so`/`libm.so`/`libc++.so`,
  real `linker64`) resolves through the `/system/lib64` -> `/apex/...` symlinks.
- `LD_LIBRARY_PATH=<ours>:<vendor-closure>:/vendor/lib64:/system/lib64` with OUR artifacts first
  so our shim `libminkdescriptor.so` wins over the vendor one.

Result: `qwes_cli` loads and runs (prints full usage; executes `-m list`). The environment is
sound; no Android init/property-service/binder/servicemanager/QMI dependency blocks startup
(both binaries' only Android coupling is `__system_property_get`, which degrades to empty
off-Android; neither `qwesd` nor `qwes_cli` is binder/servicemanager-coupled).

## Corrected, authoritative symbol diff (supersedes step 1's "2-symbol" finding)

Step 1 inspected only the direct imports of `qwesd`/`qwes_cli`. The link closure also pulls in
`libQSEEComAPI.so` (a hard `DT_NEEDED` of both), which binds additional internal symbols from
`libminkdescriptor`. The complete set the whole vendor closure imports from `libminkdescriptor`:

| symbol | imported by | maps to MinkCom? |
|---|---|---|
| `TZCom_getRootEnvObject` | qwesd, qwes_cli | yes — thin forward to `MinkCom_getRootEnvObject` |
| `TZCom_getClientEnvObject` | qwes_cli, libQSEEComAPI | yes — thin forward (root then client env) |
| `TZCom_getFdObject(int fd, Object*)` | **libQSEEComAPI only** | NO equivalent — wraps an existing fd as a callback Object; `MinkCom_getMemoryObject` only *allocates* a new region |
| `TimedRetryForwarder_new(ulong,ulong,Object,Object*)` | **libQSEEComAPI only** | NO equivalent — retry-on-timeout Object forwarder |

So the modern Mink path (`qwesd`/`qwes_cli` reading a license) needs ONLY the two thin forwards.
The two non-trivial symbols are pulled in only through `libQSEEComAPI` (the legacy
`/dev/qseecom`-era transport). Faithful implementations would be MORE than a thin forward, so the
shim provides them as instrumented placeholders to satisfy linking and to detect at runtime
whether the read path ever reaches them:
- `TZCom_getFdObject` — logged stub returning an error.
- `TimedRetryForwarder_new` — logged pass-through (returns the wrapped Object retained, no retry);
  mangled name preserved via an asm label (`_Z23TimedRetryForwarder_newmm6ObjectPS_`).

## Empirical result on gpu1 (the key finding)

`qwes_cli -m list` executed through the translator. Each worker reached:

```
qcomtee_object_root_init: No such file or directory   <- OUR libqcomtee opening /dev/tee0 (ENOENT on gpu1, expected)
Failed supplicant_start
GetClientEnv failed
Unable to get pfm service object
```

Two conclusions:
1. The translator is correctly wired end-to-end: `qwes_cli` -> `libqwes` qapi ->
   our `TZCom_getClientEnvObject` -> `MinkCom_getClientEnvObject` -> `qcomtee_object_root_init`
   (open `/dev/tee0`). The ONLY thing missing on gpu1 is `/dev/tee0`, which the qtee1 chain
   kernel provides.
2. Neither `TZCom_getFdObject` nor `TimedRetryForwarder_new` was ever called (no `[tzcom_shim]`
   log line). The license-read/list path rides the **pure Mink path** (the two thin forwards);
   the legacy `libQSEEComAPI` fd-object path is link-only, never invoked. This empirically
   settles the standing #1 risk (Mink vs `/dev/qseecom`) in our favour for the READ, and shows
   `qwesd` is not even required for the read (`qwes_cli` calls qapi in-process).

## Next (step 3 part B)

`tools/dodge-gate &&` battery preflight, then a reversible `fastboot boot` of the qtee1 chain
image (`boot-chain.img`, modem flag OFF, slot a, standing dodge rules). On the booted qtee1
kernel `/dev/tee0` is present: re-establish the ro image mounts + bionic env, start
`qtee_supplicant` + the read-only FS/RPMB listeners (log every listener request; RPMB refuses
every write; FS forces read-only), then rerun `qwes_cli` check/list and observe whether the
Smart Transmit license reads back through real QTEE. Hard rules unchanged: persist read-only,
no secure-storage write (stop+report if the op needs one), no fake/hard-coded license response,
real modem/EFS/persist never written (hash before/after).
