CREATE PROCEDURE sales.uspNotifyCustomer @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @email NVARCHAR(255);
    SELECT @email = Email FROM sales.Customer WHERE CustomerId = @CustomerId;

    EXEC msdb.dbo.sp_send_dbmail
        @recipients = @email,
        @subject    = N'Hello',
        @body       = N'Welcome aboard.';
END;
GO
