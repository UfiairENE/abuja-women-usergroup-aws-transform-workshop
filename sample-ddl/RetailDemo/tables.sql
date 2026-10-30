CREATE TABLE [sales].[Customer] (
    [CustomerId] INT IDENTITY(1,1) NOT NULL,
    [FullName] NVARCHAR(100) NOT NULL,
    [Email] NVARCHAR(255) NOT NULL,
    [IsActive] BIT NOT NULL DEFAULT ((1))
);
GO
