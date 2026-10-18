USE nrg_dw;

SELECT 'dim_tanggal'    AS tabel, COUNT(*) AS aktual, 730   AS harapan FROM dim_tanggal
UNION ALL SELECT 'dim_kanal',      COUNT(*), 45    FROM dim_kanal
UNION ALL SELECT 'dim_promo',      COUNT(*), 17    FROM dim_promo        
UNION ALL SELECT 'err_kampanye',   COUNT(*), 1     FROM err_kampanye     
UNION ALL SELECT 'dim_produk',     COUNT(*), 81    FROM dim_produk       
UNION ALL SELECT 'map_produk',     COUNT(*), 181   FROM map_produk       
UNION ALL SELECT 'dim_pelanggan',  COUNT(*), 1557  FROM dim_pelanggan    
UNION ALL SELECT 'fact_penjualan', COUNT(*), 14419 FROM fact_penjualan;

SELECT sumber_sistem,
       COUNT(*)                       AS baris,            
       SUM(qty)                       AS qty,              
       ROUND(SUM(penjualan_bersih))   AS penjualan_bersih, 
       ROUND(SUM(fee_marketplace))    AS fee,              
       ROUND(SUM(margin_kotor))       AS margin_kotor      
FROM fact_penjualan
GROUP BY sumber_sistem;

SELECT sumber_sistem, no_transaksi, no_baris, COUNT(*) n
FROM fact_penjualan GROUP BY 1,2,3 HAVING COUNT(*) > 1;

SELECT segmen_identitas, COUNT(*) FROM dim_pelanggan GROUP BY 1;

SELECT f.no_transaksi, p.material_no, p.is_inferred, f.hpp, f.margin_kotor
FROM fact_penjualan f JOIN dim_produk p ON p.produk_key = f.produk_key
WHERE f.no_transaksi = 'ORD-9999';

SELECT produk_key, material_no, harga_pokok, berlaku_mulai, berlaku_sampai, is_current
FROM dim_produk WHERE material_no = 'P-1001';

SELECT sumber_sistem, SUM(produk_key = -1) produk_unknown, SUM(pelanggan_key = -1) pelanggan_unknown
FROM fact_penjualan GROUP BY 1;

SELECT sumber_sistem,
       SUM(promo_key = -1) AS tanpa_promo,
       SUM(promo_key = -2) AS diskon_tanpa_kampanye,
       SUM(promo_key > 0)  AS kampanye_teridentifikasi
FROM fact_penjualan GROUP BY 1;

SELECT no_transaksi, waktu_transaksi_wib, tanggal_key
FROM fact_penjualan WHERE no_transaksi = 'INV/20220527/MPL/9804';

SELECT COUNT(*) AS baris_tidak_konsisten
FROM fact_penjualan
WHERE hpp IS NOT NULL AND ABS(penjualan_bersih - hpp - fee_marketplace - margin_kotor) > 0.05;
