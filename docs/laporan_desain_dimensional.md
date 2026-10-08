# Laporan Tugas Kelompok 1 — Pengembangan Data Warehouse Nusantara Retail Group (NRG)

> **Draf.** Ganti nama kelompok/anggota, tambahkan screenshot dari Spoon dan hasil kueri dari laptop kalian, lalu ekspor ke PDF (`docs/laporan_desain_dimensional.pdf`).

**Kelompok:** … **Anggota:** … (NIM) · … (NIM) · … (NIM) · … (NIM)
**Tools:** Pentaho Data Integration (Spoon) … · MySQL 8 …

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
| fact_penjualan | Fakta transaksi | (sumber_sistem, no_transaksi, no_baris) | 14.419 baris |
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
Rekonsiliasi: Σ fee di fakta = Rp1.276.197.059 = Σ fee 1.500 invoice unik.

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

*(Tempel screenshot kanvas Spoon untuk setiap transformation dan Job di sini.)*

Job `j_00_main_nrg_dw.kjb`: `Start → SQL (01_ddl_dw.sql) → t_01 → t_02 → t_03 → t_04 → t_05 → t_06 → t_07 → t_08 → t_09 → Success`. Setiap transformation memakai variabel `${NRG_DATA_DIR}` dan koneksi `nrg_ecom_src` / `nrg_dw`.

| Transformation | Step kunci |
|---|---|
| t_01_dim_tanggal | Generate rows, Add sequence, Calculator (Date A + B days), Formula, Select values, Table output |
| t_02_dim_kanal | CSV/Text file input, String operations, Stream lookup (ref_kota), Data grid, Append streams, Table output |
| t_03_dim_promo | Text file input, Filter rows, String operations, Sort rows (unique), Data validator + error handling, Select values, Table output ×2 |
| t_04_dim_produk | Text file input, Sort rows, Analytic query (LEAD), Calculator, If field value is null, Stream lookup, Table input (S1), Regex evaluation, Filter rows, Table output ×2 |
| t_05_map_produk | Table input, Regex evaluation, Text file input, JSON input, Unique rows, Append streams, Table output |
| t_06_dim_pelanggan | Table input, Text file input, Replace in string, Merge join (FULL OUTER), Formula, JSON input, Sort rows, Unique rows, Table output |
| t_07_fact_web | Table input, Filter rows, Database lookup ×6, Calculator, Formula, Table output |
| t_08_fact_toko | Text file input ×2 (wildcard 42 file), Stream lookup, Filter rows, Database lookup ×6, Calculator, Formula, Table output |
| t_09_fact_marketplace | JSON input ×2, Sort rows, Unique rows, Group by, Stream lookup, Calculator, Database lookup ×6, Formula, Table output |

## 5. Hasil validasi ETL

| Cek | Hasil |
|---|---|
| Baris fakta S1 / S2 / S3 | 4.236 / 8.386 / 1.797 = 14.419 |
| Duplikat grain | 0 |
| Baris VOID / DIBATALKAN di fakta | 0 |
| Fee marketplace teralokasi = total fee invoice unik | Rp1.276.197.059 = Rp1.276.197.059 |
| Produk gagal lookup (produk_key = -1) | 0 |
| ORD-9999 → produk inferred | ✓ (HPP NULL) |
| Konsistensi `bersih − hpp − fee = margin` | 0 selisih |

## 6. Hasil kueri pembuktian

**Q1 – Margin YoY (2023-Q1 vs 2022-Q1).** Margin kotor % per kanal: Toko Fisik 19,28% → 19,49%, Situs Web 19,33% → 19,62%, Marketplace 12,20% → 13,65%. Marketplace selalu termurah marginnya karena fee komisi (± 5–6% dari nilai transaksi). Di tingkat sub-kategori, contoh penurunan terbesar: Meja di Marketplace (−54,8% YoY), Smartphone di Marketplace (−32,0%); kenaikan terbesar: Kursi di Situs Web (+39,4%), Lemari di Toko Fisik (+39,2%).

**Q2 – Pelanggan online vs member toko.** Dari 600 pelanggan web dan 600 member toko, **200 orang (33,3%) adalah orang yang sama** (cocok lewat nomor HP). 400 hanya belanja online, 400 hanya member toko. Kelompok beririsan aktif di kedua kanal (198 bertransaksi di web, 200 di toko). Pembeli marketplace (556 hash) tidak dapat dipadankan karena anonim.

**Q3 – Efektivitas kampanye.** Dengan metode sebelum–sesudah (30 hari sebelum vs selama kampanye, per kanal), 11 kombinasi kampanye–kanal tergolong **BERHASIL** (volume/hari naik, margin turun ≤ 1 poin), misalnya BUNDLE2 Oktober 2022 (+27,2% di Situs Web, +22,1% di Toko Fisik), HARBOLNAS Feb 2022 di Toko Fisik (+7,9%), WEEKEND20 Des 2022 di Toko Fisik (+7,7%). HARBOLNAS dan BACKSCHOOL di Marketplace menaikkan volume tetapi margin turun > 1 poin.

**Q4 – Kandidat realokasi stok ke marketplace.** 9 produk berada di kuartil teratas pangsa volume marketplace tetapi di separuh bawah toko+web, dipimpin P-1019 Samsung Smartphone Atque 128GB (rasio pangsa 1,76) dan P-1054 Uniqlo Atasan Maxime (1,71).

*(Tempel tabel hasil lengkap / screenshot dari MySQL Workbench.)*

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

| Anggota | Kontribusi |
|---|---|
| … | … |
