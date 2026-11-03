# myinigwe

Repo ini AI slop, dibikin karena gabut. README-nya juga AI slop.

## Patch

Tag `v7.0.14-sdm660` belum memuat patch di bawah, jadi dibawa sendiri di sini.
Penomoran ngikutin urutan commit di `sdm660-mainline/linux`.

- `0001`-`0005` : fix GPU a5xx (Adreno 512). Tanpa ini, GPU hang bikin satu HP panic dan reboot, terutama gara-gara crashdump yang baca register GPMU (a512 nggak punya GPMU). Patch kuncinya `0002`
- `0006` : fix WiFi ath10k. Firmware WCN3990 crash tiap disconnect, abis itu WiFi mati sampai reboot

Sumber: Fabricio Akio / Dmitry Baryshkov (FROMLIST), `sdm660-mainline/linux` dan linux-wireless.

## Cara pakai

1. Jalanin workflow `build-kernel`, download artifact `linux-7.0.14-sdm660`
2. Bikin `boot.img` pakai `scripts/mkboot.py`
3. Tes dulu: `fastboot boot boot-7.0.14-sdm660.img`
4. Kalau aman: `fastboot flash boot boot-7.0.14-sdm660.img`
5. Pasang semua modul ke rootfs, jalanin `depmod -a`, dan repack initramfs pakai `msm.ko` dari build yang sama

## Catatan

- Kernel dan modul harus dari build yang sama (`CONFIG_CFI=y` + BTF). Modul dari build lain ditolak dengan error BTF `-22` / `-40`
- Kalau `modules.dep` dependency-nya kosong, WiFi nggak muncul. Jalanin `depmod -a`, terus cek `grep ath10k /lib/modules/$(uname -r)/modules.dep`
- `mkinitfs` di HP langsung nulis `boot.img` ke partisi boot tiap initramfs di-generate. Simpan salinan `boot.img` yang terbukti boot buat rollback
