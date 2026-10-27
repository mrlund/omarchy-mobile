# dodge qwesd READ path - step 1: SMCINVOKE->qcomtee ABI map + shim design (2026-10-27)

## Transport topology of the vendor QWES stack (from read-only ELF inspection)
- qwes_cli --NEEDED--> libqwes.so, libminkdescriptor.so, libminksocket_vendor.so, libQSEEComAPI.so,
  libqcbor, libcutils/utils/log/crypto/dsi_netctrl, libc++/c/m/dl.
- qwesd   --NEEDED--> libminkdescriptor.so, libminksocket_vendor.so, libQSEEComAPI.so, libqcbor,
  libcrypto, libcurl, libqmi_csi, libdsi_netctrl, libavservices_minijail, liblog/utils, libc++/c/m/dl.
- libqwes.so --NEEDED--> libminksocket_vendor.so, libQSEEComAPI.so, libqcbor, utils/cutils/log,
  libc++/c/m/dl.  It does NOT link libminkdescriptor.so, and its strings show /dev/socket/qwes_ipc:
  libqwes/qwes_cli are CLIENTS of the qwesd daemon over a unix socket; the secure-world access lives
  in qwesd.
- Secure-world transports in qwesd:
  * libminkdescriptor.so -> opens /dev/smcinvoke, SMCINVOKE_IOCTL_* (the Mink/Object path; TA IDLs
    like IQWESTAServices are Mink interfaces invoked here).
  * libQSEEComAPI.so -> /dev/qseecom (legacy QSEE blob-command path: QSEECom_send_cmd etc.).
  * libminksocket_vendor.so -> /dev/membuf + /dev/qti-smmu-proxy + socketpair: HLOS<->HLOS Mink
    object passing (e.g. qwesd exposing objects to its socket clients), NOT a QTEE transport.

## Symbol diff (the step-1 question the brief asked to answer first)
Exported (defined) dynamic symbols of vendor libminkdescriptor.so: 50 total (TZCom_*, MinkDescriptor_*,
FdWrapper_*, the whole MinkCBContext C++ class incl. marshalRequestIn/marshalResponseOut over
smcinvoke_accept, CIO_open, exception typeinfo, __cfi_check).
Symbols that qwesd + qwes_cli actually IMPORT (undefined) and that libminkdescriptor DEFINES:
    TZCom_getRootEnvObject
    TZCom_getClientEnvObject
...and nothing else. After bootstrap, every QTEE call rides the returned object's vtable:
Object_invoke is a `static inline` in object.h (dispatch through the Object's own function pointer),
so it is NOT a dynamic symbol and needs no interposition. `Object` is the same 2-pointer C ABI
({invoke, context}) on both sides.

RESULT: the vendor imports match libminkadaptor with only a THIN FORWARDING SHIM (2 functions). No
missing symbols beyond that; the 48 other libminkdescriptor exports (MinkCBContext etc.) are unused
by the consumers. This is well under the "more than a thin shim" bar.

## SMCINVOKE <-> qcomtee ABI correspondence (reference; we do NOT implement this ioctl layer)
Because the shim boundary is the Mink Object API (not the ioctl), we never translate smcinvoke ioctls;
libminkadaptor already speaks qcomtee natively. For completeness the semantic map is:
  SMCINVOKE_IOCTL_INVOKE_REQ (0x32000600)      <-> TEE_IOC_OBJECT_INVOKE (tee_ioctl_object_invoke_arg)
  SMCINVOKE_IOCTL_ACCEPT_REQ / SERVER_REQ      <-> TEE_IOC_SUPPL_RECV  (qcomtee_user_object_select)
  SMCINVOKE_IOCTL_ACK_LOCAL_OBJ / cb response  <-> TEE_IOC_SUPPL_SEND  (qcomtee_user_object_submit)
  tzhandle [1b local|15b obj|16b server]       <-> TEE OBJREF param (QCOMTEE_OBJREF_FLAG_USER marks
                                                    user/callback objects)
  root object handle 1 (SMCINVOKE_TZ_ROOT_OBJ) <-> MinkCom_getRootEnvObject() (primordial handle 0)
  shared/memory objects (MEM_RGN/MEM_MAP srvr) <-> MinkCom_getMemoryObject() (page-aligned shm)

## Shim design (the drop-in)
Build a bionic aarch64 shared object with SONAME libminkdescriptor.so that exports only:
  int TZCom_getRootEnvObject(Object *obj)        { return MinkCom_getRootEnvObject(obj); }
  int TZCom_getClientEnvObject(Object *out) {
      Object root = Object_NULL;
      int r = MinkCom_getRootEnvObject(&root); if (r) return r;
      r = MinkCom_getClientEnvObject(root, out);
      Object_release(root);
      return r;
  }
It links libminkadaptor (-> quic-teec libqcomtee -> /dev/tee0) + QCBOR. Installed into the bionic
qwesd environment in place of the vendor libminkdescriptor.so (same SONAME) so qwesd resolves the two
TZCom_* symbols against it; all subsequent Object_invoke calls flow through libminkadaptor to qcomtee.
Everything is bionic aarch64 (NDK) because it loads into the bionic qwesd process.

## #1 open risk to confirm empirically in step 3
Does the license READ (IPFM_CheckInstalledLicense / IQWESTAServices) ride the Mink path
(libminkdescriptor -> our shim -> qcomtee), or the legacy libQSEEComAPI path (/dev/qseecom)? Our qtee1
kernel exposes upstream qcomtee (/dev/tee0) but NOT the downstream /dev/qseecom char device. The QWES
TA interfaces are Mink IDLs, which argues for the Mink path (covered by the shim). If any required
step instead goes through /dev/qseecom, that is a separate, out-of-scope translation -> stop + report.
Step 3 logs every transport call to settle this.

## Hard rules (unchanged)
persist read-only (served from a read-only copy); RPMB listener read-only (log+refuse every write by
type/size, never forward); no TA persisted to secure storage (QTEE-memory load OK); real
modem/EFS/persist never written (hash before/after); standing dodge trial rules; no
identifiers/firmware/TA/.pfm in repo; never fake/hard-code a license response; if a secure-storage
write is needed to succeed, stop and report.
