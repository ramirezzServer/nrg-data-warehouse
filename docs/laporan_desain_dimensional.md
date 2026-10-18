# Laporan Tugas Kelompok 1 — Pengembangan Data Warehouse Nusantara Retail Group (NRG)

**Anggota:**

| Nama | NIM |
|---|---|
| Djaudza Djiyya Muhammad | 102022400133 |
| Faris Yahya Ayyash Alfatih | 102022400029 |
| Figo Al Ghifari | 102022400302 |
| Muhammad Nabeel Ghifari | 102022400114 |

**Tools:** Pentaho Data Integration (Spoon) · MySQL 8

**Status dokumen:** selesai. Seluruh desain dimensional, pipeline ETL (`t_01`–`t_09`), Job orkestrasi (`j_00_main_nrg_dw.kjb`), validasi rekonsiliasi (`02_validasi_etl.sql`), dan kueri pembuktian bisnis (`03_kueri_pembuktian.sql`) telah selesai dijalankan dan diverifikasi.

---

## 1. Pendahuluan

NRG menjual elektronik, furnitur, dan pakaian lewat tiga kanal (42 toko fisik, situs web resmi, dua marketplace) yang berjalan di lima sistem terpisah. Laporan lintas kanal selama ini dirakit manual di Excel (± 3 hari kerja per siklus). Kelompok membangun data warehouse berbasis **satu tabel fakta** untuk menjawab empat pertanyaan Direktur Penjualan:

1. Margin kotor per sub-kategori per kanal dibandingkan kuartal yang sama tahun lalu.
2. Apakah pelanggan online sama dengan pemegang kartu member toko.
3. Kampanye diskon yang menaikkan volume tanpa menggerus margin.
4. Produk yang laris di marketplace tetapi lemah di toko & web (kandidat realokasi stok).

## 2. Profil sumber data dan temuan kualitas data

| Kode | Bentuk | Volume | Temuan & penanganan |
|---|---|---|---|
| S1 ECOM_DB | MySQL (11 tabel) | 3.001 order, 4.540 item | `unit_price` & `disc_amount` termasuk PPN 11% → dibagi 1,11 · 194 order DIBATALKAN (304 item) dibuang · 144 pelanggan punya 2 alamat → pakai `is_primary = 1` · ORD-9999 memakai `SKU-NEWARR-001` yang belum ada di S4 → *inferred member* · 106 item retur ditandai `is_retur` |
| S2 POS_TOKO | 42 × 3 CSV `;` + 4 master | 6.000 header, 8.628 line, 6.693 payment | Tanggal `dd/MM/yyyy` · 175 transaksi VOID (242 line) dibuang · harga sudah tanpa PPN, diskon dalam % → dikonversi ke Rupiah · 885 transaksi SPLIT (>1 baris payment) → tabel payment tidak di-join ke fakta · 2.693 transaksi tanpa member → pelanggan `-1` · nomor HP member tidak seragam (`08…`, `8…`) · kota member memakai alias (`BDG`, `Jaksel`, `MKS`) |
| S3 MPL_API | 16 JSON berpaginasi, bersarang | 1.530 record invoice, 1.831 item | `paid_at` UTC → +7 jam (522 item berpindah tanggal) · `price` & `voucher` termasuk PPN → /1,11 · 30 invoice terduplikasi (34 item) → dedup (invoice, seller_sku) ambil `diambil_pada` terakhir → 1.500 invoice / 1.797 item · fee per invoice → dialokasikan proporsional · `buyer.hash` anonim; 1 hash bisa punya beberapa kota → ambil kota invoice terakhir |
| S4 ERP_MASTER | CSV | 79 baris, 60 material, 10 supplier | Riwayat: 18 material punya > 1 versi (14 karena revisi harga pokok, 5 karena status berubah jadi NONAKTIF) → SCD tipe 2 atas harga_pokok & status · `stok_harian_feb2023` tidak dimodelkan (sampel 10 toko) |
| S5 MKT_SHEET | CSV manual | 19 baris | 1 baris kosong · kode promo tidak konsisten (`newyear10 `) · 2 duplikat persis setelah dibersihkan · `target_diskon_persen = "sepuluh"` → `err_kampanye` · hasil: 15 kampanye valid |
| ref_kota | CSV | 26 alias | Membakukan kota di dim_kanal dan dim_pelanggan (kota supplier S4 sudah baku) |

**Pemetaan produk lintas kanal** (semua menuju `material_no` S4):
- S1 `sku` `SKU-1038-461` → regex `^SKU-(\d{4})-\d+$` → `P-1038` (diverifikasi: 60 nama produk identik dengan S4).
- S2 `item_code` sudah sama dengan `material_no`.
- S3 `seller_sku` `SAMSUN1005` → 4 digit terakhir → `P-1005`.

Hasilnya disimpan di tabel `map_produk` (181 baris).

## 3. Desain dimensional

### 3.1 Proses bisnis dan matriks bus

Proses bisnis: **penjualan item lintas kanal**.

| Dimensi → / Sumber ↓ | Tanggal | Produk | Pelanggan | Kanal | Promo |
|---|---|---|---|---|---|
| S1 order line | ✓ | ✓ (via map) | ✓ customer | ✓ WEB | ✓ voucher |
| S2 trx line | ✓ | ✓ | ✓ member / -1 | ✓ toko | ✓ periode kampanye |
| S3 invoice item | ✓ (WIB) | ✓ (via map) | ✓ hash | ✓ MPL A/B | ✓ periode kampanye |

### 3.2 Skema bintang

![Star schema](star_schema.png)

| Tabel | Jenis | Natural key | Keterangan |
|---|---|---|---|
| fact_penjualan | Fakta transaksi | (sumber_sistem, no_transaksi, no_baris) | 14.419 baris (4.236 S1 + 8.386 S2 + 1.797 S3) |
| dim_tanggal | Dimensi | tanggal | 730 hari (2022–2023), atribut kuartal untuk YoY |
| dim_produk | Dimensi SCD2 | material_no + berlaku_mulai | 79 versi + 1 inferred; harga pokok per versi; supplier di-*denormalisasi* ke dalam dimensi |
| dim_pelanggan | Dimensi *conformed* | pelanggan_nk (`HP:…` / `MPL:…`) | menyatukan web + member; flag `is_pelanggan_web`, `is_member_toko`, `segmen_identitas` |
| dim_kanal | Dimensi | kanal_kode | 42 toko + WEB + MPL_A + MPL_B; hierarki kanal → sub_kanal |
| dim_promo | Dimensi | kode_promo + tgl_mulai | 15 kampanye + `-1 Tanpa Promo` + `-2 Diskon Tanpa Kampanye Valid` |

Tabel pendukung (bukan bagian star schema): `map_produk` (pemetaan produk), `err_kampanye` (baris S5 gagal validasi).

### 3.3 Grain dan aturan perhitungan

**Grain:** satu baris per item transaksi — order line (S1), trx line (S2), invoice item (S3).

| Measure | S1 Situs Web | S2 Toko Fisik | S3 Marketplace |
|---|---|---|---|
| `harga_satuan` | ROUND(unit_price / 1,11; 2) | unit_price_excl | ROUND(price / 1,11; 2) |
| `penjualan_kotor` | ROUND(qty × unit_price / 1,11; 2) | qty × unit_price_excl | ROUND(qty × price / 1,11; 2) |
| `diskon` | ROUND(disc_amount / 1,11; 2) | ROUND(kotor × disc_pct / 100; 2) | ROUND(voucher / 1,11; 2) |
| `penjualan_bersih` | kotor − diskon | kotor − diskon | kotor − diskon |
| `hpp` | qty × harga_pokok versi berlaku | idem | idem |
| `fee_marketplace` | 0 | 0 | (commission + service) × porsi baris |
| `margin_kotor` | bersih − hpp − fee | bersih − hpp − fee | bersih − hpp − fee |
| `waktu_transaksi_wib` | order_ts (sudah WIB) | trx_date 00:00 | paid_at UTC + 7 jam |

**Versi harga pokok:** baris S4 dengan `berlaku_sejak` terbesar yang ≤ tanggal transaksi. Diwujudkan dengan `berlaku_mulai = berlaku_sejak`, `berlaku_sampai = berlaku_sejak versi berikutnya − 1 hari` (versi terakhir 9999-12-31), lalu lookup `berlaku_mulai ≤ tanggal ≤ berlaku_sampai`.

**Alokasi fee marketplace:**
`porsi_baris = (price × qty − voucher) / Σ(price × qty − voucher) per invoice`
`fee_marketplace = ROUND((commission + service) × porsi_baris; 2)`
Total fee dari 1.500 invoice unik adalah Rp1.276.197.059; jumlah fee teralokasi di tabel fakta sama persis dengan angka ini.

**Atribusi promo:**
- S1: `orders.voucher_id → vouchers(promo_code, valid_from) → dim_promo(kode_promo, tgl_mulai)`. Tanpa voucher → -1. Voucher tidak ada di dim_promo (GAJIAN25 periode 28-06-2022 yang ditolak validasi) → -2.
- S2/S3 (tidak menyimpan kode promo): jika diskon > 0, cari kampanye yang aktif pada tanggal transaksi untuk kanal tersebut; prioritas kampanye khusus kanal, lalu "Semua Kanal"; jika beberapa aktif, ambil `tgl_mulai` terbaru. Diskon = 0 → -1; diskon > 0 tanpa kampanye aktif → -2.

**Pencocokan pelanggan (Pertanyaan 2):** nomor HP dinormalkan (hapus non-digit, hapus awalan `62` atau `0`): `+6281234834227` → `81234834227`, `082028366541` / `82028366541` → `82028366541`. S1 ↔ S2 di-*full outer join* pada HP normal.

### 3.4 Peta source-to-target

Peta lengkap 153 baris (semua kolom S1–S5 + ref_kota, termasuk kolom yang sengaja tidak dimuat beserta alasannya) ada di `source_to_target_mapping.csv` / `.md`. Ringkasan:

| Target | Sumber utama | Transformation |
|---|---|---|
| dim_tanggal | dibangkitkan (Generate rows) | t_01 |
| dim_kanal | S2 store_master + 3 baris statis + ref_kota | t_02 |
| dim_promo, err_kampanye | S5 | t_03 |
| dim_produk | S4 produk_master + supplier_master + S1 products (inferred) | t_04 |
| map_produk | S1 products, S2 product_master_local, S3 seller_sku | t_05 |
| dim_pelanggan | S1 customers + addresses, S2 member, S3 buyer | t_06 |
| fact_penjualan | S1 / S2 / S3 | t_07 / t_08 / t_09 |

## 4. Pipeline ETL di Pentaho

Setiap transformation memakai variabel `${NRG_DATA_DIR}` dan koneksi `nrg_ecom_src` / `nrg_dw`.

| Transformation | Step kunci | Status |
|---|---|---|
| t_01_dim_tanggal | Generate rows, Add sequence, Calculator (Date A + B days), User Defined Java Expression, Select values, Table output | Selesai |
| t_02_dim_kanal | Text file input ×2, String operations, Sort rows, Stream lookup (ref_kota), User Defined Java Expression, Data grid (3 kanal online), Add constants, Select values, Table output ×2 | Selesai |
| t_03_dim_promo | Text file input, Filter rows, String operations, Sort rows (unique), Data validator + error handling, Select values, Table output ×2 (`dim_promo`, `err_kampanye`) | Selesai |
| t_04_dim_produk | Text file input ×2, Sort rows, Analytic query (LEAD), User Defined Java Expression, If field value is null, Stream lookup, Table input (S1), Regex evaluation, Filter rows, Table output ×2 | Selesai |
| t_05_map_produk | Table input (S1), Regex evaluation, Text file input (S2), JSON input (S3), User Defined Java Expression, Sort rows, Stream lookup, Table output ×3 | Selesai |
| t_06_dim_pelanggan | Table input, Text file input ×2, Replace in string, String operations, Merge join (FULL OUTER), User Defined Java Expression, JSON input, Sort rows, Unique rows, Stream lookup, Table output ×2 | Selesai |
| t_07_fact_web | Table input, Filter rows, Database lookup ×7, Calculator, User Defined Java Expression (`kunci_dan_flag`), Table output | Selesai |
| t_08_fact_toko | Text file input ×2 (wildcard 42 file), Stream lookup, Filter rows, Database lookup ×6, Calculator, User Defined Java Expression (`kunci_dan_flag`), Table output | Selesai |
| t_09_fact_marketplace | JSON input ×2, Sort rows, Unique rows, Group by, Stream lookup, Calculator, Value mapper, Database lookup ×6, User Defined Java Expression (`kunci_dan_flag`), Table output | Selesai |

Job utama `j_00_main_nrg_dw.kjb` (**Selesai**): `START → buat_ulang_dw → t_01 → t_02 → t_03 → t_04 → t_05 → t_06 → t_07 → t_08 → t_09 → Success`. Entry `buat_ulang_dw` menjalankan `sql/01_ddl_dw.sql` sehingga `nrg_dw` dibuat ulang dari kosong setiap kali Job dijalankan.

## 5. Hasil validasi ETL

Seluruh pemeriksaan pada `sql/02_validasi_etl.sql` telah dijalankan setelah eksekusi penuh `j_00_main_nrg_dw.kjb` dengan hasil **100% sesuai target**:

| Cek | Aktual | Harapan | Status |
|---|---|---|---|
| `dim_tanggal` / `dim_kanal` / `dim_promo` | 730 / 45 / 17 baris | 730 / 45 / 17 baris | ✓ Sesuai |
| `err_kampanye` (baris S5 ditolak validasi) | 1 baris (`GAJIAN25`, `"sepuluh"`) | 1 baris | ✓ Sesuai |
| `dim_produk` (79 versi S4 + 1 inferred + 1 default) | 81 baris | 81 baris | ✓ Sesuai |
| `map_produk` (61 S1 + 60 S2 + 60 S3) | 181 baris | 181 baris | ✓ Sesuai |
| `dim_pelanggan` (400 web saja, 400 member saja, 200 irisan, 556 MPL, 1 default) | 1.557 baris | 1.557 baris | ✓ Sesuai |
| `fact_penjualan` S1 (Situs Web) | 4.236 baris | 4.236 baris | ✓ Sesuai |
| `fact_penjualan` S2 (Toko Fisik) | 8.386 baris | 8.386 baris | ✓ Sesuai |
| `fact_penjualan` S3 (Marketplace) | 1.797 baris | 1.797 baris | ✓ Sesuai |
| Total `fact_penjualan` | 14.419 baris | 14.419 baris | ✓ Sesuai |
| Duplikat grain `(sumber_sistem, no_transaksi, no_baris)` | 0 | 0 | ✓ Sesuai |
| Baris `DIBATALKAN` (S1) atau `VOID` (S2) yang bocor ke fakta | 0 | 0 | ✓ Sesuai |
| Produk gagal lookup (`produk_key = -1`) | 0 | 0 | ✓ Sesuai |
| `ORD-9999` → produk inferred (`SKU-NEWARR-001`) | 1 baris (`hpp` & `margin_kotor` NULL) | 1 baris | ✓ Sesuai |
| Total `fee_marketplace` S3 teralokasi vs total fee 1.500 invoice unik | Rp1.276.197.059,00 | Rp1.276.197.059,00 | ✓ Sesuai |
| Distribusi promo S1 (`Tanpa Promo` / `Tanpa Kampanye Valid` / `Kampanye Teridentifikasi`) | 2.741 / 86 / 1.409 | 2.741 / 86 / 1.409 | ✓ Sesuai |
| Distribusi promo S2 (`Tanpa Promo` / `Tanpa Kampanye Valid` / `Kampanye Teridentifikasi`) | 5.076 / 1.742 / 1.568 | 5.076 / 1.742 / 1.568 | ✓ Sesuai |
| Distribusi promo S3 (`Tanpa Promo` / `Tanpa Kampanye Valid` / `Kampanye Teridentifikasi`) | 900 / 649 / 248 | 900 / 649 / 248 | ✓ Sesuai |
| Ketidakkonsistensi rumus `penjualan_bersih − hpp − fee_marketplace = margin_kotor` | 0 baris | 0 baris | ✓ Sesuai |

## 6. Hasil kueri pembuktian (Q1–Q4)

Keempat kueri pembuktian di `sql/03_kueri_pembuktian.sql` telah dijalankan di atas `nrg_dw` untuk menjawab empat pertanyaan bisnis Direktur Penjualan:

### 6.1 Pertanyaan 1 (Q1) — Margin Kotor per Sub-Kategori per Kanal vs Kuartal yang Sama Tahun Lalu (YoY)

Perbandingan kuartal penuh YoY dilakukan antara **2023-Q1** dan **2022-Q1** (karena data transaksi 2023 berakhir pada April 2023 sehingga Q1 adalah satu-satunya kuartal penuh yang dapat dibandingkan *apple-to-apple* secara YoY):

| Kuartal | Kategori | Sub-Kategori | Kanal | Penjualan Bersih (Rp) | Margin Kotor 2023-Q1 (Rp) | Margin % 2023-Q1 | Margin Kotor 2022-Q1 (Rp) | Margin % 2022-Q1 | Pertumbuhan Margin YoY (%) |
|---|---|---|---|---:|---:|---:|---:|---:|---:|
| 2023-Q1 | Elektronik | Aksesoris Elektronik | Marketplace | 430.117.451 | 75.607.504 | 17,58% | 64.985.673 | 16,97% | +16,34% |
| 2023-Q1 | Elektronik | Aksesoris Elektronik | Situs Web | 1.341.176.254 | 316.427.207 | 23,59% | 277.827.618 | 22,98% | +13,89% |
| 2023-Q1 | Elektronik | Aksesoris Elektronik | Toko Fisik | 2.452.559.500 | 586.368.178 | 23,91% | 506.540.308 | 22,94% | +15,76% |
| 2023-Q1 | Elektronik | Laptop | Marketplace | 96.415.000 | 16.543.537 | 17,16% | 20.753.705 | 19,24% | -20,29% |
| 2023-Q1 | Elektronik | Laptop | Situs Web | 377.408.102 | 101.579.512 | 26,92% | 81.625.909 | 27,10% | +24,45% |
| 2023-Q1 | Elektronik | Laptop | Toko Fisik | 641.207.100 | 167.251.064 | 26,08% | 223.208.361 | 26,66% | -25,07% |
| 2023-Q1 | Elektronik | Smartphone | Marketplace | 238.521.803 | 24.702.738 | 10,36% | 36.344.721 | 8,40% | -32,03% |
| 2023-Q1 | Elektronik | Smartphone | Situs Web | 853.820.223 | 147.379.808 | 17,26% | 141.780.609 | 15,75% | +3,95% |
| 2023-Q1 | Elektronik | Smartphone | Toko Fisik | 1.548.233.800 | 271.854.079 | 17,56% | 275.828.236 | 14,88% | -1,44% |
| 2023-Q1 | Furnitur | Kursi | Marketplace | 718.171.103 | 73.561.091 | 10,24% | 58.526.734 | 9,25% | +25,69% |
| 2023-Q1 | Furnitur | Kursi | Situs Web | 1.954.761.452 | 327.936.377 | 16,78% | 235.221.718 | 16,91% | +39,42% |
| 2023-Q1 | Furnitur | Kursi | Toko Fisik | 2.893.781.050 | 487.127.195 | 16,83% | 459.352.469 | 17,29% | +6,05% |
| 2023-Q1 | Furnitur | Lemari | Marketplace | 669.207.202 | 110.336.482 | 16,49% | 141.446.912 | 17,57% | -21,99% |
| 2023-Q1 | Furnitur | Lemari | Situs Web | 1.186.522.402 | 274.953.149 | 23,17% | 246.749.815 | 20,91% | +11,43% |
| 2023-Q1 | Furnitur | Lemari | Toko Fisik | 2.653.761.500 | 599.855.655 | 22,60% | 431.014.716 | 22,68% | +39,17% |
| 2023-Q1 | Furnitur | Meja | Marketplace | 209.558.902 | 20.478.407 | 9,77% | 45.273.936 | 10,41% | -54,77% |
| 2023-Q1 | Furnitur | Meja | Situs Web | 634.687.151 | 109.629.653 | 17,27% | 125.243.231 | 16,98% | -12,47% |
| 2023-Q1 | Furnitur | Meja | Toko Fisik | 1.366.397.300 | 213.584.924 | 15,63% | 222.060.360 | 16,60% | -3,82% |
| 2023-Q1 | Pakaian | Atasan | Marketplace | 537.770.253 | 78.942.794 | 14,68% | 67.269.833 | 13,25% | +17,35% |
| 2023-Q1 | Pakaian | Atasan | Situs Web | 1.066.095.055 | 228.612.987 | 21,44% | 179.009.838 | 20,29% | +27,71% |
| 2023-Q1 | Pakaian | Atasan | Toko Fisik | 1.638.478.100 | 339.430.244 | 20,72% | 390.078.083 | 20,17% | -12,98% |
| 2023-Q1 | Pakaian | Bawahan | Marketplace | 203.681.500 | 28.316.061 | 13,90% | 32.935.700 | 12,85% | -14,03% |
| 2023-Q1 | Pakaian | Bawahan | Situs Web | 337.288.300 | 73.923.531 | 21,92% | 98.481.291 | 21,47% | -24,94% |
| 2023-Q1 | Pakaian | Bawahan | Toko Fisik | 710.991.700 | 152.547.870 | 21,46% | 137.207.901 | 21,88% | +11,18% |
| 2023-Q1 | Pakaian | Sepatu | Marketplace | 403.768.952 | 50.302.586 | 12,46% | 59.815.962 | 7,86% | -15,90% |
| 2023-Q1 | Pakaian | Sepatu | Situs Web | 1.813.342.405 | 292.558.527 | 16,13% | 406.077.338 | 18,38% | -27,95% |
| 2023-Q1 | Pakaian | Sepatu | Toko Fisik | 2.970.389.950 | 470.862.347 | 15,85% | 465.282.749 | 16,73% | +1,20% |

**Temuan utama Q1:**
- Persentase margin kotor di kanal **Marketplace** secara konsisten lebih rendah **6–9 poin persentase** dibandingkan Situs Web dan Toko Fisik pada sub-kategori yang sama (misal Meja di Marketplace hanya **9,77%** vs Situs Web **17,27%**), akibat potongan `commission` + `service` fee marketplace.
- Sub-kategori **Aksesoris Elektronik** dan **Kursi** tumbuh positif di ketiga kanal secara YoY pada 2023-Q1, sedangkan **Meja** mengalami penurunan margin YoY di seluruh kanal (terdalam di Marketplace **-54,77%**).

### 6.2 Pertanyaan 2 (Q2a & Q2b) — Irisan Pelanggan Situs Web vs Pemegang Kartu Member Toko

**Q2a — Proporsi di `dim_pelanggan` (pencocokan nomor HP yang dinormalkan):**

| Segmen Identitas | Jumlah Pelanggan | % dari Semua Pelanggan | % dari Pelanggan Web (600) |
|---|---:|---:|---:|
| `MARKETPLACE` (hash anonim) | 556 | 35,73% | 0,00% |
| `WEB_SAJA` | 400 | 25,71% | **66,67%** |
| `MEMBER_SAJA` | 400 | 25,71% | 0,00% |
| `WEB_DAN_MEMBER` (Omnichannel) | 200 | 12,85% | **33,33%** |

**Q2b — Kontribusi belanja per segmen di tiap kanal:**

| Segmen Identitas | Kanal Belanja | Pelanggan Aktif | Jumlah Transaksi | Penjualan Bersih (Rp) | Rata-rata Belanja per Pelanggan di Kanal (Rp) |
|---|---|---:|---:|---:|---:|
| `MEMBER_SAJA` | Toko Fisik | 399 | 2.119 | 30.561.710.900 | 76.595.767 |
| `WEB_DAN_MEMBER` | Situs Web | 198 | 905 | 15.561.879.837 | 78.595.353 |
| `WEB_DAN_MEMBER` | Toko Fisik | 200 | 1.086 | 16.464.164.450 | 82.320.822 |
| `WEB_SAJA` | Situs Web | 396 | 1.902 | 34.073.272.310 | 86.043.617 |

**Temuan utama Q2:**
- Dari 600 pelanggan terdaftar di Situs Web dan 600 member Toko Fisik, tepat **200 orang (33,33%) adalah orang yang sama** (`WEB_DAN_MEMBER`).
- Pelanggan omnichannel (`WEB_DAN_MEMBER`) berbelanja aktif di kedua kanal dengan total nilai gabungan **Rp32,03 miliar** (rata-rata **~Rp160,9 juta per pelanggan** jika kedua kanal digabung), hampir **2× lipat** nilai belanja pelanggan satu kanal (`MEMBER_SAJA` Rp76,6 juta; `WEB_SAJA` Rp86,0 juta).

### 6.3 Pertanyaan 3 (Q3) — Evaluasi Kampanye Diskon (Volume Harian vs Margin % terhadap Baseline 30 Hari Sebelum Kampanye)

Dari 27 evaluasi pasangan kampanye × kanal, **11 evaluasi dinyatakan `BERHASIL`** (menaikkan qty/hari sekaligus menjaga penurunan margin ≤ 1 poin persentase), **2 evaluasi menggerus margin**, dan **14 evaluasi tidak menaikkan volume**:

| Kode Promo | Nama Kampanye | Kanal Evaluasi | Periode | Qty/Hari Sebelum | Qty/Hari Kampanye | Uplift Volume (%) | Margin % Sebelum | Margin % Kampanye | Selisih Margin (poin) | Kesimpulan |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---|
| `BUNDLE2` | Beli 2 Diskon | Situs Web | 2022-10-06 s.d. 10-13 | 11,40 | 14,50 | **+27,19%** | 20,07% | 19,50% | -0,57 | **BERHASIL** |
| `BUNDLE2` | Beli 2 Diskon | Toko Fisik | 2022-10-06 s.d. 10-13 | 19,97 | 24,38 | **+22,08%** | 19,58% | 20,70% | +1,12 | **BERHASIL** |
| `HARBOLNAS` | Hari Belanja Online Nasional | Toko Fisik | 2022-02-16 s.d. 03-13 | 21,10 | 22,77 | +7,91% | 19,28% | 19,48% | +0,21 | **BERHASIL** |
| `WEEKEND20` | Diskon Akhir Pekan | Toko Fisik | 2022-12-07 s.d. 01-06 | 21,60 | 23,26 | +7,68% | 19,49% | 19,27% | -0,22 | **BERHASIL** |
| `IMLEK24` | Promo Imlek | Toko Fisik | 2022-09-18 s.d. 10-13 | 19,90 | 21,35 | +7,27% | 18,91% | 19,86% | +0,95 | **BERHASIL** |
| `MEMBER15` | Diskon Member | Toko Fisik | 2022-03-23 s.d. 04-08 | 21,30 | 22,71 | +6,60% | 19,46% | 19,70% | +0,24 | **BERHASIL** |
| `WEEKEND20` | Diskon Akhir Pekan | Situs Web | 2022-03-14 s.d. 04-12 | 12,27 | 13,07 | +6,52% | 19,17% | 19,74% | +0,56 | **BERHASIL** |
| `HARBOLNAS` | Hari Belanja Online Nasional | Situs Web | 2022-02-16 s.d. 03-13 | 11,63 | 12,31 | +5,80% | 19,36% | 19,09% | -0,27 | **BERHASIL** |
| `BUNDLE2` | Beli 2 Diskon | Situs Web | 2022-03-14 s.d. 04-04 | 12,27 | 12,95 | +5,61% | 19,17% | 19,95% | +0,78 | **BERHASIL** |
| `FLASH50` | Flash Sale Akhir Bulan | Toko Fisik | 2022-11-19 s.d. 12-11 | 22,53 | 23,61 | +4,77% | 19,65% | 19,30% | -0,35 | **BERHASIL** |
| `IMLEK24` | Promo Imlek | Situs Web | 2022-09-18 s.d. 10-13 | 12,10 | 12,27 | +1,40% | 19,34% | 20,20% | +0,86 | **BERHASIL** |
| `HARBOLNAS` | Hari Belanja Online Nasional | Marketplace | 2022-02-16 s.d. 03-13 | 5,93 | 6,50 | +9,55% | 12,84% | 11,35% | **-1,49** | Volume naik, margin tergerus |
| `BACKSCHOOL` | Promo Back to School | Marketplace | 2022-02-21 s.d. 03-22 | 5,70 | 5,93 | +4,09% | 13,08% | 11,97% | **-1,11** | Volume naik, margin tergerus |

*(14 evaluasi lainnya menunjukkan pertumbuhan volume negatif sehingga dikategorikan `Volume tidak naik`.)*

**Temuan utama Q3:**
- Kampanye **`BUNDLE2` (Beli 2 Diskon)** adalah kampanye paling efektif karena mendorong lonjakan volume tertinggi (**+27,19%** di Situs Web dan **+22,08%** di Toko Fisik) tanpa menggerus margin kotor.
- Di kanal **Marketplace**, tidak ada satu pun kampanye diskon yang masuk kategori `BERHASIL`: `HARBOLNAS` dan `BACKSCHOOL` memang menaikkan volume di Marketplace, namun menggerus margin lebih dari 1 poin persentase (turun ke ~11%) karena beban diskon bertumpuk dengan *fee* marketplace.

### 6.4 Pertanyaan 4 (Q4) — 10 Produk Laris di Marketplace tetapi Lemah di Toko & Web (Kandidat Realokasi Stok)

Karena volume total Toko Fisik + Situs Web (~15.968 unit) sekitar 6,3× volume Marketplace (~2.525 unit), perbandingan dilakukan menggunakan **rasio pangsa unit** (`pangsa_mpl_pct / pangsa_toko_web_pct`) agar adil:

| Peringkat | Material No | Nama Produk | Sub-Kategori | Qty Marketplace | Qty Toko + Web | Pangsa MPL (%) | Pangsa Toko+Web (%) | Rasio Pangsa (MPL vs Toko+Web) |
|---:|---|---|---|---:|---:|---:|---:|---:|
| 1 | `P-1019` | Samsung Smartphone Atque 128GB | Smartphone | 70 | 251 | 2,77% | 1,57% | **1,76×** |
| 2 | `P-1054` | Uniqlo Atasan Maxime | Atasan | 72 | 266 | 2,85% | 1,67% | **1,71×** |
| 3 | `P-1031` | Apple Laptop Pariatur | Laptop | 58 | 262 | 2,30% | 1,64% | **1,40×** |
| 4 | `P-1024` | Uniqlo Bawahan Aperiam 256GB | Bawahan | 52 | 237 | 2,06% | 1,48% | **1,39×** |
| 5 | `P-1045` | Erigo Atasan Cumque | Atasan | 52 | 244 | 2,06% | 1,53% | **1,35×** |
| 6 | `P-1049` | Olympic Lemari Sed 128GB | Lemari | 52 | 252 | 2,06% | 1,58% | **1,30×** |
| 7 | `P-1014` | Informa Meja Reiciendis | Meja | 51 | 250 | 2,02% | 1,57% | **1,29×** |
| 8 | `P-1015` | Informa Kursi Quaerat Lite | Kursi | 48 | 238 | 1,90% | 1,49% | **1,28×** |
| 9 | `P-1027` | IKEA Kursi Vero Series 2 | Kursi | 50 | 258 | 1,98% | 1,62% | **1,23×** |
| 10 | `P-1028` | Informa Kursi Ea Lite | Kursi | 50 | 262 | 1,98% | 1,64% | **1,21×** |

**Temuan utama Q4:**
- **`P-1019` (Samsung Smartphone Atque 128GB)** dan **`P-1054` (Uniqlo Atasan Maxime)** memiliki porsi permintaan di Marketplace hingga **1,76×** dan **1,71×** lebih tinggi dibandingkan porsinya di Toko Fisik & Situs Web, sehingga menjadi prioritas utama untuk realokasi *buffer stock* gudang marketplace.

## 7. Asumsi dan batasan

1. Waktu S1 dianggap sudah WIB. S2 hanya punya tanggal (tanpa jam); toko di Makassar & Denpasar berada di zona WITA, tetapi tanpa jam konversi tidak bisa dilakukan sehingga tanggal lokal dipakai apa adanya.
2. Fee marketplace dicatat sesuai nominal yang dipotong marketplace (tidak dibagi 1,11) karena merupakan biaya, bukan harga jual.
3. Ongkos kirim S1 tidak dimasukkan ke penjualan maupun margin (level order, bukan produk).
4. Retur hanya ditandai (`is_retur`); nilainya tidak mengurangi penjualan bersih.
5. Produk inferred (ORD-9999) belum punya harga pokok → `hpp` dan `margin_kotor` NULL sampai master S4 tersedia.
6. S2/S3 tidak menyimpan kode promo, sehingga atribusi kampanye memakai periode & kanal (pendekatan perkiraan). Voucher S1 banyak dipakai di luar periode `valid_from–valid_to`; tetap diatribusikan sesuai voucher yang tercatat di sistem.
7. `stok_harian_feb2023.csv` tidak dimodelkan (hanya 10 dari 42 toko).
8. Pembeli marketplace tidak dapat dipadankan ke pelanggan web/member.

## 8. Pembagian kerja

| Anggota | NIM | Kontribusi |
|---|---|---|
| Djaudza Djiyya Muhammad | 102022400133 | Desain dimensional dan dokumen |
| Faris Yahya Ayyash Alfatih | 102022400029 | ETL dimensi (t_01 – t_06) |
| Figo Al Ghifari | 102022400302 | ETL fakta (t_07 – t_09) dan Job |
| Muhammad Nabeel Ghifari | 102022400114 | Kueri pembuktian dan laporan |