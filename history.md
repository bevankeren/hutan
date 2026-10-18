# history.md

Garis waktu proyek. Aturan penulisan ada di `rules.md`.

Entri terbaru ada di **paling bawah**. Baca dari bawah kalau mengambil alih.

---

## 2026-10-17 ±17:00 +07:00 — awal proyek

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: belum tercatat

### Perubahan
- Mulai membedah anticheat Foresters, target awal: AFK farm hub.
- Rencana awal: deteksi pohon Mythic/Secret otomatis, teleport, tebang, lalu
  server-hop saat habis.

### Alasan
- Permintaan Captain.

### Bukti
- Belum ada pengukuran terstruktur.

---

## 2026-10-18 ±11:40 +07:00 — auto-hop dihapus

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134

### Perubahan
- Menghapus semua kode `TeleportService`, sweep antar-server, dan auto-hop.
- Verifikasi: 0 referensi `TeleportService` tersisa di `farm_hub.lua`.

### Alasan
- Captain: "kita kena hop gara gara collosion ga sih" lalu "oh itu kode kita
  sendiri? ga guna ga sih apus aja".
- Auto-hop ternyata memicu masalah sendiri, bukan menyelesaikannya.

### Bukti
- Hitungan referensi `TeleportService` = 0 setelah penghapusan.

---

## 2026-10-18 ±12:30 +07:00 — mode Walk (pathfinding) ditambahkan

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134

### Perubahan
- Menambah grup **Movement** di tab Farming: `Mode: Walk`, `Mode: Teleport`,
  `Walk speed`, `Walk, teleport beyond`, `Strip map while walking`,
  `Teleport if walk fails`.
- `WALK` table di `getgenv().__ForestFarmWalk` berisi `noclip`, `strip`,
  `unstrip`, `stand`, `leg`, `go`.

### Alasan
- Captain memakai hub lain (Ouroboros) yang jalan pakai pathfinding, bukan
  teleport, dan chop-nya tetap jalan. Teleport kita masih sering ngebug, jadi
  walk dijadikan alternatif.

### Bukti
- Satu run bersih: 294 stud berjalan, sampai 5 stud dari pohon, 10 perfect
  strike, `Felled`, health 100, JobId tidak berubah.

---

## 2026-10-18 13:27 +07:00 — analisis Ouroboros v0.38

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134

### Perubahan
- Menulis `OUROBOROS_ANALYSIS.md`.

### Alasan
- Membedah kenapa hub orang lain bisa jalan padahal punya kita tidak.

### Bukti
- Gerakan Ouroboros: `Humanoid:MoveTo` + `WalkToPoint` ~22 stud/s dengan
  `CanCollide=false`.
- Setting `Walk: Teleport If Farther Than = 125`, `Strip Map (Walk)` aktif.
- 67 fitur di 7 tab: Home / Main / Shop / Teleport / Visuals / Webhook / Player /
  Settings.
- Mereka juga macet ~4 detik lalu pulih sendiri lewat recompute path.
- Sumber aslinya dilindungi FlowAuth (project `2681`, script `5674`), tidak bisa
  dibaca.

---

## 2026-10-18 14:30 +07:00 — soak test gagal, kick 285 teridentifikasi

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : a8261516-da5f-4792-b082-6c39d1939868

### Perubahan
- Menulis `SOAK_TEST_LOG.md`.

### Alasan
- Lima percobaan soak 5 menit semuanya putus.

### Bukti
- Enam disconnect, semuanya kode sama:
  `Player: 285 (DisconnectClientInitiated)` pada 06:52, 07:01, 07:17, 07:32,
  07:35, 07:46 UTC. Jeda tidak teratur: 543s, 955s, 895s, 238s, 655s.
- Bukan crash: tidak ada `CrashpadHandler`, proses tetap hidup, `Responding=True`.
- Bukan ban: tidak ada event `Banned`, tidak ada pesan kick.
- Bukan kode kita: `TeleportService` = 0 referensi.
- Bukan walker: satu disconnect terjadi saat hub tidak dimuat sama sekali.

---

## 2026-10-18 15:24 +07:00 — Respawn-TP ditemukan dan terbukti

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : a8261516-da5f-4792-b082-6c39d1939868

### Perubahan
- Menulis `RESPAWN_TP_BYPASS.md`.
- Menambah `WALK.respawnJump(dest)` dan `Mode: Respawn TP` + slider delay.

### Alasan
- Ide Captain: respawn dulu, lalu langsung teleport. Respawn menghapus baseline
  posisi server, jadi lompatan di jendela itu diterima.

### Bukti
- Lompatan 1248 stud bertahan 4,7 detik tanpa snapback.
- 4 dari 5 trial berhasil dengan target berganti-ganti.
- Yang gagal: `maxD=167`, dan raycast menunjukkan targetnya 30 stud di atas
  seabed (`Terrain` Y=0) — salah ketinggian, bukan ditolak server.
- Dua bug ditemukan dan diperbaiki:
  - raycast menembus kanopi pohon, melaporkan groundY 75 padahal permukaan asli 46
  - respawn mengembalikan kapak ke backpack, harus di-equip ulang

---

## 2026-10-18 15:47 +07:00 — InstantFell dan log buatan ditolak server

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : a8261516-da5f-4792-b082-6c39d1939868

### Perubahan
- Tidak ada kode jadi. Hanya investigasi.

### Alasan
- Captain minta akal-akalan agar pohon langka (minigame cepat) tidak meleset.

### Bukti
- `InstantChopConfig.Allows(plr)` = `false`. `Usernames` hanya berisi
  `Awesominat` (developer).
- `TreeService:InstantFell()` dijawab `{Ok=false, Reason="Instant chops are off"}`.
- Mengirim log `ChopStrike` buatan lalu `FinishChop` dijawab
  `"That chop didn't go through"`.
- Data Secret `MoonwellBaobab`: `Speed 2.4`, `Approach 0.3874`,
  `Perfect 0.0277` → jendela perfect hanya **21,45 ms**, `Needed 46`,
  `Recover 0.02`.

---

## 2026-10-18 16:05 +07:00 — FPS HP vs PC terukur

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134

### Perubahan
- Tidak ada kode jadi. Pengukuran.

### Alasan
- Captain merasa HP lebih lancar dan menduga ada fitur lain yang nabrak.

### Bukti
- PC: **19,3 FPS**, rata-rata frame 51,5 ms, terburuk 352 ms.
- HP: **57 FPS**, rata-rata frame 17,5 ms, jitter 1% (2 dari 171 frame >33ms),
  terburuk 128 ms.
- Callback sendiri murah: 23 koneksi RenderStepped total 0,4 ms; 62 Heartbeat
  total 0,48 ms.
- Semua spike terjadi saat `sniping=true`. Terberat 152,5 ms tepat saat sniping
  berubah `true→false` (momen respawn).

---

## 2026-10-18 16:20 +07:00 — konektor HP diperbaiki

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134

### Perubahan
- Menulis `CONNECTOR_PHONE.md`, `connector_phone.luau`, `connector_pc.luau`.

### Alasan
- Konektor asli menembak `localhost:16384`, yang di HP berarti HP itu sendiri.

### Bukti
- `/script.luau` di bridge menjawab 200 lewat localhost maupun IP LAN,
  64764 bytes — dan **beda** dari `connector.luau` di disk (64768). Bridge
  menyajikan build-nya sendiri.
- Konektor baris 2980: cek `MCP_Loaded`, set, **baru** baca `BridgeURL`. Jadi
  nilai yang di-set lebih dulu menang.
- Cara yang disarankan Captain (lebih baik dari file statis):
  `getgenv().BridgeURL = "<ip>:16384"` lalu loop `HttpGet .../script.luau`
  sampai `getgenv().MCP_Loaded` true.

---

## 2026-10-18 16:29 +07:00 — merchant scan dioptimasi

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134

### Perubahan
- `esp_merchants_loop` dan `nearest_merchant` tidak lagi men-scan seluruh
  workspace; sekarang hanya `Map.NPCs` + `Map.Wanderer`.

### Alasan
- Hitch periodik di HP. Tersangka: scan workspace tiap timer.

### Bukti
- `workspace.Map:GetDescendants()` = 19.587 instance, **13 ms** per panggilan.
- Scan billboard di atasnya = 9,98 ms.
- Sebelum perbaikan: 10 spike dalam 10 detik, terburuk 152 ms.
- Sesudah perbaikan: belum diukur ulang (client putus).

---

## 2026-10-18 16:40 +07:00 — Prospector's Axe dibeli

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : 3e45aba1-c838-4f97-aa20-97f5febbc10a

### Perubahan
- Respawn-TP ke pedagang Timber (478 stud) lalu ke pedagang Prospector
  (1.455 stud).
- Membeli Prospector's Axe $900.000 dan equip.

### Alasan
- Captain ingin upgrade kapak untuk Secret tree.
- Timber Axe **terkunci level 190**, Captain masih 125. Prospector's adalah yang
  tertinggi yang req-nya terpenuhi (lvl 125 persis).

### Bukti
- `AxeConfig` menyebut Prospector power 2, tapi runtime melaporkan
  **power 2.8, speed 2.40, luck 1.90**. Driftwood sebelumnya power 2, luck 1.00.
- Sisa Bucks setelah beli: $2.551.907.

---

## 2026-10-18 16:49 +07:00 — tuple asli client tertangkap

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : a8261516-da5f-4792-b082-6c39d1939868

### Perubahan
- Menulis `INSTANT_CHOP.md`.
- Membungkus `TreeService.ChopStrike.Fire` dan `TreeService.FinishChop` untuk
  merekam argumen asli saat chop sungguhan.

### Alasan
- Log buatan terus ditolak; perlu tahu persis apa yang dikirim client asli.

### Bukti
- `ChopStrike(tree, elapsed, wallSinceOpen)` — dua angka berpasangan, selisih
  beberapa ms:
  `1.1630274960771203 | 1.1575013010005932`
- `FinishChop(tree, true, false, log46)` — **arg3 = `false`**. Client asli tidak
  pernah mengklaim perfect.
- Dua kesalahan di percobaan kita: kirim arg3=`true`, dan `wallSinceOpen`
  dihitung dari mulai loop (bukan dari `StartChop`), meleset ~800 ms.
- `NotchRules.MaxStep = 0.05` — simulasi maju maksimal 50 ms per frame. Di PC
  (frame 69–110 ms) jam simulasi tertinggal dari jam dinding tanpa batas.
- Rencana 45 strike lolos `Replay`: `felled=true`, `perfect=true`,
  `fellAt=13.98`. `MinDuration = 6,64 s`.

---

## 2026-10-18 16:52 +07:00 — pohon Secret dapat, TAPI lewat minigame

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : a8261516-da5f-4792-b082-6c39d1939868

### Perubahan
- Captain melaporkan pohon Secret didapat.

### Alasan
-

### Bukti
- **Koreksi penting:** Captain mengonfirmasi minigame **tetap muncul**, jadi
  bukan instan. Pohonnya dapat, tapi lewat jalur minigame, bukan replay log.
- Awalnya gue catat "instant chop worked". Itu **salah** dan sudah diperbaiki
  di entri ini.
- Tidak bisa diverifikasi langsung: konektor putus, log Roblox terbaru
  (16:11) lebih tua dari percobaan.
- Pelajaran: jangan menyimpulkan "berhasil" dari hasil akhir sebelum memastikan
  jalurnya. Pohonnya jatuh ≠ replay log diterima.

---

## 2026-10-18 16:55:27 +07:00 — rules.md dan history.md dibuat

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134

### Perubahan
- Menambah `rules.md`: aturan pencatatan.
- Menambah `history.md`: file ini.
- Memperbaiki `INSTANT_CHOP.md` yang sebelumnya salah menyatakan instant chop
  berhasil.

### Alasan
- Captain: "tambahin 2 file di folder ini... buat assist developing aja sih
  misalnya gw ganti ganti ide atau ganti ganti ai".
- Supaya ide yang berganti-ganti dan pergantian AI tidak menghilangkan jejak
  keputusan.

### Bukti
- Dua file dibuat. Riwayat di atas direkonstruksi dari dokumen topik, pesan
  Captain, dan hasil tool sepanjang sesi.
- Bagian sebelum 16:55 ditulis setelah kejadian, jadi jamnya perkiraan kecuali
  yang punya cap waktu log Roblox (disconnect 285).

---

## Status terbuka per 2026-10-18 16:55 +07:00

Belum selesai:

1. **Instant chop belum jalan.** Replay log selalu ditolak. Dua koreksi sudah
   teridentifikasi (arg3=`false`, `wallSinceOpen` dari `StartChop`) tapi belum
   pernah dites. Perlu isolasi dulu: tes arg3=`false` dengan jam dinding lama.
2. **`MinDuration` adalah batas keras** (6,64 s untuk Secret). Tidak ada chop
   yang benar-benar instan; yang bisa dihilangkan hanya kesulitan minigame.
3. **Optimasi merchant belum diukur ulang** setelah perbaikan 16:29.
4. **Jitter di HP belum hilang terverifikasi.**
5. **Axe berikutnya terkunci level**, bukan uang:
   Thunderhead lvl 140, Collector's lvl 165, Timber lvl 190.

Catatan lingkungan:

- IP LAN PC: `192.168.0.132`
- Konektor HP: `getgenv().BridgeURL`, lalu `HttpGet .../script.luau`
- Reset `getgenv().MCP_Loaded = nil` sebelum menyambung ulang
- GUI hub: `CoreGui.RobloxGui["Blizzard Hub"]`

---

## 2026-10-18 17:17:23 +07:00 — bike TP: celah ditemukan, thrust ekstrem masih gagal

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : 7a6319da-4785-44a7-9556-5da63e8ff7df

### Perubahan
- Investigasi metode TP baru lewat bike (ide Captain).
- Tidak ada kode hub yang diubah.

### Alasan
- Captain ingin TP yang diterima server, memanfaatkan animasi naik bike.

### Bukti — yang berhasil
- `BikeConfig` ada; `MountainBike`: MaxSpeed 28, Accel 18, WheelRadius 1.38,
  SpawnCooldown 3, IdleSeconds 60.
- `BikeService` punya `Spawn`, `Ride`, `PutAway`.
- `BikeService:Spawn()` (tanpa argumen) yang benar-benar memunculkan model;
  `Spawn("MountainBike")` juga mengembalikan true tapi tidak selalu menghasilkan
  model baru, jadi hasilnya harus diverifikasi lewat set difference pada
  `workspace.Bikes`, bukan dari nilai return.
- Bike muncul di `Workspace.Bikes` dengan nama `<NamaPlayer>Bike`, punya atribut
  `Owner`, `BikeId`, `Token`, `Ridden`.
- `seat:Sit(hum)` berhasil: `seat.Occupant == hum`, `Humanoid.Sit == true`,
  karakter menempel 2 stud dari chassis.
- **PivotTo pada bike saat dinaiki DITOLAK** — bike balik ke posisi semula
  dalam 0,2 detik, karakter tetap di tempat. Server memegang otoritas.
- **AssemblyLinearVelocity pada chassis BERHASIL** — satu impuls 900 stud/s
  membuat bike + penunggang bergerak bersama: jarak ke target 86 → 69 stud,
  `stillSeated = true`, `gapToBike = 2`. Ini jalur yang hidup.

### Bukti — yang gagal
- Thrust berkelanjutan 1200 stud/s selama 0,6 detik → koneksi putus.
- Log: `Disconnected from server for reason: Player: 285
  (DisconnectClientInitiated)` — **kode yang sama** dengan disconnect yang sudah
  dilacak di SOAK_TEST_LOG.md, bukan `Banned`, bukan pesan kick.
- Belum bisa dipastikan apakah thrust-nya penyebab, karena 285 juga muncul tanpa
  aktivitas apa pun sebelumnya. Perlu tes ulang dengan thrust lebih kecil.

### Kesimpulan
- Celah bike itu **nyata**: penunggang ikut saat chassis digerakkan dengan
  kecepatan, tanpa snapback.
- Masalahnya cuma besaran. 900 stud/s sesaat = bergerak. 1200 stud/s selama 0,6
  detik = putus.
- Langkah berikutnya: cari besaran aman. Mulai dari impuls tunggal ~200–400
  stud/s, berulang tiap frame hanya bila perlu, dan hentikan thrust begitu
  jarak < 10 stud.

### Catatan
- Jangan pakai `PivotTo` untuk bike; server menolaknya.
- Jangan simpan referensi model bike — model diganti/dihapus saat respawn.
  Cari ulang lewat set difference pada `workspace.Bikes`.
