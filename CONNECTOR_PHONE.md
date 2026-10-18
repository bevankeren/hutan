# Connector untuk HP (Android)

Konektor MCP default-nya menembak `localhost:16384`. Di HP, `localhost` itu HP-nya
sendiri, bukan PC — jadi konektor versi PC tidak akan pernah nyambung dari Android.

Versi HP di repo ini sudah diubah supaya menembak **IP LAN PC**:

```
192.168.0.132:16384
```

---

## Syarat

1. HP dan PC di **jaringan Wi-Fi yang sama**.
2. PC menyala dan MCP bridge jalan (port 16384 listen).
3. Firewall PC mengizinkan inbound 16384 — sudah ada rule `roblox-mcp bridge 16384`.
4. IP PC tidak berubah. Kalau router kasih IP baru, konektor harus di-replace lagi.

Cek IP PC sekarang:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\.254" } |
  Select-Object IPAddress, InterfaceAlias
```

Kalau IP-nya berubah, edit `connector_phone.luau` dan ganti `192.168.0.132:16384`
sesuai IP baru.

---

## Cara pakai di HP

1. Buka `connector_phone.luau` dari repo, copy **seluruh isinya** (64 KB).
2. Buka executor di HP (Delta, Codex, Arceus X, Fluxus, atau apa pun yang support
   `HttpGet` dan `setclipboard`).
3. Inject ke Roblox, lalu tempel dan jalankan isi file itu.

Kalau executor HP tidak nyaman menempel 64 KB, pakai host yang bisa diakses HP:

```lua
loadstring(game:HttpGet("http://192.168.0.132:8791/connector_phone.luau"))()
```

Itu memakai HTTP server lokal yang sudah jalan di port 8791. Pastikan server itu hidup:

```powershell
cd "C:\Users\bevan\OneDrive\Documents\ChatGPT\foresters"
python -m http.server 8791 --bind 0.0.0.0
```

Perhatikan `--bind 0.0.0.0`, bukan `127.0.0.1` — kalau bind ke localhost, HP tidak
bisa mengaksesnya.

---

## Verifikasi

Setelah dijalankan, dari PC cek:

```
list-clients
```

Kalau HP-nya nyambung, akan muncul dua client: satu PC, satu HP. Bedakan dari
username dan platform:

```
<id-pc>     | GaringKriuks @ Foresters ... (desktop)
<id-hp>     | <nama> @ Foresters ...      (mobile)
```

Setelah itu setiap tool MCP bisa diarahkan ke HP dengan `set-active-client`, atau
per-call lewat parameter `clientId`.

---

## Kalau gagal nyambung

| Gejala | Penyebab | Perbaikan |
|---|---|---|
| `list-clients` kosong | HP tidak sampai ke bridge | tes buka `http://192.168.0.132:16384/health` dari browser HP — harus muncul `MCP Server Running` |
| Browser HP timeout | firewall | cek rule `roblox-mcp bridge 16384`, atau matikan firewall sementara untuk tes |
| Browser HP jalan tapi executor gagal | executor memblokir HTTP non-HTTPS | pakai executor lain, atau tempel file langsung |
| Dulu nyambung, sekarang tidak | IP PC berubah | cek IP lagi, replace di `connector_phone.luau` |
| Nyambung lalu putus | Wi-Fi PC sleep / pindah jaringan | set PC agar tidak sleep, pastikan satu SSID |

---

## Catatan

`connector_pc.luau` tetap memakai `localhost:16384` dan **jangan** dipakai di HP.
Kalau ketuker, konektor akan mencari bridge di HP sendiri dan tidak ketemu.

File ini dibuat dengan mengganti satu string default di `connector.luau` asli dari
`C:\Users\bevan\Downloads\roblox-executor-mcp\connector.luau`. Tidak ada logika lain
yang diubah, jadi perilakunya identik dengan versi PC selain alamat tujuan.
