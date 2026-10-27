# Phase A2 step 2 — translator stack built (smcinvoke→qcomtee)

Date: 2026-10-27. Branch: oneplus13-dodge. Follows step 0 (route) and step 1
(ABI map / symbol diff). This note records the build; the binaries themselves
live **outside the repo** (build tree on the workstation + the phone), per the
brief. No vendor blobs, firmware, TAs, .pfm or identifiers are committed — only
the open-source build recipe, our source patches as text, and verification.

## What was built (all bionic aarch64, ANDROID_PLATFORM=android-34, NDK r27c)

Upstream open sources, unmodified except the two read-only patches below:
- **quic-teec** → `libqcomtee.a` (+ headers). The upstream qcomtee userspace that
  talks to `/dev/tee0` via `TEE_IOC_OBJECT_INVOKE` / `TEE_IOC_SUPPL_RECV|SEND`.
- **minkipc** → `libminkadaptor.so` (the Mink `Object` API over libqcomtee,
  exporting `MinkCom_getRootEnvObject` / `MinkCom_getClientEnvObject` / …),
  `qtee_supplicant`, `libfsservice.so` (FS listener), `librpmbservice.so`
  (RPMB listener). libqcomtee.a and QCBOR are statically linked into
  libminkadaptor (confirmed: `qcomtee_object_invoke` present, no external
  qcomtee/qcbor NEEDED).

Our own shim (≈60 lines), built against minkipc's public headers:
- **libminkdescriptor.so** — SONAME `libminkdescriptor.so`, a drop-in for the
  vendor library of the same name. Exports ONLY the two symbols the vendor
  `qwesd`/`qwes_cli` import (see step-1 symbol diff) and forwards them to
  libminkadaptor. All later QTEE calls ride the returned `Object`'s vtable
  (`Object_invoke` is `static inline`, so it needs no interposition — confirmed:
  `Object_release` was inlined, not an undefined symbol).

```c
/* libminkdescriptor.so shim */
int TZCom_getRootEnvObject(Object *obj)
{
	return MinkCom_getRootEnvObject(obj);
}
int TZCom_getClientEnvObject(Object *clientEnvObj)
{
	Object root = Object_NULL;
	int ret = MinkCom_getRootEnvObject(&root);
	if (ret)
		return ret;
	ret = MinkCom_getClientEnvObject(root, clientEnvObj);
	Object_release(root);
	return ret;
}
```

## Build recipe (reproducible, outside the repo)

- Toolchain: NDK r27c `build/cmake/android.toolchain.cmake`, `ANDROID_ABI=arm64-v8a`,
  `ANDROID_PLATFORM=android-34`.
- QCBOR built static first, installed to a staging prefix `$STAGE`.
- quic-teec: `-DQCBOR_DIR_HINT=$STAGE -DBUILD_UNITTEST=OFF`, installed to `$STAGE`.
- minkipc: `-DQCBOR_DIR_HINT=$STAGE -DQCOMTEE_DIR_HINT=$STAGE`,
  `-DBUILD_PKCS11=OFF` (optee submodules intentionally not cloned),
  `-DBUILD_MINKTEEC=OFF -DBUILD_TIME_LISTENER=OFF -DBUILD_TA_AUTOLOAD_LISTENER=OFF`
  `-DBUILD_GPFS_LISTENER=OFF -DBUILD_FS_LISTENER=ON -DBUILD_RPMB_LISTENER=ON`
  `-DBUILD_RPMB_CLIENT=OFF`.
- Two build-only tweaks, non-semantic:
  1. The NDK toolchain sets `CMAKE_FIND_ROOT_PATH_MODE_*=ONLY`, so the `*_DIR_HINT`
     outside the sysroot is ignored. Passed `-DCMAKE_FIND_ROOT_PATH=$STAGE` and
     `-DCMAKE_FIND_ROOT_PATH_MODE_{INCLUDE,LIBRARY,PACKAGE}=BOTH` so QCBOR/QCOMTEE
     are found.
  2. minkipc's top CMake forces `-Werror`; the `TEE_IOC_SUPPL_RECV` ioctl constant
     has bit 31 set and trips `-Wswitch` (harmless signedness widening). Relaxed to
     `-Wno-error=switch`. No source semantics changed.

## Read-only hard-rule patches (committed here as text)

### RPMB listener — refuse every write, never touch the device
`listeners/librpmbservice/rpmb_service.c`, `rpmb_handle_write()`: logs the request
(cmd_id + sector count + bytes) and returns an error status; the call to
`rpmb_write()` is removed entirely.

```diff
@@ -114,25 +114,21 @@
 
 static int rpmb_handle_write(void *req, void *rsp)
 {
+	/* READ-ONLY HARD RULE (dodge qwes xlat): this listener never performs an
+	 * RPMB write. Log the request (cmd_id + sector count + bytes) and refuse
+	 * with an error status; never call rpmb_write() or touch the device. */
 	tz_rpmb_rw_req_t *rw_req = (tz_rpmb_rw_req_t *)req;
 	tz_rpmb_rw_res_t *rw_rsp = (tz_rpmb_rw_res_t *)rsp;
-	void *rpmb_req = (uint8_t *)req + rw_req->req_buff_offset;
-	void *rpmb_resp = (uint8_t *)rsp + sizeof(*rw_rsp);
-	uint32_t resp_len = 0;
 
-	RPMB_LOG_INFO("RPMB write: %u sectors\n", rw_req->num_sectors);
+	RPMB_LOG_ERROR("RPMB WRITE REFUSED (read-only): cmd_id=%u num_sectors=%u req_bytes=%u\n",
+		       rw_req->cmd_id, rw_req->num_sectors,
+		       rw_req->num_sectors * 512u);
 
-	rw_rsp->status = rpmb_write(rpmb_req, rw_req->num_sectors,
-				    rpmb_resp, &resp_len,
-				    rw_req->rel_wr_count);
-	rw_rsp->res_buff_len = resp_len;
+	rw_rsp->status = -1;
+	rw_rsp->res_buff_len = 0;
 	rw_rsp->res_buff_offset = sizeof(*rw_rsp);
 	rw_rsp->cmd_id = rw_req->cmd_id;
 	rw_rsp->version = rw_req->version;
-
-	if (rw_rsp->status != 0)
-		RPMB_LOG_ERROR("RPMB write failed: status=%d\n",
-			       rw_rsp->status);
 	return 0;
 }
```

### FS listener — serve reads only, refuse every mutation
`listeners/libfsservice/fs/fs.c`: interpose the mutating libc calls used in this
translation unit. `open()`/`openat()` are forced to `O_RDONLY`; `write`, `pwrite`,
`creat`, `unlink`, `unlinkat`, `rename`, `mkdir`, `rmdir`, `link`, `fsync` and
`system()` (used by the chown/chmod paths) all log and fail with `EROFS` without
touching the filesystem. `remove_file_or_dir()`, `mkdir_h()` and `rmdir_h()` are
static in this file, so they call the interposed `unlink`/`rmdir` and become
no-ops too. At runtime the listener's root is additionally pointed at a
**read-only copy** of persist (mounted in step 3). Verified at link time:
`libfsservice.so` imports **no** undefined mutating libc syscall — every write
path is interposed.

(Full inserted block is in the build tree; summary above. The block adds
`fs_ro_deny()`, `fs_ro_open()`, `fs_ro_openat()` and the `#define` interposers
immediately after the `error_number` declaration.)

## Host verification done (functional test deferred to step 3)
- All five deliverables are valid bionic ELF64 AArch64 with correct SONAMEs.
- Shim exports exactly `TZCom_getRootEnvObject` + `TZCom_getClientEnvObject`;
  its only non-libc undefined symbols are `MinkCom_getRootEnvObject` /
  `MinkCom_getClientEnvObject`, both defined in libminkadaptor. Clean link.
- `libminkadaptor.so` is self-contained (qcomtee + QCBOR static); talks `/dev/tee0`.
- FS listener imports no mutating libc syscall (read-only enforced at link level).
- A true functional run is impossible on the workstation: the NDK libc is a
  link-stub and `TZCom_getRootEnvObject` needs `/dev/tee0`, which exists only on
  the phone. Functional validation is step 3 (on-device, modem flag OFF).

## Carried-forward #1 risk (to settle in step 3)
Whether the license READ (`IPFM_CheckInstalledLicense` / `IQWESTAServices`) rides
the Mink/smcinvoke path (shim-covered) or the legacy `libQSEEComAPI` `/dev/qseecom`
path (absent on the qtee1 kernel). If any required step goes through `/dev/qseecom`,
that is a separate, out-of-scope translation → stop + report.

## Hard rules (unchanged)
persist read-only (served from a read-only copy); RPMB listener read-only (log +
refuse every write, never forward to the device); no TA persisted to secure
storage; real modem/EFS/persist partitions never written (hash before/after);
standing dodge rules for any trial boot; no identifiers/firmware/TA/.pfm in the
repo; pr-check before every push; never fake or hard-code a license response.
