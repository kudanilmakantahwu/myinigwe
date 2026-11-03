# myinigwe

Repo ini AI slop, dibikin karena gabut. README-nya juga AI slop.

## Patch

Tag `v7.0.14-sdm660` belum memuat patch di bawah, jadi dibawa sendiri di sini.
Penomoran ngikutin urutan commit di `sdm660-mainline/linux`.

- `0001`-`0005` : fix GPU a5xx (Adreno 512). Tanpa ini, GPU hang bikin satu HP panic dan reboot, terutama gara-gara crashdump yang baca register GPMU (a512 nggak punya GPMU). Patch kuncinya `0002`
- `0006` : fix WiFi ath10k. Firmware WCN3990 crash tiap disconnect, abis itu WiFi mati sampai reboot

## Sumber

- Kernel: <https://github.com/sdm660-mainline/linux> tag `v7.0.14-sdm660`
- Config & packaging: pmaports `device/testing/linux-postmarketos-qcom-sdm660`
- Patch GPU: Fabricio Akio & Dmitry Baryshkov, FROMLIST, Sep–Nov 2026
  (`65ad6c39b`, `102afe512`, `be8062b9b`, `b63149ee8`, `45b54a7c4`)
- Patch WiFi: Fabricio Akio, ML linux-wireless (11 Okt 2026)
