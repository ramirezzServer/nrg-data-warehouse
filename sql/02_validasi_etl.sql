-- =====================================================================
-- 02_validasi_etl.sql
-- Cek hasil ETL Pentaho. Jalankan setelah Job selesai.
-- Kolom "harapan" = angka yang seharusnya keluar jika ETL benar.
-- =====================================================================
USE nrg_dw;

-- 1. Jumlah baris tiap tabel (termasuk baris default -1/-2)
SELECT 'dim_tanggal'    AS tabel, COUNT(*) AS aktual, 730   AS harapan FROM dim_tanggal
UNION ALL SELECT 'dim_kanal',      COUNT(*), 45    FROM dim_kanal
UNION ALL SELECT 'dim_promo',      COUNT(*), 17    FROM dim_promo        -- 15 kampanye valid + 2 default
UNION ALL SELECT 'err_kampanye',   COUNT(*), 1     FROM err_kampanye     -- GAJIAN25 "sepuluh"
UNION ALL SELECT 'dim_produk',     COUNT(*), 81    FROM dim_produk       -- 79 versi S4 + 1 inferred + 1 default
UNION ALL SELECT 'map_produk',     COUNT(*), 181   FROM map_produk       -- 61 S1 + 60 S2 + 60 S3
UNION ALL SELECT 'dim_pelanggan',  COUNT(*), 1557  FROM dim_pelanggan    -- 1000 web/member + 556 MPL + 1 default
UNION ALL SELECT 'fact_penjualan', COUNT(*), 14419 FROM fact_penjualan;

-- 2. Fakta per sumber
SELECT sumber_sistem,
       COUNT(*)                       AS baris,            -- S1 4236 | S2 8386 | S3 1797
       SUM(qty)                       AS qty,              -- S1 5921 | S2 10053 | S3 2526
       ROUND(SUM(penjualan_bersih))   AS penjualan_bersih, -- S1 49.635.152.147 | S2 85.281.321.700 | S3 20.090.097.542
       ROUND(SUM(fee_marketplace))    AS fee,              -- S3 1.276.197.059
       ROUND(SUM(margin_kotor))       AS margin_kotor      -- S1 9.754.340.804 | S2 16.462.275.107 | S3 2.560.564.089
FROM fact_penjualan
GROUP BY sumber_sistem;

-- 3. Tidak boleh ada duplikat grain (harapan: 0 baris)
SELECT sumber_sistem, no_transaksi, no_baris, COUNT(*) n
FROM fact_penjualan GROUP BY 1,2,3 HAVING COUNT(*) > 1;

-- 4. Segmen pelanggan (harapan: WEB_SAJA 400, MEMBER_SAJA 400, WEB_DAN_MEMBER 200, MARKETPLACE 556, UNKNOWN 1)
SELECT segmen_identitas, COUNT(*) FROM dim_pelanggan GROUP BY 1;

-- 5. Late arriving dimension: ORD-9999 harus menunjuk produk inferred (harapan: 1 baris, is_inferred = 1)
SELECT f.no_transaksi, p.material_no, p.is_inferred, f.hpp, f.margin_kotor
FROM fact_penjualan f JOIN dim_produk p ON p.produk_key = f.produk_key
WHERE f.no_transaksi = 'ORD-9999';

-- 6. SCD2 harga pokok: contoh P-1001 punya 2 versi (2022-01-01 s.d. 2022-11-29, lalu 2022-11-30 s.d. 9999-12-31)
SELECT produk_key, material_no, harga_pokok, berlaku_mulai, berlaku_sampai, is_current
FROM dim_produk WHERE material_no = 'P-1001';

-- 7. Tidak ada produk/pelanggan yang gagal lookup (harapan: produk_key -1 = 0 baris, pelanggan -1 hanya S2 = 3742)
SELECT sumber_sistem, SUM(produk_key = -1) produk_unknown, SUM(pelanggan_key = -1) pelanggan_unknown
FROM fact_penjualan GROUP BY 1;

-- 8. Distribusi promo_key per sumber (harapan S1: -1=2741, -2=86 | S2: -1=5076, -2=1742 | S3: -1=900, -2=649)
SELECT sumber_sistem,
       SUM(promo_key = -1) AS tanpa_promo,
       SUM(promo_key = -2) AS diskon_tanpa_kampanye,
       SUM(promo_key > 0)  AS kampanye_teridentifikasi
FROM fact_penjualan GROUP BY 1;

-- 9. Konversi UTC -> WIB: invoice yang paid_at-nya 23:29Z harus jatuh ke tanggal berikutnya
SELECT no_transaksi, waktu_transaksi_wib, tanggal_key
FROM fact_penjualan WHERE no_transaksi = 'INV/20220527/MPL/9804';
-- harapan: 2 baris (invoice ini punya 2 item), waktu 2022-05-28 06:29:39, tanggal_key 20220528

-- 10. Margin konsisten: bersih - hpp - fee = margin (harapan: 0 baris selisih)
SELECT COUNT(*) AS baris_tidak_konsisten
FROM fact_penjualan
WHERE hpp IS NOT NULL AND ABS(penjualan_bersih - hpp - fee_marketplace - margin_kotor) > 0.05;
