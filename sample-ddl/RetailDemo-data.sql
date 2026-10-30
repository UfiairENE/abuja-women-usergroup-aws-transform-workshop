-- The one row from the original SQL Server table, written for PostgreSQL.
-- The column names are lowercase and IsActive is a real boolean, as Transform converted them.
INSERT INTO retaildemo_sales.customer (fullname, email, isactive)
VALUES ('Ada Okafor', 'ada@example.com', true);
