# myinigwe

Repo ini AI slop, dibikin karena gabut. README-nya juga AI slop.

## Patch

Tag `v7.0.14-sdm660` belum memuat patch di bawah, jadi dibawa sendiri di sini.
Penomoran ngikutin urutan commit di `sdm660-mainline/linux`.

- `0001`-`0005` : fix GPU a5xx (Adreno 512). Tanpa ini, GPU hang bikin satu HP panic dan reboot, terutama gara-gara crashdump yang baca register GPMU (a512 nggak punya GPMU). Patch kuncinya `0002`
- `0006` : fix WiFi ath10k. Firmware WCN3990 crash tiap disconnect, abis itu WiFi mati sampai reboot

Sumber: Fabricio Akio / Dmitry Baryshkov (FROMLIST), `sdm660-mainline/linux` dan linux-wireless.


