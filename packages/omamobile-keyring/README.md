# omamobile-keyring

The public key that signs Omarchy Mobile's packages and the `[omamobile]` repository
database, in pacman's keyring format. Installing it runs
`pacman-key --populate omamobile`, which imports the key and marks it trusted
(`omamobile-trusted`), the same way `archlinux-keyring` works.

The private key never leaves the build machine (`keys/`, ignored by git).
This fork signs with its own key. Replacing `omamobile.gpg` and
`omamobile-trusted` is the whole rotation; nothing else is pinned to it.
Fingerprint: `25BDA218F840C6599ED2C9DEB2C953852499B229`.
