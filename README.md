# myinigwe

Build kernel **postmarketOS** untuk **Xiaomi Redmi Note 7 (`xiaomi-lavender`, Qualcomm SDM660 / Adreno 512)** lewat **GitHub Actions**.

Semua build dijalankan di dalam container `alpine:edge` (lewat `docker run`), jadi tidak perlu cross-toolchain di mesin lokal.

## Isi repo

| Path | Keterangan |
| --- | --- |
| `scripts/build.sh` | Script build utama (jalan di dalam `alpine:edge`) |
| `config/config-postmarketos-qcom-sdm660.aarch64` | Kernel config dari pmaports (`device/testing/linux-postmarketos-qcom-sdm660`) |
| `patches/0001-drm-msm-a5xx-write-cp-rb-wptr-under-preempt-lock.patch` | Patch race `CP_RB_WPTR` pada a5xx (Adreno 512) |
| `patches/0002-drm-msm-a5xx-reset-gpu-on-resume.patch` | **Patch utama GPU**: reset GPU saat resume (fix hang `rptr/wptr = 23/C` di SDM660) |
| `patches/0003-wifi-ath10k-dont-reset-txbf-on-disassociation.patch` | **Patch WiFi**: fix crash firmware WCN3990 setiap disconnect |
| `.github/workflows/build-kernel.yml` | Workflow GitHub Actions |

## Kenapa patch ini

Ada **dua** bug a5xx yang berbeda tapi gejalanya mirip. Yang cocok dengan
`xiaomi-lavender` adalah patch **0002**.

### 0002 — GPU hang saat resume (`rptr/wptr = 23/C`) — akar masalah di sini

Di SDM630/SDM660/MSM8998, power domain **GX** ikut ke SMMU GPU, bukan ke GPU
itu sendiri. Jadi GX bisa **tetap hidup** walau GPU sudah di-suspend. GPU yang
resume dengan GX masih hidup menyimpan state-nya, termasuk read pointer (RPTR)
CP di ringbuffer. `a5xx_hw_init()` lalu me-rewind ringbuffer dan menulis
`CP_ME_INIT` di awal, sedangkan CP melanjutkan dari posisi lamanya → mengeksekusi
isi ringbuffer lama → CP opcode error dan hang yang tidak pernah pulih:

```
[drm:adreno_idle] timeout waiting to drain ringbuffer 0 rptr/wptr = 23/C
CP | opcode error | possible opcode=0x00000000
[drm:a5xx_irq] gpu fault ring 0 fence ffffff00 status 800001C1 rb 007a/000c
```

Fix: software-reset GPU di `a5xx_pm_resume()` supaya setiap resume mulai dari
kondisi reset, lalu ambil ulang baseline busy-counter devfreq
(`msm_devfreq_resample_busy()`).

Sumber: Fabricio Akio, FROMLIST, commit `be8062b9b0` di
`sdm660-mainline/linux` (belum ada di tag `v7.0.14-sdm660`).

### 0001 — race penulisan `CP_RB_WPTR`

`CP_RB_WPTR` ditulis dari dua tempat: `a5xx_flush()` (submit baru) dan
`update_wptr()` (dipanggil IRQ handler saat submit selesai). Keduanya membaca
wptr di bawah `ring->preempt_lock`, tapi menulis register **setelah** lock
dilepas, sehingga dua penulisan bisa terjadi dengan urutan terbalik → wptr
mundur. Patch memindahkan penulisan register ke **dalam** lock. Terbukti
membantu di A508 (SDM630), **tidak cukup** untuk lavender (A512) — makanya
patch 0002 tetap diperlukan.

### 0003 — WiFi mati total setiap disconnect (crash WCN3990)

Firmware WCN3990 (`WLAN.HL.1.0.1.c2-00498`) **crash setiap kali vdev di-set
TxBF saat vdev tidak punya peer AP**. `ath10k_bss_disassoc()` melakukan itu
tepat setelah peer dihapus, jadi crash terjadi di **setiap disconnect**:

```
qcom-q6v5-mss 4080000.remoteproc: fatal error received:
  err_qdi.c:459:EX:wlan_process:1:WLAN RT:2083:PC=b00c87e0
remoteproc remoteproc1: crash detected in 4080000.remoteproc: type fatal error
wlan0: failed to remove key (0, ...) from hardware (-110)
```

Setelah itu `ath10k` tidak bisa probe ulang (walau modul di-`rmmod`/`modprobe`),
`wlan0` tetap DOWN, scan gagal (`Scanning not allowed while unavailable`), dan
satu-satunya jalan adalah **reboot**. Ini sangat terasa kalau ada 2 router/AP:
pindah ruangan → disconnect → WiFi mati.

Fix: hapus pemanggilan `ath10k_mac_vif_recalc_txbf()` di
`ath10k_bss_disassoc()`. Tidak perlu di-reset di situ karena
`ath10k_bss_assoc()` akan men-set TxBF lagi dari capability AP berikutnya
sebelum vdev dinyalakan.

Sumber: Fabricio Akio, FROMLIST, `[PATCH] wifi: ath10k: don't reset TxBF on
disassociation` (11 Okt 2026). Belum ada di upstream `torvalds/linux`,
`linux-next`, maupun `wireless-testing`.

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

6. Pasang juga **semua modul** ke rootfs (bukan cuma initramfs), lalu `depmod -a`.
   Fix WiFi ada di `ath10k_core`/`ath10k_snoc` yang dimuat dari rootfs, sedangkan
   `msm` dimuat dari initramfs (jadi initramfs juga harus di-repack dengan `msm.ko`
   dari build yang sama).

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
- Patch GPU: Fabricio Akio, ML linux-kernel (19 Okt 2026)
- Patch WiFi: Fabricio Akio, ML linux-wireless (11 Okt 2026)