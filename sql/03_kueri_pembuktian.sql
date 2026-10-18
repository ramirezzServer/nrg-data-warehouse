USE nrg_dw;
WITH margin_kuartal AS (
    SELECT  t.tahun,
            t.kuartal,
            p.kategori,
            p.sub_kategori,
            k.kanal,
            SUM(f.penjualan_bersih) AS penjualan_bersih,
            SUM(f.margin_kotor)     AS margin_kotor
    FROM fact_penjualan f
    JOIN dim_tanggal t ON t.tanggal_key = f.tanggal_key
    JOIN dim_produk  p ON p.produk_key  = f.produk_key
    JOIN dim_kanal   k ON k.kanal_key   = f.kanal_key
    GROUP BY t.tahun, t.kuartal, p.kategori, p.sub_kategori, k.kanal
)
SELECT  CONCAT(sek.tahun, '-Q', sek.kuartal)                     AS kuartal,
        sek.kategori,
        sek.sub_kategori,
        sek.kanal,
        ROUND(sek.penjualan_bersih)                              AS penjualan_bersih,
        ROUND(sek.margin_kotor)                                  AS margin_kotor,
        ROUND(100 * sek.margin_kotor / sek.penjualan_bersih, 2)  AS margin_pct,
        ROUND(lalu.margin_kotor)                                 AS margin_kotor_thn_lalu,
        ROUND(100 * lalu.margin_kotor / lalu.penjualan_bersih, 2) AS margin_pct_thn_lalu,
        ROUND(100 * (sek.margin_kotor - lalu.margin_kotor)
                  / ABS(lalu.margin_kotor), 2)                   AS pertumbuhan_margin_yoy_pct
FROM margin_kuartal sek
LEFT JOIN margin_kuartal lalu
       ON  lalu.tahun        = sek.tahun - 1
       AND lalu.kuartal      = sek.kuartal
       AND lalu.sub_kategori = sek.sub_kategori
       AND lalu.kanal        = sek.kanal
WHERE sek.tahun = 2023 AND sek.kuartal = 1          
ORDER BY sek.kategori, sek.sub_kategori, sek.kanal;

SELECT  segmen_identitas,
        COUNT(*)                                                        AS jumlah_pelanggan,
        ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                AS pct_dari_semua,
        ROUND(100 * SUM(is_pelanggan_web) / NULLIF(
              (SELECT SUM(is_pelanggan_web) FROM dim_pelanggan), 0), 2) AS pct_dari_pelanggan_web
FROM dim_pelanggan
WHERE pelanggan_key > 0
GROUP BY segmen_identitas
ORDER BY jumlah_pelanggan DESC;


SELECT  c.segmen_identitas,
        k.kanal,
        COUNT(DISTINCT c.pelanggan_key)       AS pelanggan_aktif,
        COUNT(DISTINCT f.no_transaksi)        AS jumlah_transaksi,
        ROUND(SUM(f.penjualan_bersih))        AS penjualan_bersih,
        ROUND(SUM(f.penjualan_bersih) / COUNT(DISTINCT c.pelanggan_key)) AS penjualan_per_pelanggan
FROM fact_penjualan f
JOIN dim_pelanggan c ON c.pelanggan_key = f.pelanggan_key
JOIN dim_kanal     k ON k.kanal_key     = f.kanal_key
WHERE c.segmen_identitas IN ('WEB_SAJA', 'MEMBER_SAJA', 'WEB_DAN_MEMBER')
GROUP BY c.segmen_identitas, k.kanal
ORDER BY c.segmen_identitas, k.kanal;


WITH promo_kanal AS (
    SELECT  pr.promo_key, pr.kode_promo, pr.nama_kampanye, pr.kanal_promo,
            pr.tgl_mulai, pr.tgl_selesai, pr.target_diskon_persen, k.kanal
    FROM dim_promo pr
    JOIN (SELECT DISTINCT kanal FROM dim_kanal) k
      ON pr.kanal_promo = 'Semua Kanal' OR pr.kanal_promo = k.kanal
    WHERE pr.promo_key > 0
),
periode AS (
    SELECT promo_key, kanal, 'KAMPANYE' AS periode, tgl_mulai AS d1, tgl_selesai AS d2
    FROM promo_kanal
    UNION ALL
    SELECT promo_key, kanal, 'SEBELUM', DATE_SUB(tgl_mulai, INTERVAL 30 DAY), DATE_SUB(tgl_mulai, INTERVAL 1 DAY)
    FROM promo_kanal
),
penjualan_kanal AS (
    SELECT f.tanggal_key, k.kanal, f.qty, f.penjualan_bersih, f.margin_kotor
    FROM fact_penjualan f
    JOIN dim_kanal k ON k.kanal_key = f.kanal_key
    WHERE f.margin_kotor IS NOT NULL                 
),
agregat AS (
    SELECT  p.promo_key, p.kanal, p.periode,
            DATEDIFF(p.d2, p.d1) + 1            AS jumlah_hari,
            COALESCE(SUM(x.qty), 0)             AS qty,
            SUM(x.penjualan_bersih)             AS penjualan_bersih,
            SUM(x.margin_kotor)                 AS margin_kotor
    FROM periode p
    JOIN dim_tanggal t        ON t.tanggal BETWEEN p.d1 AND p.d2
    LEFT JOIN penjualan_kanal x ON x.tanggal_key = t.tanggal_key AND x.kanal = p.kanal
    GROUP BY p.promo_key, p.kanal, p.periode, p.d1, p.d2
),
banding AS (
    SELECT  pk.*,
            kp.qty / kp.jumlah_hari                          AS qty_hari_kampanye,
            sb.qty / sb.jumlah_hari                          AS qty_hari_sebelum,
            100 * kp.margin_kotor / kp.penjualan_bersih      AS margin_pct_kampanye,
            100 * sb.margin_kotor / sb.penjualan_bersih      AS margin_pct_sebelum,
            (SELECT SUM(f.diskon)
               FROM fact_penjualan f JOIN dim_kanal k2 ON k2.kanal_key = f.kanal_key
              WHERE f.promo_key = pk.promo_key AND k2.kanal = pk.kanal) AS diskon_teratribusi
    FROM promo_kanal pk
    JOIN agregat kp ON kp.promo_key = pk.promo_key AND kp.kanal = pk.kanal AND kp.periode = 'KAMPANYE'
    JOIN agregat sb ON sb.promo_key = pk.promo_key AND sb.kanal = pk.kanal AND sb.periode = 'SEBELUM'
)
SELECT  kode_promo,
        nama_kampanye,
        kanal_promo,
        tgl_mulai,
        tgl_selesai,
        kanal                                                     AS kanal_dievaluasi,
        ROUND(qty_hari_sebelum, 2)                                AS qty_per_hari_sebelum,
        ROUND(qty_hari_kampanye, 2)                               AS qty_per_hari_kampanye,
        ROUND(100 * (qty_hari_kampanye / qty_hari_sebelum - 1), 2) AS uplift_volume_pct,
        ROUND(margin_pct_sebelum, 2)                              AS margin_pct_sebelum,
        ROUND(margin_pct_kampanye, 2)                             AS margin_pct_kampanye,
        ROUND(margin_pct_kampanye - margin_pct_sebelum, 2)        AS selisih_margin_poin,
        ROUND(COALESCE(diskon_teratribusi, 0))                    AS diskon_teratribusi,
        CASE
            WHEN qty_hari_kampanye > qty_hari_sebelum
             AND margin_pct_kampanye >= margin_pct_sebelum - 1    THEN 'BERHASIL'
            WHEN qty_hari_kampanye > qty_hari_sebelum             THEN 'Volume naik, margin tergerus'
            ELSE 'Volume tidak naik'
        END                                                       AS kesimpulan
FROM banding
ORDER BY CASE WHEN qty_hari_kampanye > qty_hari_sebelum
               AND margin_pct_kampanye >= margin_pct_sebelum - 1 THEN 0 ELSE 1 END,
         uplift_volume_pct DESC;


WITH qty_kanal AS (
    SELECT  p.material_no,
            MAX(p.nama_produk)                                                  AS nama_produk,
            MAX(p.sub_kategori)                                                 AS sub_kategori,
            SUM(CASE WHEN k.kanal = 'Marketplace' THEN f.qty ELSE 0 END)        AS qty_mpl,
            SUM(CASE WHEN k.kanal IN ('Toko Fisik', 'Situs Web') THEN f.qty ELSE 0 END) AS qty_toko_web
    FROM fact_penjualan f
    JOIN dim_produk p ON p.produk_key = f.produk_key
    JOIN dim_kanal  k ON k.kanal_key  = f.kanal_key
    WHERE p.is_inferred = 0
    GROUP BY p.material_no
),
pangsa AS (
    SELECT  q.*,
            100 * q.qty_mpl      / SUM(q.qty_mpl)      OVER () AS pangsa_mpl_pct,
            100 * q.qty_toko_web / SUM(q.qty_toko_web) OVER () AS pangsa_toko_web_pct
    FROM qty_kanal q
),
peringkat AS (
    SELECT  p.*,
            NTILE(4) OVER (ORDER BY p.pangsa_mpl_pct DESC)      AS kuartil_mpl,
            NTILE(2) OVER (ORDER BY p.pangsa_toko_web_pct DESC) AS paruh_toko_web
    FROM pangsa p
)
SELECT  material_no,
        nama_produk,
        sub_kategori,
        qty_mpl,
        qty_toko_web,
        ROUND(pangsa_mpl_pct, 2)                         AS pangsa_mpl_pct,
        ROUND(pangsa_toko_web_pct, 2)                    AS pangsa_toko_web_pct,
        ROUND(pangsa_mpl_pct / pangsa_toko_web_pct, 2)   AS rasio_pangsa_mpl_vs_toko_web
FROM peringkat
WHERE kuartil_mpl = 1 AND paruh_toko_web = 2
ORDER BY rasio_pangsa_mpl_vs_toko_web DESC;
