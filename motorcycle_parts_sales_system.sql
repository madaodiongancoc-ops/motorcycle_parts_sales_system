-- ============================================================================
-- MOTORCYCLE PARTS SALES SYSTEM - FULL DATABASE SCHEMA
-- ============================================================================
-- Covers: retail/wholesale/accessories sales, stock tracking, model/brand
-- compatibility, revenue reporting (daily/weekly/monthly), bulk discounts,
-- payments (GCash, Installment, Credit/Debit, Cash) with installment balance
-- tracking, product condition (new/second-hand/surplus/OEM), product status
-- ("still good to sell"), stock status, role-based accounts, delivery +
-- tracking, price comparison, pre-orders, featured items, invoices & receipts.
--
-- Engine: InnoDB | Charset: utf8mb4
-- ============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE DATABASE IF NOT EXISTS motorcycle_parts_sales
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE motorcycle_parts_sales;

-- ============================================================================
-- SECTION 1: ROLES, BRANCHES, USERS (Role-based accounts)
-- ============================================================================

CREATE TABLE roles (
  role_id       INT AUTO_INCREMENT PRIMARY KEY,
  role_name     VARCHAR(50) NOT NULL UNIQUE,   -- Super Admin, Manager, Cashier, Inventory Staff, Delivery Staff
  description   VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE branches (
  branch_id       INT AUTO_INCREMENT PRIMARY KEY,
  branch_name     VARCHAR(100) NOT NULL,
  address         VARCHAR(255),
  contact_number  VARCHAR(20),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE users (
  user_id         INT AUTO_INCREMENT PRIMARY KEY,
  branch_id       INT NULL,
  role_id         INT NOT NULL,
  username        VARCHAR(50) NOT NULL UNIQUE,
  password_hash   VARCHAR(255) NOT NULL,
  full_name       VARCHAR(100) NOT NULL,
  email           VARCHAR(100),
  contact_number  VARCHAR(20),
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_users_role   FOREIGN KEY (role_id)   REFERENCES roles(role_id),
  CONSTRAINT fk_users_branch FOREIGN KEY (branch_id) REFERENCES branches(branch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 2: MOTORCYCLE BRANDS & MODELS (for parts compatibility)
-- ============================================================================

CREATE TABLE motorcycle_brands (
  brand_id    INT AUTO_INCREMENT PRIMARY KEY,
  brand_name  VARCHAR(100) NOT NULL UNIQUE       -- Honda, Yamaha, Suzuki, Kawasaki, etc.
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE motorcycle_models (
  model_id             INT AUTO_INCREMENT PRIMARY KEY,
  brand_id             INT NOT NULL,
  model_name           VARCHAR(100) NOT NULL,     -- Click 125i, Mio Sporty, Raider 150, etc.
  year_start           YEAR,
  year_end             YEAR,
  engine_displacement  VARCHAR(20),                -- e.g. 125cc
  CONSTRAINT fk_model_brand FOREIGN KEY (brand_id) REFERENCES motorcycle_brands(brand_id),
  UNIQUE KEY uq_brand_model (brand_id, model_name, year_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 3: PRODUCT CATALOG (parts + accessories, retail/wholesale/2nd-hand/surplus/OEM)
-- ============================================================================

CREATE TABLE product_categories (
  category_id        INT AUTO_INCREMENT PRIMARY KEY,
  category_name      VARCHAR(100) NOT NULL,        -- Engine Parts, Body Parts, Electrical, Accessories...
  parent_category_id INT NULL,
  CONSTRAINT fk_category_parent FOREIGN KEY (parent_category_id) REFERENCES product_categories(category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE suppliers (
  supplier_id      INT AUTO_INCREMENT PRIMARY KEY,
  supplier_name    VARCHAR(150) NOT NULL,
  contact_person   VARCHAR(100),
  contact_number   VARCHAR(20),
  email            VARCHAR(100),
  address          VARCHAR(255),
  supplier_type    ENUM('manufacturer','distributor','surplus_dealer','individual') NOT NULL DEFAULT 'distributor'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE products (
  product_id       INT AUTO_INCREMENT PRIMARY KEY,
  sku              VARCHAR(50) NOT NULL UNIQUE,
  product_name     VARCHAR(150) NOT NULL,
  category_id      INT NULL,
  supplier_id      INT NULL,

  product_type     ENUM('part','accessory') NOT NULL DEFAULT 'part',
  condition_type   ENUM('brand_new','second_hand','surplus','oem','aftermarket') NOT NULL DEFAULT 'brand_new',

  description      TEXT,
  unit_of_measure  VARCHAR(20) NOT NULL DEFAULT 'pc',
  is_universal_fit BOOLEAN NOT NULL DEFAULT FALSE,   -- fits all models (e.g. generic oil, bulbs)

  -- "should this product still be sold" flag
  product_status   ENUM('active','inactive','damaged','expired','discontinued','recalled') NOT NULL DEFAULT 'active',

  is_featured      BOOLEAN NOT NULL DEFAULT FALSE,
  featured_from    DATE NULL,
  featured_until   DATE NULL,

  allow_preorder   BOOLEAN NOT NULL DEFAULT FALSE,

  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  CONSTRAINT fk_product_category FOREIGN KEY (category_id) REFERENCES product_categories(category_id),
  CONSTRAINT fk_product_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(supplier_id),
  INDEX idx_product_status (product_status),
  INDEX idx_product_featured (is_featured, featured_from, featured_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Parts compatibility: many-to-many between products and motorcycle models
CREATE TABLE product_compatibility (
  compatibility_id INT AUTO_INCREMENT PRIMARY KEY,
  product_id       INT NOT NULL,
  model_id         INT NOT NULL,
  notes            VARCHAR(255),
  CONSTRAINT fk_compat_product FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,
  CONSTRAINT fk_compat_model   FOREIGN KEY (model_id)   REFERENCES motorcycle_models(model_id) ON DELETE CASCADE,
  UNIQUE KEY uq_product_model (product_id, model_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 4: PRICING & BULK DISCOUNTS (supports price comparison before checkout)
-- ============================================================================

CREATE TABLE product_pricing (
  pricing_id         INT AUTO_INCREMENT PRIMARY KEY,
  product_id         INT NOT NULL,
  retail_price       DECIMAL(12,2) NOT NULL,
  wholesale_price     DECIMAL(12,2) NOT NULL,
  wholesale_min_qty   INT NOT NULL DEFAULT 1,       -- minimum qty to qualify for wholesale price
  cost_price          DECIMAL(12,2),                 -- for margin/profit reporting
  effective_date      DATE NOT NULL DEFAULT (CURRENT_DATE),
  is_current          BOOLEAN NOT NULL DEFAULT TRUE,  -- only one current price row per product (enforced at app level)
  created_by          INT NULL,
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pricing_product FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,
  CONSTRAINT fk_pricing_user    FOREIGN KEY (created_by) REFERENCES users(user_id),
  INDEX idx_pricing_current (product_id, is_current)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE bulk_discount_rules (
  rule_id        INT AUTO_INCREMENT PRIMARY KEY,
  product_id     INT NULL,                          -- NULL = not limited to one product
  category_id    INT NULL,                          -- NULL = not limited to one category
  min_quantity   INT NOT NULL,                       -- qty that triggers this discount tier
  discount_type  ENUM('percent','fixed_amount') NOT NULL DEFAULT 'percent',
  discount_value DECIMAL(10,2) NOT NULL,
  applies_to     ENUM('retail','wholesale','both') NOT NULL DEFAULT 'wholesale',
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_bulk_product  FOREIGN KEY (product_id)  REFERENCES products(product_id) ON DELETE CASCADE,
  CONSTRAINT fk_bulk_category FOREIGN KEY (category_id) REFERENCES product_categories(category_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 5: INVENTORY / STOCK TRACKING (per branch, with movement log)
-- ============================================================================

CREATE TABLE inventory (
  inventory_id       INT AUTO_INCREMENT PRIMARY KEY,
  product_id         INT NOT NULL,
  branch_id          INT NOT NULL,
  quantity_on_hand   INT NOT NULL DEFAULT 0,
  reorder_level      INT NOT NULL DEFAULT 5,
  reserved_qty       INT NOT NULL DEFAULT 0,          -- reserved for pre-orders / pending orders
  updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE,
  CONSTRAINT fk_inventory_branch  FOREIGN KEY (branch_id)  REFERENCES branches(branch_id) ON DELETE CASCADE,
  UNIQUE KEY uq_product_branch (product_id, branch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE stock_movements (
  movement_id     INT AUTO_INCREMENT PRIMARY KEY,
  product_id      INT NOT NULL,
  branch_id       INT NOT NULL,
  movement_type   ENUM('stock_in','stock_out','adjustment','transfer_in','transfer_out','return','damage') NOT NULL,
  quantity        INT NOT NULL,                       -- always positive; movement_type gives direction
  reference_type  ENUM('purchase','sale','order_cancel','manual','preorder_reserve') NOT NULL DEFAULT 'manual',
  reference_id    INT NULL,                           -- e.g. order_id, purchase_id
  remarks         VARCHAR(255),
  performed_by    INT NULL,
  movement_date   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_movement_product FOREIGN KEY (product_id)   REFERENCES products(product_id),
  CONSTRAINT fk_movement_branch  FOREIGN KEY (branch_id)    REFERENCES branches(branch_id),
  CONSTRAINT fk_movement_user    FOREIGN KEY (performed_by) REFERENCES users(user_id),
  INDEX idx_movement_product_branch (product_id, branch_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 6: CUSTOMERS
-- ============================================================================

CREATE TABLE customers (
  customer_id     INT AUTO_INCREMENT PRIMARY KEY,
  customer_type   ENUM('retail','wholesale') NOT NULL DEFAULT 'retail',
  full_name       VARCHAR(150) NOT NULL,
  contact_number  VARCHAR(20),
  email           VARCHAR(100),
  address         VARCHAR(255),
  business_name   VARCHAR(150),                       -- for wholesale accounts
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 7: ORDERS / SALES (retail, wholesale, pre-order)
-- ============================================================================

CREATE TABLE orders (
  order_id        INT AUTO_INCREMENT PRIMARY KEY,
  order_number    VARCHAR(30) NOT NULL UNIQUE,
  branch_id       INT NOT NULL,
  customer_id     INT NULL,
  cashier_id      INT NOT NULL,

  sale_type       ENUM('retail','wholesale') NOT NULL DEFAULT 'retail',
  order_category  ENUM('regular','pre_order') NOT NULL DEFAULT 'regular',
  order_status    ENUM('pending','processing','completed','cancelled','refunded') NOT NULL DEFAULT 'pending',

  subtotal        DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount_total  DECIMAL(12,2) NOT NULL DEFAULT 0,
  tax_total       DECIMAL(12,2) NOT NULL DEFAULT 0,
  grand_total     DECIMAL(12,2) NOT NULL DEFAULT 0,

  needs_delivery  BOOLEAN NOT NULL DEFAULT FALSE,

  order_date      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  CONSTRAINT fk_order_branch   FOREIGN KEY (branch_id)   REFERENCES branches(branch_id),
  CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
  CONSTRAINT fk_order_cashier  FOREIGN KEY (cashier_id)  REFERENCES users(user_id),
  INDEX idx_order_date (order_date),
  INDEX idx_order_status (order_status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE order_items (
  order_item_id    INT AUTO_INCREMENT PRIMARY KEY,
  order_id         INT NOT NULL,
  product_id       INT NOT NULL,
  quantity         INT NOT NULL,
  unit_price       DECIMAL(12,2) NOT NULL,             -- price actually applied (retail or wholesale) at time of sale
  discount_amount  DECIMAL(12,2) NOT NULL DEFAULT 0,
  line_total       DECIMAL(12,2) NOT NULL,
  CONSTRAINT fk_orderitem_order   FOREIGN KEY (order_id)   REFERENCES orders(order_id) ON DELETE CASCADE,
  CONSTRAINT fk_orderitem_product FOREIGN KEY (product_id) REFERENCES products(product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE preorder_details (
  preorder_id                 INT AUTO_INCREMENT PRIMARY KEY,
  order_item_id               INT NOT NULL,
  expected_availability_date  DATE,
  preorder_status             ENUM('awaiting_stock','ready_for_pickup','converted_to_sale','cancelled') NOT NULL DEFAULT 'awaiting_stock',
  down_payment                DECIMAL(12,2) NOT NULL DEFAULT 0,
  notes                       VARCHAR(255),
  CONSTRAINT fk_preorder_orderitem FOREIGN KEY (order_item_id) REFERENCES order_items(order_item_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 8: PAYMENTS (GCash, Cash, Credit/Debit, Installment) + balance tracking
-- ============================================================================

CREATE TABLE payment_methods (
  method_id    INT AUTO_INCREMENT PRIMARY KEY,
  method_name  VARCHAR(30) NOT NULL UNIQUE            -- GCash, Cash, Credit Card, Debit Card, Installment
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE payments (
  payment_id        INT AUTO_INCREMENT PRIMARY KEY,
  order_id          INT NOT NULL,
  method_id         INT NOT NULL,
  amount            DECIMAL(12,2) NOT NULL,
  reference_number  VARCHAR(100),                      -- GCash ref no., card approval code, etc.
  payment_date      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  received_by       INT NOT NULL,
  CONSTRAINT fk_payment_order  FOREIGN KEY (order_id)    REFERENCES orders(order_id) ON DELETE CASCADE,
  CONSTRAINT fk_payment_method FOREIGN KEY (method_id)   REFERENCES payment_methods(method_id),
  CONSTRAINT fk_payment_user   FOREIGN KEY (received_by) REFERENCES users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE installment_plans (
  plan_id              INT AUTO_INCREMENT PRIMARY KEY,
  order_id             INT NOT NULL UNIQUE,
  total_amount         DECIMAL(12,2) NOT NULL,
  down_payment         DECIMAL(12,2) NOT NULL DEFAULT 0,
  remaining_balance    DECIMAL(12,2) NOT NULL,
  term_months          INT NOT NULL,
  monthly_due_amount   DECIMAL(12,2) NOT NULL,
  start_date           DATE NOT NULL,
  due_day_of_month     TINYINT,                          -- e.g. 15
  plan_status          ENUM('active','completed','defaulted','cancelled') NOT NULL DEFAULT 'active',
  CONSTRAINT fk_plan_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE installment_payments (
  installment_payment_id INT AUTO_INCREMENT PRIMARY KEY,
  plan_id                INT NOT NULL,
  payment_id              INT NOT NULL,                  -- links to the actual payment record (method used)
  amount_paid             DECIMAL(12,2) NOT NULL,
  balance_before          DECIMAL(12,2) NOT NULL,
  balance_after           DECIMAL(12,2) NOT NULL,
  payment_date            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_instpay_plan    FOREIGN KEY (plan_id)    REFERENCES installment_plans(plan_id) ON DELETE CASCADE,
  CONSTRAINT fk_instpay_payment FOREIGN KEY (payment_id) REFERENCES payments(payment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 9: DELIVERY & TRACKING
-- ============================================================================

CREATE TABLE deliveries (
  delivery_id       INT AUTO_INCREMENT PRIMARY KEY,
  order_id          INT NOT NULL UNIQUE,
  recipient_name    VARCHAR(150) NOT NULL,
  delivery_address  VARCHAR(255) NOT NULL,
  contact_number    VARCHAR(20),
  rider_name        VARCHAR(100),
  courier_service   VARCHAR(100),                        -- if outsourced to 3rd-party courier
  tracking_number   VARCHAR(100),
  delivery_fee      DECIMAL(10,2) NOT NULL DEFAULT 0,
  delivery_status   ENUM('pending','preparing','out_for_delivery','delivered','failed','returned') NOT NULL DEFAULT 'pending',
  scheduled_date    DATE,
  delivered_at      TIMESTAMP NULL,
  remarks           VARCHAR(255),
  CONSTRAINT fk_delivery_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE delivery_status_history (
  history_id    INT AUTO_INCREMENT PRIMARY KEY,
  delivery_id   INT NOT NULL,
  status        ENUM('pending','preparing','out_for_delivery','delivered','failed','returned') NOT NULL,
  status_date   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by    INT NULL,
  notes         VARCHAR(255),
  CONSTRAINT fk_history_delivery FOREIGN KEY (delivery_id) REFERENCES deliveries(delivery_id) ON DELETE CASCADE,
  CONSTRAINT fk_history_user     FOREIGN KEY (updated_by)  REFERENCES users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- SECTION 10: INVOICES & RECEIPTS
-- ============================================================================

CREATE TABLE invoices (
  invoice_id      INT AUTO_INCREMENT PRIMARY KEY,
  order_id        INT NOT NULL UNIQUE,
  invoice_number  VARCHAR(30) NOT NULL UNIQUE,
  issued_date     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  issued_by       INT NOT NULL,
  CONSTRAINT fk_invoice_order FOREIGN KEY (order_id)  REFERENCES orders(order_id),
  CONSTRAINT fk_invoice_user  FOREIGN KEY (issued_by) REFERENCES users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE receipts (
  receipt_id      INT AUTO_INCREMENT PRIMARY KEY,
  payment_id      INT NOT NULL,
  receipt_number  VARCHAR(30) NOT NULL UNIQUE,
  issued_date     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  issued_by       INT NOT NULL,
  CONSTRAINT fk_receipt_payment FOREIGN KEY (payment_id) REFERENCES payments(payment_id),
  CONSTRAINT fk_receipt_user    FOREIGN KEY (issued_by)  REFERENCES users(user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================================
-- SECTION 11: VIEWS - stock status, price comparison, featured items, revenue
-- ============================================================================

-- Stock status per product per branch (in_stock / low_stock / out_of_stock / pre_order_available)
CREATE OR REPLACE VIEW v_stock_status AS
SELECT
  i.product_id,
  p.sku,
  p.product_name,
  i.branch_id,
  b.branch_name,
  i.quantity_on_hand,
  i.reorder_level,
  i.reserved_qty,
  (i.quantity_on_hand - i.reserved_qty) AS available_qty,
  CASE
    WHEN p.product_status <> 'active' THEN 'not_for_sale'
    WHEN i.quantity_on_hand <= 0 AND p.allow_preorder = TRUE THEN 'pre_order_available'
    WHEN i.quantity_on_hand <= 0 THEN 'out_of_stock'
    WHEN i.quantity_on_hand <= i.reorder_level THEN 'low_stock'
    ELSE 'in_stock'
  END AS stock_status
FROM inventory i
JOIN products p ON p.product_id = i.product_id
JOIN branches b ON b.branch_id = i.branch_id;

-- Price comparison (retail vs wholesale) for checkout screen
CREATE OR REPLACE VIEW v_price_comparison AS
SELECT
  p.product_id,
  p.sku,
  p.product_name,
  p.condition_type,
  pr.retail_price,
  pr.wholesale_price,
  pr.wholesale_min_qty,
  ROUND(pr.retail_price - pr.wholesale_price, 2) AS savings_if_wholesale
FROM products p
JOIN product_pricing pr ON pr.product_id = p.product_id AND pr.is_current = TRUE;

-- Currently active featured items
CREATE OR REPLACE VIEW v_featured_products AS
SELECT p.product_id, p.sku, p.product_name, p.condition_type, pr.retail_price
FROM products p
JOIN product_pricing pr ON pr.product_id = p.product_id AND pr.is_current = TRUE
WHERE p.is_featured = TRUE
  AND p.product_status = 'active'
  AND (p.featured_from IS NULL OR p.featured_from <= CURDATE())
  AND (p.featured_until IS NULL OR p.featured_until >= CURDATE());

-- Revenue: daily / weekly / monthly (completed orders only)
CREATE OR REPLACE VIEW v_daily_sales AS
SELECT DATE(order_date) AS sales_date, branch_id, sale_type,
       SUM(grand_total) AS total_revenue, COUNT(*) AS total_orders
FROM orders
WHERE order_status = 'completed'
GROUP BY DATE(order_date), branch_id, sale_type;

CREATE OR REPLACE VIEW v_weekly_sales AS
SELECT YEAR(order_date) AS sales_year, WEEK(order_date, 1) AS sales_week, branch_id, sale_type,
       SUM(grand_total) AS total_revenue, COUNT(*) AS total_orders
FROM orders
WHERE order_status = 'completed'
GROUP BY YEAR(order_date), WEEK(order_date, 1), branch_id, sale_type;

CREATE OR REPLACE VIEW v_monthly_sales AS
SELECT YEAR(order_date) AS sales_year, MONTH(order_date) AS sales_month, branch_id, sale_type,
       SUM(grand_total) AS total_revenue, COUNT(*) AS total_orders
FROM orders
WHERE order_status = 'completed'
GROUP BY YEAR(order_date), MONTH(order_date), branch_id, sale_type;

-- Installment accounts with outstanding balance
CREATE OR REPLACE VIEW v_installment_balances AS
SELECT ip.plan_id, ip.order_id, o.order_number, c.full_name AS customer_name,
       ip.total_amount, ip.down_payment, ip.remaining_balance,
       ip.term_months, ip.monthly_due_amount, ip.plan_status
FROM installment_plans ip
JOIN orders o ON o.order_id = ip.order_id
LEFT JOIN customers c ON c.customer_id = o.customer_id;

-- ============================================================================
-- SECTION 12: TRIGGER - enforce "product_status" sellability rule
-- ============================================================================

DELIMITER $$

CREATE TRIGGER trg_orderitems_check_sellable
BEFORE INSERT ON order_items
FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(20);
  SELECT product_status INTO v_status FROM products WHERE product_id = NEW.product_id;
  IF v_status <> 'active' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'This product is not currently sellable (status is not active).';
  END IF;
END$$

DELIMITER ;

-- ============================================================================
-- SECTION 13: SEED DATA (lookups only)
-- ============================================================================

INSERT INTO roles (role_name, description) VALUES
  ('Super Admin', 'Full system access'),
  ('Manager', 'Branch-level management, reports, pricing'),
  ('Cashier', 'Process sales, payments, issue receipts'),
  ('Inventory Staff', 'Manage stock levels and stock movements'),
  ('Delivery Staff', 'Manage deliveries and delivery status');

INSERT INTO payment_methods (method_name) VALUES
  ('Cash'), ('GCash'), ('Credit Card'), ('Debit Card'), ('Installment');

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================
