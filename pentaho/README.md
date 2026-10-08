# Folder Pentaho

Simpan semua file hasil Spoon di folder ini dengan nama PERSIS seperti di bawah
(Job memanggil transformation lewat `${Internal.Entry.Current.Directory}/<nama>.ktr`).

| File | Isi |
|---|---|
| j_00_main_nrg_dw.kjb | Job utama: SQL DDL → t_01 … t_09 |
| t_01_dim_tanggal.ktr | dim_tanggal |
| t_02_dim_kanal.ktr | dim_kanal |
| t_03_dim_promo.ktr | dim_promo + err_kampanye |
| t_04_dim_produk.ktr | dim_produk (SCD2 + inferred) |
| t_05_map_produk.ktr | map_produk |
| t_06_dim_pelanggan.ktr | dim_pelanggan |
| t_07_fact_web.ktr | fact_penjualan dari S1 |
| t_08_fact_toko.ktr | fact_penjualan dari S2 |
| t_09_fact_marketplace.ktr | fact_penjualan dari S3 |
