# myinigwe

Build kernel **postmarketOS** untuk **Xiaomi Redmi Note 7 (`xiaomi-lavender`, Qualcomm SDM660 / Adreno 512)** lewat **GitHub Actions**.

Semua build dijalankan di dalam container `alpine:edge` (lewat `docker run`), jadi tidak perlu cross-toolchain di mesin lokal.

## Isi repo

| Path | Keterangan |
| --- | --- |
| `scripts/build.sh` | Script build utama (jalan di dalam `alpine:edge`) |
| `config/config-postmarketos-qcom-sdm660.aarch64` | Kernel config dari pmaports (`device/testing/linux-postmarketos-qcom-sdm660`) |
| `patches/0001-drm-msm-a5xx-write-cp-rb-wptr-under-preempt-lock.patch` | Patch perbaikan GPU hang a5xx (Adreno 512) |
| `.github/workflows/build-kernel.yml` | Workflow GitHub Actions |

## Kenapa patch ini

`CP_RB_WPTR` ditulis dari dua tempat: `a5xx_flush()` (submit baru) dan
`update_wptr()` (dipanggil IRQ handler saat submit selesai). Keduanya membaca
wptr di bawah `ring->preempt_lock`, tapi menulis register **setelah** lock
dilepas, sehingga dua penulisan bisa terjadi dengan urutan terbalik. Akibatnya
`CP_RB_WPTR` menunjuk ke belakang submit terakhir → CP opcode error → fence
mundur → GPU hang permanen sampai reboot.

Patch memindahkan penulisan register ke **dalam** lock.

## Cara pakai

1. Jalankan workflow **build-kernel** (manual via *Run workflow*, atau otomatis saat push ke `main`).
2. Unduh artifact `linux-7.0.14-sdm660`.
3. Di PC: bikin `boot.img` dengan `scripts/mkboot.py` (kernel `Image.gz` + DTB lavender yang di-append, ramdisk = initramfs HP).
4. Tes tanpa menulis partisi:

   ```
   fastboot boot boot-7.0.14-sdm660.img
   ```

5. Kalau sehat, baru flash permanen:

   ```
   fastboot flash boot boot-7.0.14-sdm660.img
   ```

## Cacat yang perlu diwaspadai: `modules.dep` kosong

Tree modul hasil build pmbootstrap (`linux-postmarketos-qcom-sdm660`) bisa ikut
terpasang dengan **`modules.dep` yang dependency-nya kosong** — semua baris
berakhiran `:` tanpa daftar modul. Akibatnya `modprobe` tidak memuat dependency,
contohnya `ath10k_snoc` di-`insmod` sendirian lalu gagal dengan
`Unknown symbol ath10k_core_*` → **WiFi tidak muncul sama sekali** (`wlan0`
tidak ada, scan kosong, toggle WiFi mati sendiri).

Setelah memasang kernel/modul baru, **selalu** jalankan:

```
depmod -a
grep ath10k /lib/modules/$(uname -r)/modules.dep   # harus ada dependency-nya
```

Baris yang benar terlihat seperti:

```
.../ath10k_snoc.ko.zst: .../ath10k_core.ko.zst .../mac80211.ko.zst ...
```

Bukan:

```
.../ath10k_snoc.ko.zst:
```

## Catatan penting

- Kernel ini pakai `CONFIG_CFI=y` (kCFI). **Kernel dan modul harus dibuild oleh compiler yang sama persis.** Karena itu workflow membangun kernel **dan** modul dalam satu job (satu image `alpine:edge`, satu clang).
- Jangan mencampur modul dari build berbeda (mis. ambil `msm.ko.zst` dari package lain) — kCFI type hash bisa tidak cocok.
- `boot-deploy`/`mkinitfs` di HP punya `deviceinfo_flash_kernel_on_update=true`: setiap regenerasi initramfs **langsung menulis** `boot.img` ke partisi boot. Hati-hati saat eksperimen.
- Rollback: simpan salinan `boot.img` yang terbukti boot, lalu `fastboot flash boot <image-lama>`.

## Sumber

- Kernel: <https://github.com/sdm660-mainline/linux> tag `v7.0.14-sdm660`
- Config & packaging: pmaports `device/testing/linux-postmarketos-qcom-sdm660`
- Patch: Fabricio Akio, ML linux-kernel (1 Nov 2026)