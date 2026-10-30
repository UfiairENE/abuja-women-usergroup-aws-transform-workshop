-- The pretend on-premises SQL Server: the original database, with one row in it.
CREATE DATABASE RetailDemo;
GO
USE RetailDemo;
GO
CREATE SCHEMA sales;
GO
CREATE TABLE sales.Customer (
    CustomerId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    FullName   NVARCHAR(100)     NOT NULL,
    Email      NVARCHAR(255)     NOT NULL,
    IsActive   BIT               NOT NULL DEFAULT 1
);
GO
INSERT INTO sales.Customer (FullName, Email) VALUES (N'Ada Okafor', N'ada@example.com');
GO
