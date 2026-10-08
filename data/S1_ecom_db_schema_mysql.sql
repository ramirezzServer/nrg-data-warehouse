DROP DATABASE IF EXISTS nrg_ecom;
CREATE DATABASE nrg_ecom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE nrg_ecom;

CREATE TABLE categories (
    category_id         INT PRIMARY KEY,
    parent_category_id  INT NULL,
    category_name       VARCHAR(60) NOT NULL,
    FOREIGN KEY (parent_category_id) REFERENCES categories(category_id)
) ENGINE=InnoDB;

CREATE TABLE products (
    product_id      INT AUTO_INCREMENT PRIMARY KEY,
    sku             VARCHAR(40) NOT NULL UNIQUE,
    category_id     INT NOT NULL,
    product_name    VARCHAR(150) NOT NULL,
    brand           VARCHAR(60),
    base_price      DECIMAL(15,2) NOT NULL,   -- SUDAH termasuk PPN 11%
    is_active       BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (category_id) REFERENCES categories(category_id)
) ENGINE=InnoDB;

CREATE TABLE customers (
    customer_id     INT AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(120) NOT NULL,
    email           VARCHAR(120) UNIQUE NOT NULL,
    phone           VARCHAR(20),               -- format +62...
    gender          CHAR(1),
    birth_date      DATE,
    registered_at   DATETIME NOT NULL
) ENGINE=InnoDB;

CREATE TABLE customer_addresses (
    address_id      INT AUTO_INCREMENT PRIMARY KEY,
    customer_id     INT NOT NULL,
    label           VARCHAR(30),
    address_line    VARCHAR(200),
    city            VARCHAR(60),
    province        VARCHAR(60),
    postal_code     VARCHAR(10),
    is_primary      BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
) ENGINE=InnoDB;

CREATE TABLE vouchers (
    voucher_id      INT AUTO_INCREMENT PRIMARY KEY,
    promo_code      VARCHAR(30) NOT NULL,
    discount_type   VARCHAR(10) NOT NULL,
    discount_value  DECIMAL(10,2) NOT NULL,
    min_purchase    DECIMAL(15,2) DEFAULT 0,
    quota           INT,
    valid_from      DATE,
    valid_to        DATE
) ENGINE=InnoDB;

CREATE TABLE orders (
    order_id            VARCHAR(20) PRIMARY KEY,
    customer_id         INT NOT NULL,
    order_ts            DATETIME NOT NULL,
    status              VARCHAR(20) NOT NULL,
    voucher_id          INT NULL,
    payment_method      VARCHAR(20),
    shipping_fee        DECIMAL(12,2) DEFAULT 0,
    shipping_address_id INT NULL,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (voucher_id) REFERENCES vouchers(voucher_id),
    FOREIGN KEY (shipping_address_id) REFERENCES customer_addresses(address_id)
) ENGINE=InnoDB;

CREATE TABLE order_items (
    order_item_id   INT AUTO_INCREMENT PRIMARY KEY,
    order_id        VARCHAR(20) NOT NULL,
    line_no         SMALLINT NOT NULL,
    product_id      INT NULL,
    sku             VARCHAR(40) NOT NULL,
    qty             INT NOT NULL,
    unit_price      DECIMAL(15,2) NOT NULL,
    disc_amount     DECIMAL(15,2) DEFAULT 0,
    UNIQUE KEY uq_order_line (order_id, line_no),
    FOREIGN KEY (order_id) REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
) ENGINE=InnoDB;

CREATE TABLE order_status_history (
    history_id      INT AUTO_INCREMENT PRIMARY KEY,
    order_id        VARCHAR(20) NOT NULL,
    status          VARCHAR(20) NOT NULL,
    changed_at      DATETIME NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
) ENGINE=InnoDB;

CREATE TABLE payments (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    order_id        VARCHAR(20) NOT NULL,
    provider        VARCHAR(30),
    amount          DECIMAL(15,2) NOT NULL,
    paid_at         DATETIME,
    status          VARCHAR(15),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
) ENGINE=InnoDB;

CREATE TABLE shipments (
    shipment_id     INT AUTO_INCREMENT PRIMARY KEY,
    order_id        VARCHAR(20) NOT NULL,
    courier         VARCHAR(30),
    tracking_no     VARCHAR(30),
    shipped_at      DATETIME,
    delivered_at    DATETIME NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
) ENGINE=InnoDB;

CREATE TABLE order_returns (
    return_id       INT AUTO_INCREMENT PRIMARY KEY,
    order_item_id   INT NOT NULL,
    qty             INT NOT NULL,
    reason          VARCHAR(100),
    refund_amount   DECIMAL(15,2),
    status          VARCHAR(15),
    requested_at    DATETIME,
    FOREIGN KEY (order_item_id) REFERENCES order_items(order_item_id)
) ENGINE=InnoDB;

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_ts       ON orders(order_ts);
CREATE INDEX idx_items_order     ON order_items(order_id);
CREATE INDEX idx_payments_order  ON payments(order_id);
