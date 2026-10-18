# rules.md

Aturan kerja di folder ini. Berlaku untuk siapa pun yang mengerjakan — manusia
maupun AI. Tujuannya supaya ide yang berganti-ganti dan pergantian AI tidak
menghilangkan jejak keputusan.

---

## 1. Setiap perubahan WAJIB dicatat di `history.md`

Tidak ada pengecualian. Kalau kode, temuan, atau keputusan berubah, `history.md`
harus ikut berubah **pada kesempatan yang sama** — bukan nanti, bukan menyusul.

Yang dianggap perubahan:

- Sunting apa pun di `farm_hub.lua`, `blizzard_hub.lua`, atau file connector
- Menambah atau menghapus fitur, tombol, mode, slider
- Mengubah nilai default (kecepatan jalan, jumlah trial, dan sebagainya)
- Hasil tes — berhasil maupun gagal
- Temuan hasil reverse engineering, bahkan yang belum jadi kode
- Keputusan untuk **tidak** mengerjakan sesuatu, dan alasannya
- Perubahan rencana atau arah dari Captain

Ganti ide adalah hal normal. Yang tidak boleh normal adalah ide sebelumnya hilang
tanpa jejak.

---

## 2. Format entri `history.md`

Setiap entri memakai tanggal dan waktu **persis**, bukan "kemarin" atau "baru saja".

```
## 2026-10-18 16:55:27 +07:00 — judul singkat

Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
Job   : a8261516-da5f-4792-b082-6c39d1939868

### Perubahan
- apa yang diubah

### Alasan
- kenapa

### Bukti
- angka, hasil tes, log, atau tangkapan layar
- kalau belum diverifikasi, tulis "belum diverifikasi"
```

Aturan isi:

- **Tanggal** memakai `YYYY-MM-DD HH:mm:ss +07:00` (Asia/Jakarta).
- **Job ID** ditulis kalau entri itu menyangkut kejadian di server tertentu.
- **Bukti** harus berisi angka nyata bila ada pengukuran. Jangan tulis "jadi lebih
  cepat" — tulis "126ms jadi 10ms".
- Kalau hasilnya **gagal**, tulis gagal. Kegagalan yang tercatat mencegah
  pengulangan kerja yang sama.

---

## 3. Pisahkan yang terbukti dari yang belum

Di setiap catatan temuan, bedakan dengan tegas:

- **Terbukti** — ada pengukuran langsung, ada angka.
- **Dugaan** — terlihat masuk akal, belum dites.
- **Gagal** — sudah dicoba, tidak berhasil, dan bagaimana gagalnya.

Tulis "belum diverifikasi" bila memang belum. Jangan mengarang hasil. Bila
koneksi ke client putus di tengah tes, catat bahwa datanya hilang — jangan
menyimpulkan dari ingatan.

---

## 4. Catat versi game dan client

Foresters sering update dan bisa mengubah perilaku anticheat, nama remote, atau
parameter minigame. Karena itu setiap entri menyertakan:

```
Game  : Foresters 🌳 [RELEASE]
Place : 117020342702668
Client: 0.743.0.7431134
```

Kalau nanti ada temuan yang tiba-tiba tidak berlaku lagi, versi di entri lama
adalah hal pertama yang dicek.

---

## 5. Jangan hapus catatan lama

`history.md` itu tambah-terus, bukan tulis-ulang. Kalau sebuah keputusan
dibatalkan, **tambahkan entri baru** yang menyebut entri lamanya, jangan hapus
atau sunting entri lama.

Contoh:

```
## 2026-10-19 09:12:04 +07:00 — batalkan auto-hop

Membatalkan keputusan 2026-10-18 11:40:22 (auto-hop antar-server).
Alasan: ternyata memicu kick 285. Kode sudah dihapus.
```

Dengan begitu terlihat riwayat: pernah ada, kenapa ada, kenapa dibuang.

---

## 6. Dokumen temuan tidak menggantikan history

File seperti `INSTANT_CHOP.md`, `RESPAWN_TP_BYPASS.md`, `SOAK_TEST_LOG.md`, dan
`OUROBOROS_ANALYSIS.md` adalah **penjelasan mendalam** satu topik. `history.md`
adalah **garis waktu** seluruh proyek.

Saat ada temuan baru yang berarti:

1. Tulis detailnya di dokumen topik yang sesuai (atau buat baru).
2. Tambahkan entri di `history.md` yang menunjuk ke dokumen itu.

Jangan memilih salah satu. Dua-duanya.

---

## 7. Untuk AI yang masuk di tengah jalan

Kalau mengambil alih pekerjaan ini, urutan membacanya:

1. `history.md` — bagian **paling bawah dulu**, itu yang terbaru
2. `rules.md` — file ini
3. Dokumen topik yang disebut di entri terakhir

Hal-hal yang sering salah ditebak AI baru, jadi tulis jelas di history:

- IP LAN PC berubah-ubah; terakhir `192.168.0.132`
- Client HP menyambung lewat `getgenv().BridgeURL`, bukan `localhost`
- `getgenv().MCP_Loaded` harus di-nil-kan sebelum menyambung ulang
- GUI hub ada di `CoreGui.RobloxGui["Blizzard Hub"]`, bukan PlayerGui
- Batas 200 local di main chunk Luau; menambah terlalu banyak local bikin
  "Out of local registers"
- `NotchRules.MaxStep = 0.05` membuat jam simulasi tertinggal dari jam dinding
  saat frame lebih dari 50ms

---

## 8. Ringkas dan jujur

Entri bagus menjawab tiga hal: **apa yang berubah, kenapa, dan apa buktinya.**
Tidak perlu panjang, tapi tidak boleh mengaburkan kegagalan.

Kalau ragu antara menulis terlalu banyak atau terlalu sedikit — tulis lebih banyak.
Konteks yang hilang lebih mahal daripada catatan yang berlebihan.
