-- =====================================================================
-- 01_ddl_dw.sql
-- DDL Data Warehouse Nusantara Retail Group (NRG) - Star Schema
-- Target  : MySQL 8.x (diuji juga di MariaDB 10.11)
-- Dijalankan otomatis oleh Job Pentaho  j_00_main_nrg_dw.kjb  (entry "SQL")
-- Menjalankan ulang script ini = mengosongkan DW (kondisi kosong).
-- =====================================================================

DROP DATABASE IF EXISTS nrg_dw;
CREATE DATABASE nrg_dw CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE nrg_dw;

-- ---------------------------------------------------------------------
-- DIMENSI TANGGAL  (role: tanggal transaksi dalam WIB)
-- ---------------------------------------------------------------------
CREATE TABLE dim_tanggal (
    tanggal_key      INT          NOT NULL PRIMARY KEY,   -- format YYYYMMDD
    tanggal          DATE         NOT NULL UNIQUE,
    hari_dalam_bulan TINYINT      NOT NULL,
    nama_hari        VARCHAR(10)  NOT NULL,
    is_akhir_pekan   TINYINT(1)   NOT NULL,
    minggu_ke        TINYINT      NOT NULL,               -- ISO week
    bulan            TINYINT      NOT NULL,
    nama_bulan       VARCHAR(10)  NOT NULL,
    kuartal          TINYINT      NOT NULL,
    tahun            SMALLINT     NOT NULL,
    tahun_kuartal    CHAR(7)      NOT NULL,               -- contoh 2022-Q1
    tahun_bulan      CHAR(7)      NOT NULL                -- contoh 2022-01
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- DIMENSI KANAL / TOKO  (3 kanal: Toko Fisik x42, Situs Web x1, Marketplace x2)
-- ---------------------------------------------------------------------
CREATE TABLE dim_kanal (
    kanal_key     INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    kanal_kode    VARCHAR(20)  NOT NULL UNIQUE,   -- TS01..TS42, WEB, MPL_A, MPL_B
    kanal         VARCHAR(20)  NOT NULL,          -- Toko Fisik / Situs Web / Marketplace
    sub_kanal     VARCHAR(60)  NOT NULL,          -- nama toko / Situs Web Resmi / Marketplace A/B
    store_id      INT          NULL,
    kota          VARCHAR(60)  NULL,              -- sudah dibakukan via ref_kota
    provinsi      VARCHAR(60)  NULL,
    format_toko   VARCHAR(20)  NULL,
    tanggal_buka  DATE         NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- DIMENSI PRODUK  (SCD Tipe 2 atas harga_pokok - sumber S4 ERP)
-- ---------------------------------------------------------------------
CREATE TABLE dim_produk (
    produk_key       INT           NOT NULL AUTO_INCREMENT PRIMARY KEY,
    material_no      VARCHAR(40)   NOT NULL,      -- natural key (S4), utk inferred = SKU S1
    nama_produk      VARCHAR(150)  NOT NULL,
    brand            VARCHAR(60)   NULL,
    kategori         VARCHAR(60)   NULL,
    sub_kategori     VARCHAR(60)   NULL,
    harga_pokok      DECIMAL(15,2) NULL,          -- NULL utk inferred member
    supplier_id      VARCHAR(10)   NULL,
    nama_supplier    VARCHAR(120)  NULL,
    kota_supplier    VARCHAR(60)   NULL,
    status_produk    VARCHAR(10)   NULL,          -- AKTIF / NONAKTIF / INFERRED
    berlaku_mulai    DATE          NOT NULL,
    berlaku_sampai   DATE          NOT NULL,      -- 9999-12-31 = versi terkini
    is_current       TINYINT(1)    NOT NULL,
    is_inferred      TINYINT(1)    NOT NULL DEFAULT 0,  -- 1 = late arriving dimension
    UNIQUE KEY uq_produk_versi (material_no, berlaku_mulai),
    KEY idx_produk_nk (material_no, berlaku_mulai, berlaku_sampai)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- DIMENSI PELANGGAN  (conformed: pelanggan web S1 + member toko S2 + pembeli marketplace S3)
-- ---------------------------------------------------------------------
CREATE TABLE dim_pelanggan (
    pelanggan_key     INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    pelanggan_nk      VARCHAR(40)  NOT NULL UNIQUE,  -- 'HP:8xxxx' atau 'MPL:<hash>' atau 'UNKNOWN'
    hp_normal         VARCHAR(20)  NULL,             -- nomor HP dinormalkan (tanpa 0/62 di depan)
    customer_id_web   INT          NULL,             -- S1 customers.customer_id
    member_no         VARCHAR(10)  NULL,             -- S2 member.member_no
    buyer_hash        VARCHAR(20)  NULL,             -- S3 buyer.hash
    nama_pelanggan    VARCHAR(120) NULL,
    gender            CHAR(1)      NULL,
    kota              VARCHAR(60)  NULL,             -- dibakukan via ref_kota
    is_pelanggan_web  TINYINT(1)   NOT NULL DEFAULT 0,
    is_member_toko    TINYINT(1)   NOT NULL DEFAULT 0,
    is_pembeli_mpl    TINYINT(1)   NOT NULL DEFAULT 0,
    segmen_identitas  VARCHAR(20)  NOT NULL,         -- WEB_SAJA / MEMBER_SAJA / WEB_DAN_MEMBER / MARKETPLACE / UNKNOWN
    KEY idx_cust_web (customer_id_web),
    KEY idx_cust_member (member_no),
    KEY idx_cust_hash (buyer_hash)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- DIMENSI PROMO  (sumber S5 MKT_SHEET yang sudah dibersihkan)
-- ---------------------------------------------------------------------
CREATE TABLE dim_promo (
    promo_key             INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    kode_promo            VARCHAR(30)  NOT NULL,
    nama_kampanye         VARCHAR(100) NOT NULL,
    jenis_promo           VARCHAR(20)  NULL,
    kanal_promo           VARCHAR(20)  NULL,       -- Semua Kanal / Toko Fisik / Situs Web / Marketplace
    tgl_mulai             DATE         NULL,
    tgl_selesai           DATE         NULL,
    target_diskon_persen  DECIMAL(5,2) NULL,
    pic                   VARCHAR(60)  NULL,
    UNIQUE KEY uq_promo (kode_promo, tgl_mulai),
    KEY idx_promo_periode (kanal_promo, tgl_mulai, tgl_selesai)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- TABEL PEMETAAN PRODUK  (SKU S1 / item_code S2 / seller_sku S3  -> material_no S4)
-- ---------------------------------------------------------------------
CREATE TABLE map_produk (
    sumber_sistem   VARCHAR(5)   NOT NULL,   -- S1 / S2 / S3
    kode_sumber     VARCHAR(40)  NOT NULL,   -- sku / item_code / seller_sku
    nama_sumber     VARCHAR(150) NULL,
    material_no     VARCHAR(40)  NOT NULL,
    metode_mapping  VARCHAR(60)  NOT NULL,
    PRIMARY KEY (sumber_sistem, kode_sumber)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- TABEL ERROR  (baris S5 yang gagal validasi - tidak dibuang tanpa jejak)
-- ---------------------------------------------------------------------
CREATE TABLE err_kampanye (
    err_id                INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    kode_promo            VARCHAR(30)  NULL,
    nama_kampanye         VARCHAR(100) NULL,
    jenis_promo           VARCHAR(20)  NULL,
    kanal                 VARCHAR(20)  NULL,
    tgl_mulai             VARCHAR(20)  NULL,
    tgl_selesai           VARCHAR(20)  NULL,
    target_diskon_persen  VARCHAR(20)  NULL,   -- disimpan apa adanya (teks)
    pic                   VARCHAR(60)  NULL,
    error_count           INT          NULL,
    error_desc            VARCHAR(500) NULL,
    error_fields          VARCHAR(200) NULL,
    error_codes           VARCHAR(100) NULL,
    dicatat_pada          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- TABEL FAKTA PENJUALAN
-- Grain: 1 baris = 1 item transaksi (order line S1 / trx line S2 / invoice item S3)
-- Semua nilai uang: Rupiah TANPA PPN. Semua waktu: WIB.
-- ---------------------------------------------------------------------
CREATE TABLE fact_penjualan (
    penjualan_id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    tanggal_key           INT           NOT NULL,
    produk_key            INT           NOT NULL,
    pelanggan_key         INT           NOT NULL,
    kanal_key             INT           NOT NULL,
    promo_key             INT           NOT NULL,
    -- degenerate dimension / lineage
    sumber_sistem         VARCHAR(5)    NOT NULL,   -- S1 / S2 / S3
    no_transaksi          VARCHAR(40)   NOT NULL,   -- order_id / trx_no / invoice
    no_baris              VARCHAR(40)   NOT NULL,   -- line_no / line_seq / seller_sku
    waktu_transaksi_wib   DATETIME      NOT NULL,
    is_retur              TINYINT(1)    NOT NULL DEFAULT 0,
    -- measures
    qty                   INT           NOT NULL,
    harga_satuan          DECIMAL(15,2) NOT NULL,   -- tanpa PPN
    penjualan_kotor       DECIMAL(18,2) NOT NULL,   -- qty * harga_satuan
    diskon                DECIMAL(18,2) NOT NULL,   -- tanpa PPN, dalam Rupiah
    penjualan_bersih      DECIMAL(18,2) NOT NULL,   -- kotor - diskon
    hpp                   DECIMAL(18,2) NULL,       -- qty * harga_pokok versi berlaku (S4)
    fee_marketplace       DECIMAL(18,2) NOT NULL DEFAULT 0,  -- alokasi commission+service (S3)
    margin_kotor          DECIMAL(18,2) NULL,       -- bersih - hpp - fee
    UNIQUE KEY uq_fact_grain (sumber_sistem, no_transaksi, no_baris),
    KEY idx_fact_tanggal (tanggal_key),
    KEY idx_fact_produk (produk_key),
    KEY idx_fact_pelanggan (pelanggan_key),
    KEY idx_fact_kanal (kanal_key),
    KEY idx_fact_promo (promo_key),
    CONSTRAINT fk_fact_tanggal   FOREIGN KEY (tanggal_key)   REFERENCES dim_tanggal(tanggal_key),
    CONSTRAINT fk_fact_produk    FOREIGN KEY (produk_key)    REFERENCES dim_produk(produk_key),
    CONSTRAINT fk_fact_pelanggan FOREIGN KEY (pelanggan_key) REFERENCES dim_pelanggan(pelanggan_key),
    CONSTRAINT fk_fact_kanal     FOREIGN KEY (kanal_key)     REFERENCES dim_kanal(kanal_key),
    CONSTRAINT fk_fact_promo     FOREIGN KEY (promo_key)     REFERENCES dim_promo(promo_key)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- BARIS DEFAULT (unknown / not applicable member)
-- ---------------------------------------------------------------------
INSERT INTO dim_pelanggan (pelanggan_key, pelanggan_nk, nama_pelanggan, segmen_identitas)
VALUES (-1, 'UNKNOWN', 'Pembeli Toko Non-Member', 'UNKNOWN');

INSERT INTO dim_promo (promo_key, kode_promo, nama_kampanye, jenis_promo, kanal_promo)
VALUES (-1, 'TANPA_PROMO', 'Tanpa Promo / Tanpa Diskon', 'N/A', 'N/A'),
       (-2, 'TIDAK_TERIDENTIFIKASI', 'Diskon Tanpa Kampanye Valid', 'N/A', 'N/A');

INSERT INTO dim_produk (produk_key, material_no, nama_produk, status_produk,
                        berlaku_mulai, berlaku_sampai, is_current, is_inferred)
VALUES (-1, 'UNKNOWN', 'Produk Tidak Dikenal', 'UNKNOWN', '1900-01-01', '9999-12-31', 1, 1);
