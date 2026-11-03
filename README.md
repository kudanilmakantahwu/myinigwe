# myinigwe

Build kernel **postmarketOS** untuk **Xiaomi Redmi Note 7 (`xiaomi-lavender`, Qualcomm SDM660 / Adreno 512)** lewat **GitHub Actions**.

Semua build dijalankan di dalam container `alpine:edge` (lewat `docker run`), jadi tidak perlu cross-toolchain di mesin lokal.

## Isi repo

| Path | Keterangan |
| --- | --- |
| `scripts/build.sh` | Script build utama (jalan di dalam `alpine:edge`) |
| `config/config-postmarketos-qcom-sdm660.aarch64` | Kernel config dari pmaports (`device/testing/linux-postmarketos-qcom-sdm660`) |
| `patches/0001-drm-msm-a5xx-add-hangcheck-progress-detection.patch` | hangcheck: deteksi progres ALU supaya dispatch panjang tidak salah dianggap hang (`65ad6c39b`) |
| `patches/0002-drm-msm-a5xx-dont-read-gpmu-registers-without-gpmu.patch` | **KRITIS**: jangan baca register GPMU saat crashdump pada a512 (tidak punya GPMU) — kalau dibaca, SoC **reboot/panic** saat GPU hang (`102afe512`) |
| `patches/0003-drm-msm-a5xx-reset-gpu-on-resume.patch` | reset GPU saat resume (fix hang `rptr/wptr = 23/C`) (`be8062b9b`) |
| `patches/0004-drm-msm-a5xx-hold-cpu-latency-request.patch` | tahan CPU latency request selama GPU powered, cegah GPU stall saat SoC power-collapse (`b63149ee8`) |
| `patches/0005-drm-msm-a5xx-write-cp-rb-wptr-under-preempt-lock.patch` | race penulisan `CP_RB_WPTR` (`45b54a7c4`) |
| `patches/0006-wifi-ath10k-dont-reset-txbf-on-disassociation.patch` | **Patch WiFi**: fix crash firmware WCN3990 setiap disconnect |
| `.github/workflows/build-kernel.yml` | Workflow GitHub Actions |

Urutan penomoran mengikuti urutan commit di `sdm660-mainline/linux` supaya
semua patch apply bersih tanpa `.rej`.

## Kenapa patch ini

Tag `v7.0.14-sdm660` dibuat **2 Agustus 2026**, sedangkan semua patch GPU
FROMLIST di bawah ini baru masuk ke branch utama `sdm660-mainline/linux`
pada **September–November 2026**. Jadi tag itu **belum** memuatnya dan harus
dibawa out-of-tree.

### GPU — 5 patch a5xx (Adreno 512)

Gejala di lavender: GPU hang saat dipakai (contoh paling jelas: `angelfish`
/ QtWebEngine), lalu **seluruh HP panic dan reboot**:

```
[drm:hangcheck_handler] *ERROR* 5.1.2.0: hangcheck detected gpu lockup rb 2!
[drm:hangcheck_handler] *ERROR* 5.1.2.0:     completed fence: 9657
[drm:hangcheck_handler] *ERROR* 5.1.2.0:     submitted fence: 9665
[drm:recover_worker]   *ERROR* 5.1.2.0: hangcheck recover!
[drm:recover_worker]   *ERROR* 5.1.2.0: offending task: Chrome_InProcGp (/usr/sbin/angelfish)
watchdog: CPU1: Watchdog detected hard LOCKUP on cpu 2
Kernel panic - not syncing: Hard LOCKUP
```

Penyebab reboot-nya bukan hang itu sendiri, tapi **crashdump**: saat GPU hang,
driver mengumpulkan register untuk crashstate. Pada a512 (SDM660) **tidak ada
GPMU**, tetapi kode lama tetap membaca aperture GPMU `0xa800-0xac60`, dan di
sda660 pembacaan itu **me-reset board**. Patch `0002` memisahkan blok GPMU dan
hanya membacanya kalau `adreno_is_a530() || adreno_is_a540()`. Dengan patch ini
GPU hang seharusnya **pulih** (recover) alih-alih memicu panic.

Patch `0004` menyerang hang-nya: GPU bisa berhenti saat SoC masuk system-level
power collapse (interupsi GPU tidak punya jalur wakeup lewat MPM). Downstream
Qualcomm memegang CPU latency request (`qcom,pm-qos-active-latency`) selama GPU
aktif; patch ini melakukan hal yang sama (`cpu_latency_us` 518 us untuk A512).

`0001` mencegah false-positive hangcheck pada dispatch komputasi panjang.
`0003` menangani bug resume/GX yang di SDM660 bisa membuat CP mengeksekusi ulang
ringbuffer lama. `0005` menutup race `CP_RB_WPTR` antara submit dan IRQ handler.

Semua sumber: **Fabricio Akio / Dmitry Baryshkov, FROMLIST**, di
`sdm660-mainline/linux` (belum ada di tag `v7.0.14-sdm660`).

### WiFi — 0006: mati total setiap disconnect (crash WCN3990)

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

- Kernel ini pakai `CONFIG_CFI=y` (kCFI) dan `CONFIG_DEBUG_INFO_BTF_MODULES=y`.
  **Kernel dan modul harus berasal dari build yang sama.** BTF pada modul
  mengikat ke BTF `vmlinux` build tersebut; memuat modul build lain ditolak
  dengan `failed to validate module [x] BTF: -22` / `-40 (ELOOP)`
  (`modprobe: ... Symbolic link loop`).
- Kalau perlu memindahkan modul antar-build dengan `vermagic` sama (mis. pasang
  modul CI ke kernel lokal), **strip `.BTF` dan `.BTF.ext`** dari modul
  (`aarch64-linux-gnu-objcopy --remove-section .BTF --remove-section .BTF.ext`
  lalu re-`zstd`) supaya lolos validasi. BTF tidak dipakai untuk fungsi runtime.
- Karena `CONFIG_CFI=y`, kernel **dan** modul wajib dibuild oleh compiler yang
  sama persis. Workflow membangun kernel **dan** modul dalam satu job (satu image
  `alpine:edge`, satu clang).
- `boot-deploy`/`mkinitfs` di HP punya `deviceinfo_flash_kernel_on_update=true`:
  setiap regenerasi initramfs **langsung menulis** `boot.img` ke partisi boot.
  Hati-hati saat eksperimen.
- Rollback: simpan salinan `boot.img` yang terbukti boot, lalu
  `fastboot flash boot <image-lama>` (atau `dd` ke `/dev/mmcblk1p60`).

## Sumber

- Kernel: <https://github.com/sdm660-mainline/linux> tag `v7.0.14-sdm660`
- Config & packaging: pmaports `device/testing/linux-postmarketos-qcom-sdm660`
- Patch GPU: Fabricio Akio & Dmitry Baryshkov, FROMLIST, Sep–Nov 2026
  (`65ad6c39b`, `102afe512`, `be8062b9b`, `b63149ee8`, `45b54a7c4`)
- Patch WiFi: Fabricio Akio, ML linux-wireless (11 Okt 2026)