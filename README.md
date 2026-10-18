# Data Warehouse Nusantara Retail Group (NRG)

Tugas Kelompok 1 – Pengembangan Data Warehouse · Mata Kuliah Data Warehouse / Business Intelligence

| Nama | NIM | Peran |
|---|---|---|
| Djaudza Djiyya Muhammad | 102022400133 | Desain dimensional + dokumen |
| Faris Yahya Ayyash Alfatih | 102022400029 | ETL dimensi (t_01 – t_06) |
| Figo Al Ghifari | 102022400302 | ETL fakta (t_07 – t_09) + Job |
| Muhammad Nabeel Ghifari | 102022400114 | Kueri pembuktian + laporan |

Satu tabel fakta (`fact_penjualan`, grain 1 baris = 1 item transaksi) dan lima dimensi (`dim_tanggal`, `dim_produk`, `dim_pelanggan`, `dim_kanal`, `dim_promo`) yang mengintegrasikan lima sumber:
S1 ECOM_DB (MySQL), S2 POS_TOKO (CSV `;`), S3 MPL_API (JSON), S4 ERP_MASTER (CSV), S5 MKT_SHEET (CSV).

![Star schema](docs/star_schema.png)

## Status (18 Oktober 2026)

| Komponen | Status |
|---|---|
| Star schema + DDL (`sql/01_ddl_dw.sql`) | Selesai |
| Source-to-target mapping | Selesai |
| t_01 – t_06 (dimensi + map_produk) | Selesai |
| t_07_fact_web (S1) | Selesai |
| t_08_fact_toko (S2) | Selesai |
| t_09_fact_marketplace (S3) | Selesai |
| Job `j_00_main_nrg_dw.kjb` | Selesai |
| Validasi ETL (`sql/02_validasi_etl.sql`) & Kueri Pembuktian (`sql/03_kueri_pembuktian.sql`) | Selesai |
| Laporan desain dimensional (`docs/laporan_desain_dimensional.md`) | Selesai |

Seluruh pipeline ETL (`t_01` s.d. `t_09`) yang diorkestrasi melalui `j_00_main_nrg_dw.kjb` telah selesai diuji dan lulus seluruh kueri validasi (`02_validasi_etl.sql`) serta kueri pembuktian bisnis (`03_kueri_pembuktian.sql`).

## Struktur repositori

```
nrg-data-warehouse/
├── README.md
├── data/                              ← paket data dari dosen (TIDAK diubah isinya)
│   ├── S1_ecom_db_schema_mysql.sql, load_all.py, ref_kota.csv
│   └── S1_ECOM_DB/  S2_POS_TOKO/  S3_MPL_API/  S4_ERP_MASTER/  S5_MKT_SHEET/
├── sql/
│   ├── 01_ddl_dw.sql                  ← DDL star schema + baris default (-1/-2)
│   ├── 02_validasi_etl.sql            ← cek hasil ETL (aktual vs harapan)
│   └── 03_kueri_pembuktian.sql        ← 4 kueri pembuktian (Q1–Q4)
├── pentaho/
│   ├── j_00_main_nrg_dw.kjb           ← Job utama orkestrasi end-to-end
│   ├── t_01_dim_tanggal.ktr
│   ├── t_02_dim_kanal.ktr
│   ├── t_03_dim_promo.ktr
│   ├── t_04_dim_produk.ktr
│   ├── t_05_map_produk.ktr
│   ├── t_06_dim_pelanggan.ktr
│   ├── t_07_fact_web.ktr
│   ├── t_08_fact_toko.ktr
│   └── t_09_fact_marketplace.ktr
└── docs/
    ├── laporan_desain_dimensional.md  ← laporan desain & hasil kueri pembuktian
    ├── star_schema.png
    ├── source_to_target_mapping.csv   ← peta S2T kolom demi kolom (153 baris)
    ├── source_to_target_mapping.md
    └── screenshots/                   ← tangkapan layar kanvas Job dan 9 transformation
```

## Prasyarat

| Komponen | Versi yang dipakai | Catatan |
|---|---|---|
| MySQL Server | 8.x | user `root`, port `3306` (sesuaikan) |
| Pentaho Data Integration (Spoon) | 9.x / 10.x | Java sesuai versi PDI |
| MySQL JDBC driver | mysql-connector-j 8.x | taruh `.jar` di `data-integration/lib/` |
| Python 3 + `pandas`, `mysql-connector-python` | – | hanya untuk memuat S1 (skrip dari dosen) |

## Persiapan

1. **Muat sumber S1 ke MySQL** (sekali saja):
   ```bash
   cd data
   mysql -u root -p < S1_ecom_db_schema_mysql.sql      # membuat database nrg_ecom
   python load_all.py                                   # memuat 11 CSV S1 ke nrg_ecom
   ```
   `load_all.py` memakai user `root` tanpa password. Kalau MySQL kamu memakai user/password lain, ubah bagian koneksi di skrip itu secara lokal (tidak perlu di-commit).
2. **Skema `nrg_dw`** tidak perlu dibuat manual karena Job menjalankan `sql/01_ddl_dw.sql` di awal. Kalau ingin menjalankan transformation satu per satu tanpa Job, jalankan dulu:
   ```bash
   mysql -u root -p < sql/01_ddl_dw.sql
   ```
3. **Atur variabel Pentaho** di `~/.kettle/kettle.properties` (Windows: `C:\Users\<user>\.kettle\kettle.properties`):
   ```properties
   NRG_DATA_DIR=C:/Users/<user>/Documents/nrg-data-warehouse/data
   NRG_DB_HOST=localhost
   NRG_DB_PORT=3306
   NRG_DB_USER=root
   NRG_DB_PASS=
   ```
   Gunakan `/` walaupun di Windows. Restart Spoon setelah mengubah file ini.
4. **Koneksi database** (sudah tersimpan di setiap `.ktr` dan `.kjb`, memakai variabel di atas):

   | Nama koneksi | Database | Dipakai untuk |
   |---|---|---|
   | `nrg_ecom_src` | `nrg_ecom` | membaca sumber S1 |
   | `nrg_dw` | `nrg_dw` | menulis star schema |

   Opsi koneksi: `serverTimezone=Asia/Jakarta`, `useSSL=false`, `allowPublicKeyRetrieval=true`.

## Cara menjalankan

### 1. Menjalankan sekaligus lewat Job utama (Direkomendasikan)

Buka `pentaho/j_00_main_nrg_dw.kjb` di Spoon lalu klik **Run** (`F9`), atau jalankan melalui command line (`Kitchen`):

```
START → buat_ulang_dw → t_01 → t_02 → t_03 → t_04 → t_05 → t_06 → t_07 → t_08 → t_09 → Success
```

```bash
# Windows
Kitchen.bat /file:"C:\...\pentaho\j_00_main_nrg_dw.kjb" /level:Basic
# Linux / macOS
./kitchen.sh -file=/.../pentaho/j_00_main_nrg_dw.kjb -level=Basic
```

Entry `buat_ulang_dw` (SQL, koneksi `nrg_ecom_src`) menjalankan `sql/01_ddl_dw.sql` lewat path relatif `${Internal.Entry.Current.Directory}/../sql/01_ddl_dw.sql`. Script itu menghapus dan membuat ulang database `nrg_dw` beserta baris default (`-1` dan `-2`), jadi Job selalu mulai dari kondisi kosong dan aman dijalankan berulang kali tanpa duplikasi data. Setiap hop memakai *Follow when result is true*, sehingga Job berhenti jika satu transformation gagal.

### 2. Urutan transformation di dalam Job

| No | Transformation | Isi |
|---|---|---|
| 1 | `t_01_dim_tanggal` | 730 tanggal 2022-01-01 s.d. 2023-12-31 |
| 2 | `t_02_dim_kanal` | 42 toko + Situs Web + 2 marketplace |
| 3 | `t_03_dim_promo` | S5 dibersihkan; baris gagal validasi → `err_kampanye` |
| 4 | `t_04_dim_produk` | S4 SCD2 harga pokok + produk inferred dari S1 |
| 5 | `t_05_map_produk` | pemetaan SKU S1 / item_code S2 / seller_sku S3 → material_no |
| 6 | `t_06_dim_pelanggan` | web + member (cocok via HP dinormalkan) + pembeli marketplace |
| 7 | `t_07_fact_web` | fakta dari S1 (order DIBATALKAN dibuang, harga & diskon dibagi 1,11) |
| 8 | `t_08_fact_toko` | fakta dari S2 (42 toko, transaksi VOID dibuang) |
| 9 | `t_09_fact_marketplace` | fakta dari S3 (dedup tarikan API + konversi UTC→WIB + alokasi fee per item) |

Setelah Job selesai, jalankan `sql/02_validasi_etl.sql` (semua kolom `aktual` sama dengan `harapan`), lalu `sql/03_kueri_pembuktian.sql` (Q1–Q4).

## Jumlah baris

Seluruh angka hasil pemuatan ETL pada `nrg_dw` telah sesuai 100% dengan target rekonsiliasi data sumber:

| Tabel | Baris | Keterangan |
|---|---|---|
| dim_tanggal | 730 | hasil run |
| dim_kanal | 45 | hasil run |
| dim_promo | 17 (15 kampanye + 2 default) | hasil run |
| err_kampanye | 1 | hasil run |
| dim_produk | 81 (79 versi S4 + 1 inferred + 1 default) | hasil run |
| map_produk | 181 (61 S1 + 60 S2 + 60 S3) | hasil run |
| dim_pelanggan | 1.557 | hasil run |
| fact_penjualan (S1) | 4.236 | hasil run |
| fact_penjualan (S2) | 8.386 | hasil run |
| fact_penjualan (S3) | 1.797 | hasil run |
| fact_penjualan (total) | 14.419 | hasil run |

## Keputusan desain utama

- **Basis harga tanpa PPN**: S1 & S3 dibagi 1,11; S2 sudah tanpa PPN.
- **Basis waktu WIB**: S3 `paid_at` (UTC) + 7 jam; S1 sudah WIB; S2 hanya tanggal.
- **Margin kotor** = penjualan bersih − HPP (harga pokok S4 versi berlaku pada tanggal transaksi) − fee marketplace (dialokasikan proporsional per item).
- **Late arriving dimension**: `SKU-NEWARR-001` (ORD-9999) dimuat sebagai *inferred member* (`is_inferred = 1`, HPP NULL).
- **Pelanggan lintas kanal**: S1 ↔ S2 dicocokkan lewat nomor HP yang dinormalkan; S3 hanya `buyer.hash`.

Detail lengkap ada di `docs/laporan_desain_dimensional.md` dan `docs/source_to_target_mapping.csv`.