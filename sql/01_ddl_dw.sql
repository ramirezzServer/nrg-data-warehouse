DROP DATABASE IF EXISTS nrg_dw;
CREATE DATABASE nrg_dw CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE nrg_dw;

CREATE TABLE dim_tanggal (
    tanggal_key      INT          NOT NULL PRIMARY KEY,   
    tanggal          DATE         NOT NULL UNIQUE,
    hari_dalam_bulan TINYINT      NOT NULL,
    nama_hari        VARCHAR(10)  NOT NULL,
    is_akhir_pekan   TINYINT(1)   NOT NULL,
    minggu_ke        TINYINT      NOT NULL,               
    bulan            TINYINT      NOT NULL,
    nama_bulan       VARCHAR(10)  NOT NULL,
    kuartal          TINYINT      NOT NULL,
    tahun            SMALLINT     NOT NULL,
    tahun_kuartal    CHAR(7)      NOT NULL,               
    tahun_bulan      CHAR(7)      NOT NULL                
) ENGINE=InnoDB;


CREATE TABLE dim_kanal (
    kanal_key     INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    kanal_kode    VARCHAR(20)  NOT NULL UNIQUE,   
    kanal         VARCHAR(20)  NOT NULL,          
    sub_kanal     VARCHAR(60)  NOT NULL,          
    store_id      INT          NULL,
    kota          VARCHAR(60)  NULL,              
    provinsi      VARCHAR(60)  NULL,
    format_toko   VARCHAR(20)  NULL,
    tanggal_buka  DATE         NULL
) ENGINE=InnoDB;


CREATE TABLE dim_produk (
    produk_key       INT           NOT NULL AUTO_INCREMENT PRIMARY KEY,
    material_no      VARCHAR(40)   NOT NULL,      
    nama_produk      VARCHAR(150)  NOT NULL,
    brand            VARCHAR(60)   NULL,
    kategori         VARCHAR(60)   NULL,
    sub_kategori     VARCHAR(60)   NULL,
    harga_pokok      DECIMAL(15,2) NULL,         
    supplier_id      VARCHAR(10)   NULL,
    nama_supplier    VARCHAR(120)  NULL,
    kota_supplier    VARCHAR(60)   NULL,
    status_produk    VARCHAR(10)   NULL,         
    berlaku_mulai    DATE          NOT NULL,
    berlaku_sampai   DATE          NOT NULL,      
    is_current       TINYINT(1)    NOT NULL,
    is_inferred      TINYINT(1)    NOT NULL DEFAULT 0,  
    UNIQUE KEY uq_produk_versi (material_no, berlaku_mulai),
    KEY idx_produk_nk (material_no, berlaku_mulai, berlaku_sampai)
) ENGINE=InnoDB;


CREATE TABLE dim_pelanggan (
    pelanggan_key     INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    pelanggan_nk      VARCHAR(40)  NOT NULL UNIQUE,  
    hp_normal         VARCHAR(20)  NULL,             
    customer_id_web   INT          NULL,             
    member_no         VARCHAR(10)  NULL,             
    buyer_hash        VARCHAR(20)  NULL,             
    nama_pelanggan    VARCHAR(120) NULL,
    gender            CHAR(1)      NULL,
    kota              VARCHAR(60)  NULL,             
    is_pelanggan_web  TINYINT(1)   NOT NULL DEFAULT 0,
    is_member_toko    TINYINT(1)   NOT NULL DEFAULT 0,
    is_pembeli_mpl    TINYINT(1)   NOT NULL DEFAULT 0,
    segmen_identitas  VARCHAR(20)  NOT NULL,        
    KEY idx_cust_web (customer_id_web),
    KEY idx_cust_member (member_no),
    KEY idx_cust_hash (buyer_hash)
) ENGINE=InnoDB;


CREATE TABLE dim_promo (
    promo_key             INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    kode_promo            VARCHAR(30)  NOT NULL,
    nama_kampanye         VARCHAR(100) NOT NULL,
    jenis_promo           VARCHAR(20)  NULL,
    kanal_promo           VARCHAR(20)  NULL,       
    tgl_mulai             DATE         NULL,
    tgl_selesai           DATE         NULL,
    target_diskon_persen  DECIMAL(5,2) NULL,
    pic                   VARCHAR(60)  NULL,
    UNIQUE KEY uq_promo (kode_promo, tgl_mulai),
    KEY idx_promo_periode (kanal_promo, tgl_mulai, tgl_selesai)
) ENGINE=InnoDB;

CREATE TABLE map_produk (
    sumber_sistem   VARCHAR(5)   NOT NULL,   
    kode_sumber     VARCHAR(40)  NOT NULL,   
    nama_sumber     VARCHAR(150) NULL,
    material_no     VARCHAR(40)  NOT NULL,
    metode_mapping  VARCHAR(60)  NOT NULL,
    PRIMARY KEY (sumber_sistem, kode_sumber)
) ENGINE=InnoDB;

CREATE TABLE err_kampanye (
    err_id                INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
    kode_promo            VARCHAR(30)  NULL,
    nama_kampanye         VARCHAR(100) NULL,
    jenis_promo           VARCHAR(20)  NULL,
    kanal                 VARCHAR(20)  NULL,
    tgl_mulai             VARCHAR(20)  NULL,
    tgl_selesai           VARCHAR(20)  NULL,
    target_diskon_persen  VARCHAR(20)  NULL,   
    pic                   VARCHAR(60)  NULL,
    error_count           INT          NULL,
    error_desc            VARCHAR(500) NULL,
    error_fields          VARCHAR(200) NULL,
    error_codes           VARCHAR(100) NULL,
    dicatat_pada          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE fact_penjualan (
    penjualan_id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    tanggal_key           INT           NOT NULL,
    produk_key            INT           NOT NULL,
    pelanggan_key         INT           NOT NULL,
    kanal_key             INT           NOT NULL,
    promo_key             INT           NOT NULL,
   
    sumber_sistem         VARCHAR(5)    NOT NULL,   
    no_transaksi          VARCHAR(40)   NOT NULL,   
    no_baris              VARCHAR(40)   NOT NULL,   
    waktu_transaksi_wib   DATETIME      NOT NULL,
    is_retur              TINYINT(1)    NOT NULL DEFAULT 0,
   
    qty                   INT           NOT NULL,
    harga_satuan          DECIMAL(15,2) NOT NULL,   
    penjualan_kotor       DECIMAL(18,2) NOT NULL,   
    diskon                DECIMAL(18,2) NOT NULL,   
    penjualan_bersih      DECIMAL(18,2) NOT NULL,   
    hpp                   DECIMAL(18,2) NULL,      
    fee_marketplace       DECIMAL(18,2) NOT NULL DEFAULT 0,  
    margin_kotor          DECIMAL(18,2) NULL,       
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


INSERT INTO dim_pelanggan (pelanggan_key, pelanggan_nk, nama_pelanggan, segmen_identitas)
VALUES (-1, 'UNKNOWN', 'Pembeli Toko Non-Member', 'UNKNOWN');

INSERT INTO dim_promo (promo_key, kode_promo, nama_kampanye, jenis_promo, kanal_promo)
VALUES (-1, 'TANPA_PROMO', 'Tanpa Promo / Tanpa Diskon', 'N/A', 'N/A'),
       (-2, 'TIDAK_TERIDENTIFIKASI', 'Diskon Tanpa Kampanye Valid', 'N/A', 'N/A');

INSERT INTO dim_produk (produk_key, material_no, nama_produk, status_produk,
                        berlaku_mulai, berlaku_sampai, is_current, is_inferred)
VALUES (-1, 'UNKNOWN', 'Produk Tidak Dikenal', 'UNKNOWN', '1900-01-01', '9999-12-31', 1, 1);
