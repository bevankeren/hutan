# Connector untuk HP (Android)

Cara paling ringkas — **tidak perlu file 64 KB, tidak perlu copy-paste**. Bridge MCP
sudah menyajikan konektornya sendiri di `/script.luau`, dan konektor itu membaca
`getgenv().BridgeURL` sebelum jatuh ke default `localhost`.

Jadi cukup set alamat PC **sebelum** load:

```lua
getgenv().BridgeURL = "192.168.0.132:16384"

while not getgenv().MCP_Loaded do
    pcall(function()
        loadstring(game:HttpGet("http://" .. getgenv().BridgeURL .. "/script.luau"))()
    end)
    task.wait(0.15)
end
```

Itu saja. Ganti `192.168.0.132` kalau IP PC berubah.

---

## Kenapa ini lebih baik daripada file statis

| | `/script.luau` | file `connector_phone.luau` |
|---|---|---|
| Ukuran yang harus ditempel | ~10 baris | 64 KB |
| Ikut update bridge | ya, otomatis | tidak, harus replace manual |
| Ganti IP | edit satu baris | edit satu string di file 64 KB |
| Butuh akses repo | tidak | ya |

Konektor dari bridge itu **byte-nya beda** dengan file yang ada di disk
(64764 vs 64768) — artinya bridge menyajikan versi build-nya sendiri, bukan copy
dari `connector.luau` di folder Downloads. Jadi memakai `/script.luau` selalu dapat
versi yang paling cocok dengan bridge yang sedang jalan.

---

## Cara kerjanya

Di baris 2980 konektor ada guard:

```lua
if getgenv().MCP_Loaded == true then
    return
end

getgenv().MCP_Loaded = true

local b = getgenv().BridgeURL or getgenv().bridgeurl or ... or "localhost:16384"
getgenv().BridgeURL = b
getgenv().bridgeurl = b
```

Urutannya penting: `MCP_Loaded` dicek dulu, lalu di-set, lalu `BridgeURL` dibaca.
Artinya kalau `getgenv().BridgeURL` sudah diisi sebelum load, nilai itu yang dipakai —
default `localhost` tidak pernah tersentuh.

Loop `while not getgenv().MCP_Loaded` juga berguna: kalau percobaan pertama gagal
(bridge belum siap, Wi-Fi baru nyambung), dia coba lagi tiap 150 ms sampai berhasil.

---

## Syarat

1. HP dan PC di **Wi-Fi yang sama**.
2. MCP bridge jalan di PC, port 16384 listen.
3. Firewall PC mengizinkan inbound 16384 — rule `roblox-mcp bridge 16384` sudah ada.

Cek IP PC:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notmatch "^127\." -and $_.IPAddress -notmatch "^169\.254" } |
  Select-Object IPAddress, InterfaceAlias
```

---

## Verifikasi

Dari browser HP, buka:

```
http://192.168.0.132:16384/health
```

Harus muncul `MCP Server Running`. Kalau ini gagal, executor juga akan gagal — betulkan
jaringan dulu.

Setelah konek, dari PC jalankan `list-clients`. Akan muncul dua entry; bedakan dari
platform dan username.

---

## Troubleshooting

| Gejala | Penyebab | Perbaikan |
|---|---|---|
| Browser HP timeout | beda Wi-Fi / firewall | pastikan satu SSID, cek rule firewall 16384 |
| Browser HP OK, executor gagal | executor blokir HTTP non-HTTPS | coba executor lain |
| Dulu jalan, sekarang tidak | IP PC berubah | cek IP, ganti satu baris `BridgeURL` |
| Loop tidak pernah selesai | `MCP_Loaded` sudah `true` dari sesi lama | `getgenv().MCP_Loaded = nil` lalu jalankan ulang |
| Nyambung lalu putus | PC sleep | set PC tidak sleep |

Baris terakhir itu penting: kalau konektor pernah jalan lalu mati, `MCP_Loaded` tetap
`true` dan guard akan langsung `return` tanpa menyambung ulang. Reset dulu:

```lua
getgenv().MCP_Loaded = nil
getgenv().MCP_ClientSessionId = nil
```
