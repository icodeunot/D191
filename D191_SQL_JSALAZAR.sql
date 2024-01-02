ROLLBACK;
-- **************************** SECTION B ****************************


-- Drop the function if it exists 
DROP FUNCTION IF EXISTS transform_data(); 
-- The transform_data() function is used to manipulate data types. (Display purposes only)
CREATE OR REPLACE FUNCTION transform_data() 
RETURNS TABLE ( 
    discount text, 
    rental_month text 
	)
	LANGUAGE plpgsql
AS $$ 
BEGIN 
    RETURN QUERY 
    WITH CustomerRentals AS ( -- CTE made to count rentals/month for each customer 
        SELECT 
            customer_id, 
            TO_CHAR(rental_date, 'Month') AS rental_month, 
            COUNT(rental_id) AS rental_count 
        FROM 
            rental 
        GROUP BY 
            customer_id, rental_month 
    ) 
    SELECT 
        CASE -- This allows the results of the CTE to be compared for the appropriate discount 
            WHEN cr.rental_count BETWEEN 9 AND 19 THEN '10% OFF' 
            WHEN cr.rental_count > 19 THEN '25% OFF' 
            WHEN c.active = 0 THEN 'Free Return' 
            ELSE '5% OFF' 
      END AS discount,  
        cr.rental_month 
    FROM 
        CustomerRentals cr 
    INNER JOIN customer c ON cr.customer_id = c.customer_id 
    ORDER BY c.customer_id 
    LIMIT 5; -- Limit the results for display purposes 
END; 
$$; 

-- Call the function and display the results 
SELECT * FROM transform_data();


-- **************************** SECTION C ****************************


-- This function creates the "Detailed" section of the business report and calls the empty table
DROP TABLE IF EXISTS detailed;
CREATE TABLE detailed (
	"Discount" text,
	customer_id smallint,
	active integer,
	email character varying (50),
	rental_month text,
	rental_count bigint,
	"Tier A rewards" bigint
);
-- Call the empty table
SELECT * FROM detailed;

-- This function creates the "summary" section of the business report and calls the empty table
DROP TABLE IF EXISTS summary;
CREATE TABLE summary (
	"Discount" text,
	customer_id integer,
	email character varying (50),
	rental_month text
);
-- Call the empty table
SELECT * FROM summary;


-- **************************** SECTION D ****************************


DELETE FROM detailed; -- Refresh the data and removes anything that has been erased from 'dvdrental' database
-- Create Common Table Expression to gather rental statistics for Rewards program
WITH CustomerRentals AS (
    SELECT
        customer_id,
        TO_CHAR(rental_date, 'Month') AS rental_month,
        COUNT(rental_id) AS rental_count
    FROM
        rental
    GROUP BY
        customer_id, rental_month
)

INSERT INTO detailed (
    "Discount",
    customer_id,
    active,
    email,
    rental_month,
    rental_count,
    "Tier A rewards"
)
SELECT
	CASE
		WHEN cr.rental_count BETWEEN 9 AND 19 THEN '10% OFF'
		WHEN cr.rental_count > 19 THEN '25% OFF'
		WHEN c.active = 0 THEN 'Free Return'
		ELSE '5% OFF'
	END AS "Discount",
    cr.customer_id,
	c.active,
	c.email,
    cr.rental_month,
    cr.rental_count,
	-- The sub-statement below filters the rental_count field for a number 10 or higher
	(SELECT COUNT(DISTINCT customer_id) FROM CustomerRentals WHERE rental_count > 9) AS "Tier A Rewards"
FROM
    CustomerRentals cr
	INNER JOIN customer c ON cr.customer_id = c.customer_id
	-- WHERE c.active = 0 -- (Filters for active patients)
ORDER BY
    2 desc;
	
-- Call the table to show results, verify data
SELECT * FROM detailed;


-- **************************** SECTION E ****************************


-- Drop any existing trigger or function for this section
DROP TRIGGER IF EXISTS update_summary ON detailed;
DROP FUNCTION IF EXISTS update_summary();

-- The update_summary() function used to fill the summary table	
CREATE OR REPLACE FUNCTION update_summary()
	RETURNS TRIGGER
	LANGUAGE PLPGSQL
AS $$
BEGIN
	DELETE FROM summary; -- Clears out summary table for refresh
	INSERT INTO summary (
    	"Discount",
    	customer_id,
    	email,
    	rental_month
	)
	-- Pull the data from the "detailed" section of the report.
	SELECT "Discount", customer_id, email, rental_month FROM detailed
	WHERE rental_month LIKE '%July%'; -- (EXAMPLE ONLY)
	-- WHERE rental_month LIKE '%' || TO_CHAR(CURRENT_DATE - INTERVAL '1 month', 'Month') || '%';
	RETURN NULL;
END;
$$;

-- The update_summary TRIGGER that will be used any time the detailed table has an INSERT performed
CREATE TRIGGER update_summary
AFTER INSERT ON detailed
FOR EACH STATEMENT
EXECUTE FUNCTION update_summary();	

-- Use Insert statement to trigger update_summary TRIGGER and FUNCTION
INSERT INTO detailed (
    "Discount",
    customer_id,
    active,
    email,
    rental_month,
    rental_count,
    "Tier A rewards"
)
VALUES
(NULL, NULL, NULL, NULL, NULL, NULL, NULL);

--Display results AND VERIFY DATA
SELECT* FROM summary
ORDER BY customer_id asc;


-- **************************** SECTION F ****************************


-- ********** RUN THIS CODE TO DISPLAY EMPTY TABLES **********
ROLLBACK;
DELETE FROM detailed;
DELETE FROM summary;
SELECT * FROM detailed;
SELECT * FROM summary;

-- FULL STORED PROCEDURE FOR REPORT
CREATE OR REPLACE PROCEDURE fill_report()
LANGUAGE plpgsql
AS $$
BEGIN

-- ********** CREATE EMPTY TABLES (DROP IF THEY EXIST ALREADY)**********

DROP TABLE IF EXISTS detailed; -- DETAILED
CREATE TABLE detailed (
	"Discount" text,
	customer_id smallint,
	active integer,
	email character varying (50),
	rental_month text,
	rental_count bigint,
	"Tier A rewards" bigint
);
DROP TABLE IF EXISTS summary; -- SUMMARY
CREATE TABLE summary (
	"Discount" text,
	customer_id integer,
	email character varying (50),
	rental_month text
);

-- ********** CREATE TRIGGER AND FUNCTION FOR REPORT DATA **********

DROP TRIGGER IF EXISTS update_summary ON detailed;
DROP FUNCTION IF EXISTS update_summary();

-- update_summary() function used to fill the summary table	
CREATE OR REPLACE FUNCTION update_summary()
	RETURNS TRIGGER
	LANGUAGE PLPGSQL
AS $inner$
BEGIN
	DELETE FROM summary; -- Clears out summary table for refresh
	INSERT INTO summary (
    	"Discount",
    	customer_id,
    	email,
    	rental_month
	)
	-- Pull the data from the "detailed" section of the report.
	SELECT "Discount", customer_id, email, rental_month FROM detailed
	WHERE rental_month LIKE '%July%'; -- (EXAMPLE ONLY)
	-- WHERE rental_month LIKE '%' || TO_CHAR(CURRENT_DATE - INTERVAL '1 month', 'Month') || '%';
	RETURN NULL;
END;
$inner$;

-- update_summary TRIGGER fired with INSERT on detailed table
CREATE TRIGGER update_summary
AFTER INSERT ON detailed
FOR EACH STATEMENT
EXECUTE FUNCTION update_summary();	

-- ********** FILL DETAILED TABLE WITH RAW DATA **********

DELETE FROM detailed; -- Refresh the data and removes anything that has been erased from 'dvdrental' database
-- Create Common Table Expression to gather rental statistics for Rewards program
WITH CustomerRentals AS (
    SELECT
        customer_id,
        TO_CHAR(rental_date, 'Month') AS rental_month,
        COUNT(rental_id) AS rental_count
    FROM
        rental
    GROUP BY
        customer_id, rental_month
)

INSERT INTO detailed (
    "Discount",
    customer_id,
    active,
    email,
    rental_month,
    rental_count,
    "Tier A rewards"
)
SELECT
	CASE
		WHEN cr.rental_count BETWEEN 9 AND 19 THEN '10% OFF'
		WHEN cr.rental_count > 19 THEN '25% OFF'
		WHEN c.active = 0 THEN 'Free Return'
		ELSE '5% OFF'
	END AS "Discount",
    cr.customer_id,
	c.active,
	c.email,
    cr.rental_month,
    cr.rental_count,
	-- The sub-statement below filters the rental_count field for a number 10 or higher
	(SELECT COUNT(DISTINCT customer_id) FROM CustomerRentals WHERE rental_count > 9) AS "Tier A Rewards"
FROM
    CustomerRentals cr
	INNER JOIN customer c ON cr.customer_id = c.customer_id
	-- WHERE c.active = 0 -- (Filters for active patients)
ORDER BY
    2 desc;
END;
$$;

-- ********** Call the stored procedure, SELECT the tables and verify the data
CALL fill_report();
SELECT * FROM detailed;
SELECT * FROM summary;