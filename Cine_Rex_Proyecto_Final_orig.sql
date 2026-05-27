CREATE DATABASE CineRex;
USE CineRex;

CREATE TABLE Movies (
    movie_id INT PRIMARY KEY AUTO_INCREMENT,
    title  VARCHAR(150) NOT NULL,
    genre VARCHAR(60),
    duration_min INT,
    rating ENUM('AA', 'A', 'B', 'B15', 'C'),
    synopsis TEXT,
    is_now_playing BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ;


CREATE TABLE Theaters (
    theater_id INT PRIMARY KEY AUTO_INCREMENT,
    theater_name VARCHAR(50) NOT NULL,
    capacity INT NOT NULL,
    format ENUM('2D', '3D', 'IMAX', 'VIP') DEFAULT '2D',
    under_maintenance BOOLEAN DEFAULT FALSE
);


CREATE TABLE Seats (
    seat_id INT PRIMARY KEY AUTO_INCREMENT,
    theater_id INT NOT NULL,
    seat_row CHAR(1),
    seat_number INT,
    seat_type ENUM('General', 'Preferential', 'Disabled') DEFAULT 'General',
    FOREIGN KEY (theater_id) REFERENCES Theaters(theater_id)
);


CREATE TABLE Employees (
    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(100),
    tax_id VARCHAR(13) UNIQUE,
    job_title ENUM('Cashier', 'Supervisor', 'Manager', 'Janitor'),
    access_level INT DEFAULT 1,
    employee_status ENUM('Active', 'Inactive') DEFAULT 'Active',
    hire_date DATE DEFAULT (CURRENT_DATE)
);

CREATE TABLE Customers (
    customer_id INT PRIMARY KEY AUTO_INCREMENT,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    phone VARCHAR(15),
    loyalty_points INT DEFAULT 0,
    registration_date DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Showtimes (
    showtime_id INT PRIMARY KEY AUTO_INCREMENT,
    movie_id    INT,
    theater_id  INT,
    start_time  DATETIME ,
    base_price  DECIMAL(10,2),
    FOREIGN KEY (movie_id)   REFERENCES Movies(movie_id),
    FOREIGN KEY (theater_id) REFERENCES Theaters(theater_id)
);

CREATE TABLE Tickets (
    ticket_id  INT PRIMARY KEY AUTO_INCREMENT,
    showtime_id INT ,
    customer_id INT,
    employee_id INT,
    seat_id INT,
    amount_paid DECIMAL(10,2) NOT NULL,
    sale_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (showtime_id) REFERENCES Showtimes(showtime_id),
    FOREIGN KEY (customer_id) REFERENCES Customers(customer_id),
    FOREIGN KEY (employee_id) REFERENCES Employees(employee_id),
    FOREIGN KEY (seat_id)     REFERENCES Seats(seat_id)
);

CREATE TABLE Concession_Products (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    product_name VARCHAR(100) NOT NULL,
    cost_price DECIMAL(10,2),
    sale_price DECIMAL(10,2),
    current_stock INT DEFAULT 0,
    category ENUM('Snacks', 'Drinks', 'Combos', 'Promos'),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE Concession_Sales (
    concession_sale_id  INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT,
    employee_id INT NOT NULL,
    total_amount DECIMAL(10,2),
    sale_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES Customers(customer_id),
    FOREIGN KEY (employee_id) REFERENCES Employees(employee_id)
);


CREATE TABLE Concession_Sale_Items (
    item_id INT PRIMARY KEY AUTO_INCREMENT,
    concession_sale_id  INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2),
    subtotal DECIMAL(10,2),
    FOREIGN KEY (concession_sale_id) REFERENCES Concession_Sales(concession_sale_id),
    FOREIGN KEY (product_id) REFERENCES Concession_Products(product_id)
);

CREATE TABLE System_Audit (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    table_affected VARCHAR(50),
    operation_type VARCHAR(30),
    record_id INT,
    old_value TEXT,
    new_value TEXT,
    db_user VARCHAR(50),
    event_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DELIMITER //

CREATE TRIGGER tr_audit_price_change
AFTER UPDATE ON Concession_Products
FOR EACH ROW
BEGIN
    IF OLD.sale_price <> NEW.sale_price THEN
        INSERT INTO System_Audit (table_affected, operation_type, record_id, old_value, new_value, db_user)
        VALUES ('Concession_Products', 'PRICE_CHANGE', OLD.product_id,
                CONCAT('$', OLD.sale_price), CONCAT('$', NEW.sale_price), USER());
    END IF;
END //


CREATE TRIGGER tr_award_loyalty_points
AFTER INSERT ON Tickets
FOR EACH ROW
BEGIN
    IF NEW.customer_id IS NOT NULL THEN
        UPDATE Customers
        SET loyalty_points = loyalty_points + FLOOR(NEW.amount_paid * 0.15)
        WHERE customer_id = NEW.customer_id;
    END IF;
END //


CREATE TRIGGER tr_reduce_stock_on_sale
AFTER INSERT ON Concession_Sale_Items
FOR EACH ROW
BEGIN
    UPDATE Concession_Products
    SET current_stock = current_stock - NEW.quantity
    WHERE product_id = NEW.product_id;
END //

CREATE TRIGGER tr_prevent_double_booking
BEFORE INSERT ON Tickets
FOR EACH ROW
BEGIN
    DECLARE seat_taken INT;
    SELECT COUNT(*) INTO seat_taken
    FROM Tickets
    WHERE seat_id = NEW.seat_id AND showtime_id = NEW.showtime_id;

    IF seat_taken > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: This seat is already booked for this showtime.';
    END IF;
END //

CREATE TRIGGER tr_block_maintenance_theater
BEFORE INSERT ON Tickets
FOR EACH ROW
BEGIN
    DECLARE is_maintenance BOOLEAN;
    SELECT th.under_maintenance INTO is_maintenance
    FROM Showtimes s
    JOIN Theaters th ON s.theater_id = th.theater_id
    WHERE s.showtime_id = NEW.showtime_id;

    IF is_maintenance = TRUE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Theater is currently under maintenance. Sale not allowed.';
    END IF;
END //

CREATE TRIGGER tr_alert_out_of_stock
AFTER UPDATE ON Concession_Products
FOR EACH ROW
BEGIN
    IF NEW.current_stock <= 0 AND OLD.current_stock > 0 THEN
        INSERT INTO System_Audit (table_affected, operation_type, record_id, old_value, new_value, db_user)
        VALUES ('Concession_Products', 'OUT_OF_STOCK', NEW.product_id,
                CONCAT('Stock: ', OLD.current_stock), 'Stock: 0 — RESTOCK NEEDED', USER());
    END IF;
END //

CREATE TRIGGER tr_audit_customer_delete
BEFORE DELETE ON Customers
FOR EACH ROW
BEGIN
    INSERT INTO System_Audit (table_affected, operation_type, record_id, old_value, new_value, db_user)
    VALUES ('Customers', 'DELETE', OLD.customer_id,
            CONCAT(OLD.full_name, ' | ', OLD.email), 'RECORD DELETED', USER());
END //

CREATE TRIGGER tr_audit_showtime_price
AFTER UPDATE ON Showtimes
FOR EACH ROW
BEGIN
    IF OLD.base_price <> NEW.base_price THEN
        INSERT INTO System_Audit (table_affected, operation_type, record_id, old_value, new_value, db_user)
        VALUES ('Showtimes', 'PRICE_CHANGE', OLD.showtime_id,
                CONCAT('$', OLD.base_price), CONCAT('$', NEW.base_price), USER());
    END IF;
END //

DELIMITER ;


DELIMITER //
CREATE PROCEDURE sp_register_ticket_sale(
    IN p_showtime INT,
    IN p_customer INT,
    IN p_employee INT,
    IN p_seat INT,
    IN p_amount DECIMAL(10,2)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Transaction failed and was rolled back.' AS result;
    END;

    START TRANSACTION;
        INSERT INTO Tickets (showtime_id, customer_id, employee_id, seat_id, amount_paid)
        VALUES (p_showtime, p_customer, p_employee, p_seat, p_amount);
    COMMIT;
    SELECT 'Ticket sale registered successfully.' AS result;
END //

-- -------------------------------------------------------
CREATE PROCEDURE sp_register_concession_sale(
    IN p_customer INT,
    IN p_employee INT,
    IN p_product INT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_subtotal DECIMAL(10,2);
    DECLARE v_sale_id INT;
    DECLARE v_stock INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Concession sale failed and was rolled back.' AS result;
    END;

    SELECT sale_price, current_stock INTO v_price, v_stock
    FROM Concession_Products WHERE product_id = p_product;

    IF v_stock < p_quantity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'ERROR: Insufficient stock for this product.';
    END IF;

    SET v_subtotal = v_price * p_quantity;

    START TRANSACTION;
        INSERT INTO Concession_Sales (customer_id, employee_id, total_amount)
        VALUES (p_customer, p_employee, v_subtotal);

        SET v_sale_id = LAST_INSERT_ID();

        INSERT INTO Concession_Sale_Items (concession_sale_id, product_id, quantity, unit_price, subtotal)
        VALUES (v_sale_id, p_product, p_quantity, v_price, v_subtotal);
    COMMIT;
    SELECT 'Concession sale registered successfully.' AS result;
END //

CREATE PROCEDURE sp_revenue_report(
    IN p_start_date DATE,
    IN p_end_date   DATE
)
BEGIN
    SELECT
        DATE(t.sale_date)       AS sale_date,
        COUNT(t.ticket_id)      AS tickets_sold,
        SUM(t.amount_paid)      AS ticket_revenue,
        (SELECT COALESCE(SUM(cs.total_amount), 0)
         FROM Concession_Sales cs
         WHERE DATE(cs.sale_date) = DATE(t.sale_date)) AS concession_revenue,
        SUM(t.amount_paid) +
        (SELECT COALESCE(SUM(cs.total_amount), 0)
         FROM Concession_Sales cs
         WHERE DATE(cs.sale_date) = DATE(t.sale_date)) AS total_revenue
    FROM Tickets t
    WHERE DATE(t.sale_date) BETWEEN p_start_date AND p_end_date
    GROUP BY DATE(t.sale_date)
    ORDER BY sale_date DESC;
END //


CREATE PROCEDURE sp_register_customer(
    IN p_full_name  VARCHAR(100),
    IN p_email      VARCHAR(100),
    IN p_phone      VARCHAR(15)
)
BEGIN
    DECLARE v_exists INT;

    SELECT COUNT(*) INTO v_exists
    FROM Customers WHERE email = p_email;

    IF v_exists > 0 THEN
        SELECT 'ERROR: A customer with this email already exists.' AS result;
    ELSE
        INSERT INTO Customers (full_name, email, phone)
        VALUES (p_full_name, p_email, p_phone);
        SELECT 'Customer registered successfully.' AS result;
    END IF;
END //


CREATE PROCEDURE sp_redeem_loyalty_points(
    IN p_customer_id INT,
    IN p_points_to_use  INT
)
BEGIN
    DECLARE v_current_points INT;
    DECLARE v_discount DECIMAL(10,2);

    SELECT loyalty_points INTO v_current_points
    FROM Customers WHERE customer_id = p_customer_id;

    IF v_current_points < p_points_to_use THEN
        SELECT 'ERROR: Insufficient loyalty points.' AS result;
    ELSE
        SET v_discount = p_points_to_use * 0.10; -- $0.10 per point

        UPDATE Customers
        SET loyalty_points = loyalty_points - p_points_to_use
        WHERE customer_id = p_customer_id;

        INSERT INTO System_Audit (table_affected, operation_type, record_id, old_value, new_value, db_user)
        VALUES ('Customers', 'POINTS_REDEEMED', p_customer_id,
                CONCAT('Points before: ', v_current_points),
                CONCAT('Points used: ', p_points_to_use, ' | Discount: $', v_discount), USER());

        SELECT CONCAT('Success! ', p_points_to_use, ' points redeemed. Discount applied: $', v_discount) AS result;
    END IF;
END //

DELIMITER ;

CREATE VIEW View_Box_Office_Chart AS
SELECT
    m.movie_id,
    m.title AS movie,
    m.genre,
    m.rating,
    COUNT(t.ticket_id)AS tickets_sold,
    SUM(t.amount_paid) AS total_revenue,
    AVG(t.amount_paid) AS avg_ticket_price
FROM Movies m
JOIN Showtimes s ON m.movie_id   = s.movie_id
JOIN Tickets   t ON s.showtime_id = t.showtime_id
GROUP BY m.movie_id, m.title, m.genre, m.rating
ORDER BY total_revenue DESC;


CREATE  VIEW View_Inventory_Alert AS
SELECT
    product_id,
    product_name                    AS product,
    category,
    current_stock,
    sale_price,
    CASE
        WHEN current_stock = 0  THEN 'OUT OF STOCK'
        WHEN current_stock < 10 THEN 'CRITICAL'
        ELSE                         'LOW'
    END                             AS alert_level
FROM Concession_Products
WHERE current_stock < 20
ORDER BY current_stock ASC;


CREATE  VIEW View_Employee_Performance AS
SELECT
    e.employee_id,
    e.full_name AS employee,
    e.job_title,
    COUNT(t.ticket_id) AS tickets_sold,
    COALESCE(SUM(t.amount_paid), 0) AS ticket_revenue,
    COUNT(cs.concession_sale_id) AS concession_sales,
    COALESCE(SUM(cs.total_amount),0)AS concession_revenue
FROM Employees e
LEFT JOIN Tickets  t  ON e.employee_id = t.employee_id
LEFT JOIN Concession_Sales cs ON e.employee_id = cs.employee_id
WHERE e.employee_status = 'Active'
GROUP BY e.employee_id, e.full_name, e.job_title
ORDER BY ticket_revenue DESC;


CREATE VIEW View_Loyalty_Ranking AS
SELECT
    c.customer_id,
    c.full_name AS customer,
    c.email,
    c.loyalty_points,
    COUNT(t.ticket_id) AS total_visits,
    COALESCE(SUM(t.amount_paid), 0) AS total_spent,
    CASE
        WHEN c.loyalty_points >= 500 THEN 'GOLD'
        WHEN c.loyalty_points >= 200 THEN 'SILVER'
        ELSE                              'BRONZE'
    END                             AS loyalty_tier
FROM Customers c
LEFT JOIN Tickets t ON c.customer_id = t.customer_id
GROUP BY c.customer_id, c.full_name, c.email, c.loyalty_points
ORDER BY c.loyalty_points DESC;


CREATE VIEW View_Theater_Occupancy AS
SELECT
    s.showtime_id,
    m.title AS movie,
    th.theater_name AS theater,
    th.format,
    s.start_time,
    th.capacity  AS total_seats,
    COUNT(t.ticket_id) AS seats_sold,
    ROUND(COUNT(t.ticket_id) * 100.0 / th.capacity, 2) AS occupancy_pct
FROM Showtimes s
JOIN Movies   m  ON s.movie_id   = m.movie_id
JOIN Theaters th ON s.theater_id = th.theater_id
LEFT JOIN Tickets t ON s.showtime_id = t.showtime_id
GROUP BY s.showtime_id, m.title, th.theater_name, th.format, s.start_time, th.capacity
ORDER BY s.start_time DESC;

-- Audit log: last 30 days of system changes
CREATE  VIEW View_Recent_Audit_Log AS
SELECT
    log_id,
    table_affected AS table_name,
    operation_type,
    record_id,
    old_value,
    new_value,
    db_user AS changed_by,
    event_timestamp AS changed_at
FROM System_Audit
WHERE event_timestamp >= NOW() - INTERVAL 30 DAY
ORDER BY event_timestamp DESC;


CREATE VIEW View_Daily_Revenue AS
SELECT DATE(sale_date) AS sale_date, 'Tickets' AS source,
       COUNT(ticket_id) AS transactions, SUM(amount_paid) AS revenue
FROM Tickets GROUP BY DATE(sale_date)
UNION ALL
SELECT DATE(sale_date), 'Concessions',
       COUNT(concession_sale_id), SUM(total_amount)
FROM Concession_Sales GROUP BY DATE(sale_date)
ORDER BY sale_date DESC, source;


INSERT INTO Movies (title, genre, duration_min, rating, synopsis) VALUES
('Joker: Folie à Deux',  'Drama/Thriller', 138, 'C',   'Arthur Fleck navigates life in Arkham Asylum alongside Harley Quinn.'),
('Moana 2',              'Animation',      100, 'AA',  'Moana embarks on a new voyage across the seas of Oceania.'),
('Gladiator II',         'Action',         148, 'B15', 'The epic sequel set in ancient Rome.'),
('Inside Out 2',         'Animation',       96, 'AA',  'Riley faces new emotions as she enters her teenage years.'),
('Dune: Part Two',       'Sci-Fi',         166, 'B15', 'Paul Atreides leads the Fremen against the Harkonnens.'),
('The Substance',        'Horror',         141, 'C',   'A faded celebrity uses a mysterious substance with dark consequences.');


INSERT INTO Theaters (theater_name, capacity, format) VALUES
('Theater 1 — IMAX',  120, 'IMAX'),
('Theater 2 — VIP',    40, 'VIP'),
('Theater 3 — 3D',     80, '3D'),
('Theater 4 — 2D',    100, '2D');


INSERT INTO Seats (theater_id, seat_row, seat_number, seat_type) VALUES
(1, 'A', 1, 'General'), (1, 'A', 2, 'General'), (1, 'A', 3, 'General'),
(1, 'B', 1, 'General'), (1, 'B', 2, 'Preferential'), (1, 'B', 3, 'Preferential'),
(2, 'F', 1, 'Preferential'), (2, 'F', 2, 'Preferential'),
(3, 'C', 1, 'General'), (3, 'C', 2, 'General'),
(1, 'D', 1, 'Disabled'), (1, 'D', 2, 'Disabled');


INSERT INTO Employees (full_name, tax_id, job_title, access_level) VALUES
('Hanna Martinez',  'HAMA900101ABC', 'Manager',    3),
('Pedro Lopez',     'PELO850215XYZ', 'Cashier',    1),
('Sofia Ramirez',   'RASO920530DEF', 'Supervisor', 2),
('Carlos Mendez',   'MECA880720GHI', 'Cashier',    1),
('Laura Torres',    'TOLA950414JKL', 'Cashier',    1);


INSERT INTO Customers (full_name, email, phone, loyalty_points) VALUES
('Juan Perez',      'juan.perez@gmail.com',   '6641234567', 350),
('Jane Smith',      'jane.smith@email.com',   '6649876543', 520),
('Maria Gonzalez',  'maria.g@outlook.com',    '6643456789', 80),
('Luis Herrera',    'luis.h@gmail.com',       '6645678901', 210),
('Ana Castillo',    'ana.castillo@mail.com',  '6642345678', 0),
('Robert Brown',    'r.brown@email.com',      '6647890123', 175);


INSERT INTO Showtimes (movie_id, theater_id, start_time, base_price) VALUES
(1, 1, '2026-05-26 20:00:00', 130.00),
(2, 2, '2026-05-26 16:00:00', 190.00),
(3, 3, '2026-05-26 18:30:00', 110.00),
(4, 4, '2026-05-27 14:00:00',  90.00),
(5, 1, '2026-05-27 21:00:00', 130.00),
(6, 3, '2026-05-27 19:00:00', 110.00);


INSERT INTO Concession_Products (product_name, cost_price, sale_price, current_stock, category) VALUES
('Large Popcorn',       20.00,  85.00, 120, 'Snacks'),
('Medium Popcorn',      15.00,  65.00,  90, 'Snacks'),
('Jumbo Soda',          10.00,  45.00, 200, 'Drinks'),
('Medium Soda',          8.00,  35.00, 180, 'Drinks'),
('Hot Dog',             18.00,  70.00,  60, 'Snacks'),
('Nachos with Cheese',  22.00,  90.00,  40, 'Snacks'),
('Combo 1 (L.Pop+Soda)',30.00, 120.00,  15, 'Combos'),  
('Candy Box',            5.00,  30.00,   8, 'Snacks'),  
('Premium Combo VIP',   45.00, 175.00,  25, 'Combos'),
('Water Bottle',         5.00,  25.00, 300, 'Drinks');

INSERT INTO Tickets (showtime_id, customer_id, employee_id, seat_id, amount_paid) VALUES
(1, 1, 2, 1, 130.00),
(1, 2, 2, 2, 130.00),
(2, 3, 4, 7, 190.00),
(3, 4, 5, 9, 110.00),
(4, 5, 2, 10, 90.00),
(1, 6, 4, 3, 130.00);

INSERT INTO Concession_Sales (customer_id, employee_id, total_amount) VALUES
(1, 2, 205.00),
(2, 4, 120.00),
(3, 5,  85.00);

INSERT INTO Concession_Sale_Items (concession_sale_id, product_id, quantity, unit_price, subtotal) VALUES
(1, 1, 1, 85.00,  85.00),  
(1, 3, 2, 45.00,  90.00),  
(1, 5, 1, 70.00,  70.00),  
(2, 7, 1, 120.00,120.00),  
(3, 2, 1, 65.00,  65.00);  

USE cinerex;

USE cinerex;

INSERT INTO System_Audit (table_affected, operation_type, record_id, old_value, new_value, db_user) VALUES
('Movies','INSERT',1,NULL,'Title: Dune Part Two','admin'),
('Tickets','UPDATE',3,'status: pending','status: used','empleado1'),
('Customers','INSERT',7,NULL,'Name: Maria Gonzalez','admin'),
('Concession_Products','DELETE',2,'product: Medium Popcorn','RECORD DELETED','gerente'),
('Showtimes','UPDATE',4,'Theater 2 — 16:00','Theater 2 — 17:00','admin'),
('Concession_Sales','INSERT',5,NULL,'Total: $85.00','cajero1'),
('Employees','UPDATE',1,'salary: $15000','salary: $16500','admin'),
('Tickets','INSERT',8,NULL,'Movie: Gladiator II | Amount: $110','cajero2'),
('Movies','UPDATE',3,'rating: B','rating: A','admin'),
('Seats','DELETE',10,'seat: C2 — General','RECORD DELETED','gerente');


CALL sp_register_customer('Diego Ruiz', 'diego.ruiz@mail.com', '6648765432');

CALL sp_register_ticket_sale(2, 1, 2, 8, 190.00);

CALL sp_register_concession_sale(1, 2, 9, 1);

CALL sp_revenue_report('2026-05-20', '2026-05-27');

CALL sp_redeem_loyalty_points(2, 100);

SELECT * FROM View_Box_Office_Chart;
SELECT * FROM View_Inventory_Alert;
SELECT * FROM View_Employee_Performance;
SELECT * FROM View_Loyalty_Ranking;
SELECT * FROM View_Theater_Occupancy;
SELECT * FROM View_Recent_Audit_Log;
SELECT * FROM View_Daily_Revenue;

SELECT * FROM View_Loyalty_Ranking WHERE loyalty_tier = 'GOLD';

SELECT * FROM View_Theater_Occupancy WHERE occupancy_pct < 50;
