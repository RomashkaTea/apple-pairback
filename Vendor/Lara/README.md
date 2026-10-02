# Vendored Lara components

This directory contains the minimum exploit sources and two linked libraries needed by PairBack, copied from [rooootdev/lara](https://github.com/rooootdev/lara) commit `879e3fae0822776d1f75f91d9f2d1aee505f339e`.

PairBack's copy of `kexploit/darksword.m` differs from that commit only by two `#if !defined(PAIRBACK_DISABLE_PERSISTENCE)` guards around launchd KRW recovery/transfer. The project defines `PAIRBACK_DISABLE_PERSISTENCE=1`. Acquisition code is unchanged. `persistence.m` and RemoteCall implementation files are neither included nor linked.

Lara is distributed under AGPL-3.0; the full license is in the repository root. The prebuilt `libxpf.dylib` and `libgrabkernel2.dylib` are the copies shipped with the pinned Lara commit. The original project and its notices remain available at the upstream URL above.

| Vendored library | SHA-256 |
| --- | --- |
| `libxpf.dylib` | `e87d0469bc542e1403531cf7d4f027335d514882c78b5a80cb750c5e6f310a30` |
| `libgrabkernel2.dylib` | `fb27032f7a9401b52ba94821de301aa2a57e3f61fc67bf464db3ce4075b52a4e` |
