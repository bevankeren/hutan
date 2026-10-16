# Legit — Auto Perfect Minigame

Fitur tab **Legit**: bot mainin minigame tebang pohon beneran (bukan ketok flag dari server) sampai hasilnya **Perfect**. Animasi, suara, UI minigame — semua jalan natural karena yang direrun adalah alur asli game.

Status: **riset selesai, implementasi setengah jalan**. Detail di bagian [Status](#status).

---

## Hasil reverse engineering

### Peta alur

```
Pemain tahan input (tahan tombol / tap)
  → ChopController:BeginWindup
  → lepas → ReleaseWindup → kapak terbang → sesi mulai (server: StartChop)
  → minigame jalan (client-side murni)
  → onFinish(done, perfect)
  → TreeService:FinishChop(tree, done, perfect)   ← server percaya flag perfect dari client
```

### Tiga jenis minigame (dipilih per axe, field `ChopTuning.Minigame`)

| Minigame | Mekanik | File |
|---|---|---|
| **Chop** | tahan = bar naik, lepas = turun, jaga bar di bawah spot | `PlayerScripts/Source/ui/ChopMinigame/useChopSimulation` |
| **Swing** | timing swing | `PlayerScripts/Source/ui/SwingMinigame/useSwingSimulation` |
| **Notch** | ritme: ring mengejar target lingkaran, tap pas align | `PlayerScripts/Source/ui/NotchMinigame/*` |

Axe aktif (DriftwoodAxe) pakai **Notch**.

### NotchMinigame — yang perlu diketahui

- `useNotchSimulation` — grading murni client. Per tekan:
  - `fraction = 1 - (elapsed - dot.Start) / Approach`
  - grade = `|fraction - 0.3| <= Perfect` → **"Perfect"**, `<= Good` → "Good", sisanya "None"
  - grade apa pun selain Perfect → `perfect = false` permanen untuk tebangan itu
  - kalau dot lewat tanpa ditekan (fraction < 0.3 - Good) → **Miss**: progress dipotong `HitStep * MissCost`, combo reset
  - tekan berhasil → dot berikutnya di-arms di `elapsed + Recover`
- Ada dua jalur press (`v_u_14` mapper):
  - **Mouse/Touch dengan posisi** → jalur `"Aimed"` → dicek `isOnMark(1, pos)` (posisi press harus di dekat mark) → **window penuh** (×1)
  - **Keyboard (Space)** → jalur `"Button"` → cek aim **di-skip** → tapi window dikali **0.6** (lebih sempit)
  - Khusus layar sentuh besar (`min(w,h) >= 600`): press apapun lolos cek aim, window penuh
- Visual (`NotchDot` → `DotRing` → `NotchRing`):
  - Dot = **BillboardGui** di `PlayerGui.ReactWorld.Dot1..N`, adornee = titik lemah di batang
  - Struktur: `Dot1 > Area (TextButton) > Ring (Frame) > Square > [Target, Ring-dalam]`
  - Ukuran Ring animasi dari besar→kecil sesuai `fraction`
  - **Stroke Ring ganti warna jadi `Theme.NotchPerfect` persis di jendela Perfect** — ini kunci bot
  - Setelah tekan, muncul HitWord: `"Perfect"`, `"Good"`, `"Miss"` — bisa dibaca buat verifikasi

### Temuan input (executor ini)

| Metode | Hasil |
|---|---|
| `firesignal(UIS.InputBegan, tbl, false)` | **jalan** — listener nerima tabel palsu (`KeyCode`/`UserInputType`/`Position` dibaca manual oleh handler) |
| `vim:SendMouseButtonEvent(x, y, 0, down, game, 0)` | **jalan** — masuk pipeline input asli, `UIS.InputBegan` tembak, `UserInputType = MouseButton1` |
| `vim:SendTouchEvent(x, y, state)` | gagal — signature sebenarnya 4 arg `(id, x, y, state)`, dan walau `ok=true` **tidak** menembak `UIS` di host ini |
| `vim:SendKeyEvent(...)` | semua varian arg gagal menembak `UIS` |
| `firesignal` untuk mulai tebang (ButtonR2 windup) | tidak memulai sesi |

**Kesimpulan:** mulai tebang + press = `SendMouseButtonEvent` (pipeline asli). Press ritme alternatif = `firesignal` Space (jalur Button, window 0.6×).

---

## Desain bot (final)

```
1. Mulai tebang:
   - teleport dekat pohon (jangan anchor), hitung posisi Trunk di layar (WorldToViewportPoint)
   - vim:SendMouseButtonEvent(x, y, 0, true)  → windup
   - tunggu ~0.45s
   - vim:SendMouseButtonEvent(x, y, 0, false) → lepas → sesi + minigame mulai

2. Main minigame (Notch):
   - pantau PlayerGui → BillboardGui "Dot%d" → Area → Ring → UIStroke
     ( struktur dirender async — WAJIB polling, cek sekali langsung gagal )
   - setiap frame baca UIStroke.Color
   - kalau ≈ Theme.NotchPerfect (0.61, 0.89, 0.48):
       posisi press = proyeksi layar dari dot.Adornee (pusat lingkaran)
       vim:SendMouseButtonEvent(pos, 0, true) … 0.06s … (pos, 0, false)
   - repeat sampai pohon tumbang / sesi selesai
```

Kenapa ini "legit":
- Press-nya lewat pipeline input asli (event `UIS.InputBegan` beneran, bukan call remote langsung)
- Timing-nya mengikuti jendela yang sama dengan pemain manusia (window penuh, bukan dipaksa)
- Tidak menyentuh remote sama sekali — server cuma lihat hasil `FinishChop` dari alur normal
- Animasi/suara/UI jalan semua karena minigame aslinya yang direrun

---

## Status

### Sudah terverifikasi (live client)

- [x] `Theme.NotchPerfect` kebaca: `(0.608, 0.886, 0.478)`
- [x] Sesi tebang bisa dimulai via `SendMouseButtonEvent` (UI `NotchProgress.Bar > Fill` muncul, 212px = progress penuh)
- [x] BillboardGui `Dot1` ketemu di `PlayerGui.ReactWorld`
- [x] Struktur `Area > Ring` ada; **stroke belum kebaca saat cek pertama** → React render anak-nya async, perlu polling (fix sudah ditulis, belum sempat diverifikasi — client putus saat test)

### Belum / lanjutan

- [ ] Verifikasi press di jendela hijau → HitWord muncul `"Perfect"` (baca TextLabel di dalam Dot)
- [ ] Verifikasi tebangan tumbang dengan semua press Perfect (tanpa hook server)
- [ ] Bot Chop (bar-hold) dan Swing kalau mau support axe lain
- [ ] Tanam ke tab Legit: toggle "Auto Perfect" versi main-minigame ini (toggle lama versi flag-flip dipisah/rename)
- [ ] Pertimbangkan humanize: jitter kecil di timing/posisi biar makin natural

### Pendekatan lama (flag-flip, sudah jalan)

Hook `TreeService.FinishChop`: chop sukses (`done=true`) dinaikkan `perfect=true`. Sudah dites live (`Ok=true, Felled=true`). Kekurangan: tanpa animasi minigame — ini yang membuat Captain minta versi main-beneran. Fungsi ini masih ada di `farm_hub.lua` (`perfect_hook_install`) sebagai fallback.

---

## Referensi file game

| File | Isi kunci |
|---|---|
| `Source/ui/NotchMinigame/useNotchSimulation` | grading, window Perfect/Good, arm dot, miss handling (line 129-310) |
| `Source/ui/NotchMinigame/NotchDot` | BillboardGui + Area press → `sim.strike(pos)` |
| `Source/ui/NotchMinigame/DotRing` | binding `ring` = fraction, `zone` = grade sekarang |
| `Source/ui/NotchMinigame/NotchRing` | warna stroke = zone (NotchPerfect saat jendela Perfect) |
| `Source/ui/Theme` | warna `NotchPerfect` / `NotchMark` |
| `Source/modules/ChopController` | input windup (ButtonR2 / Touch), `OnFinish` → `FinishChop(tree, done, perfect)` (line 615-646) |
| `ReplicatedStorage/Modules/Lumber/ChopTuning` | params per axe: `Minigame`, `BarWidth`, `SpotSpeed`, dll |
