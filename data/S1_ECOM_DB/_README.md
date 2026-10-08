# S1 E-Commerce Database

## Cara Menjalankan

1. **Import database schema**
   Import file `S1_ecom_db_schema_mysql.sql` ke MySQL untuk membuat database dan seluruh tabel.

2. **Load data CSV**
   Pastikan folder `S1_ECOM_DB` dan file `load_all.py` berada pada lokasi yang sesuai, kemudian jalankan:

   ```bash
   python load_all.py
   ```

Script akan membaca data dari file CSV dan memasukkannya ke database `nrg_ecom`.
