-- Q2. Apakah pelanggan online (situs web) adalah orang yang sama dengan pemegang kartu member toko fisik?
USE nrg_dw;

SELECT  segmen_identitas,
        COUNT(*)                                                        AS jumlah_pelanggan,
        ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                AS pct_dari_semua,
        ROUND(100 * SUM(is_pelanggan_web) / NULLIF(
              (SELECT SUM(is_pelanggan_web) FROM dim_pelanggan), 0), 2) AS pct_dari_pelanggan_web
FROM dim_pelanggan
WHERE pelanggan_key > 0
GROUP BY segmen_identitas
ORDER BY jumlah_pelanggan DESC;