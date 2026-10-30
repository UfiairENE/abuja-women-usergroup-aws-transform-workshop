# SQL Server → Aurora PostgreSQL workshop target

Terraform for a private, KMS-encrypted, multi-AZ Aurora PostgreSQL cluster (the migration
target), plus an optional small private instance for loading the converted schema into it.

## 1. The problem: moving off SQL Server

Moving from SQL Server to PostgreSQL is more than copying data. The two engines differ,
so the work is mostly conversion:

- **Schema:** data types, identity columns, indexes and constraints map differently.
- **T-SQL code:** stored procedures, functions, triggers and views are written in T-SQL
  and must be rewritten in PL/pgSQL. This is usually the slowest part, because every
  object is converted, fixed and tested by hand.
- **Dependencies:** objects reference each other, so conversion order matters and one
  failure can block others.
- **Application code:** .NET code that uses SQL Server drivers and T-SQL must be changed
  to talk to PostgreSQL.
- **Data:** it has to be moved and checked against the source.

Done manually, each of these is a separate, repetitive effort.

## 2. The tool: AWS Transform

[AWS Transform](https://docs.aws.amazon.com/transform/latest/userguide/sql-server-modernization.html)
is an agentic AI service that modernizes Windows workloads. For SQL Server it automates:

- assessing the source database
- converting the schema, including T-SQL stored procedures to PL/pgSQL
- migrating data with AWS DMS
- transforming the associated .NET application code

This workshop covers the first two: assessment and schema conversion. It then loads one row
of data with a small script. It does not use DMS or touch application code. See "What we cover
today" below.

## 3. What happens in the workshop

1. **Upload:** you zip your SQL Server DDL and upload it in the AWS Transform chat. Use
   [sample-ddl/RetailDemo-ddl.zip](sample-ddl/RetailDemo-ddl.zip) (source:
   [sample-ddl/RetailDemo/](sample-ddl/RetailDemo/)): one schema, one table and one procedure
   that sends email with Database Mail, which PostgreSQL can't do. The zip copies the layout
   of Transform's own extraction script: a folder named after the database, with one file per
   object type (`schemas.sql`, `tables.sql`, `primary_keys.sql`, `stored_procedures.sql`), each
   statement followed by `GO`. If the agent asks which database the objects belong to, type
   `RetailDemo`.
2. **Assess:** Transform reads the zip, counts the objects, estimates the effort and lists
   what needs a person.
3. **Steer the plan:** Transform proposes a plan and waits. You tell it what to run. Here
   you tell it to convert only, because its default plan also builds its own, much larger,
   Aurora cluster, and to map `BIT` columns to `BOOLEAN`.
4. **Convert:** Transform converts the schema and checks its own work in a validation sandbox.
   It runs in the background, so start it early or show a finished run.
5. **Review:** you read the validation reports and the converted SQL. Database Mail has no
   PostgreSQL equivalent, so Transform leaves that procedure as an `UNCONVERTIBLE` stub for a
   person to rewrite.
6. **Load:** you run the converted SQL against the Aurora cluster in this stack (section 6),
   then load one row of data with a small script. Transform can also build and deploy to its
   own cluster, but this workshop does not use that.

### What we cover today

- The original SQL Server table failing on PostgreSQL, and why migrations are hard.
- Building the target with Terraform: a private, encrypted Aurora PostgreSQL cluster.
- AWS Transform: assessing the database, steering the plan, converting the schema and the
  stored procedure, and reading its validation reports.
- Loading the converted schema into Aurora and checking it with `psql`.
- Loading one row of data with a script.

### What we do not cover today

- Moving real data at scale. You would use AWS DMS for that, and we do not run it.
- Transforming .NET application code.
- Letting Transform provision and deploy its own cluster. We switch that off in the plan.
- Running Transform's extraction script against a live SQL Server.
- Rewriting the email procedure with Amazon SES or SNS. Transform leaves it as a stub.

## 4. What this Terraform creates

- A private VPC with no internet gateway or NAT, and private subnets across three AZs.
- A KMS-encrypted, multi-AZ Aurora PostgreSQL cluster (writer plus reader).
- Optional (`enable_ssm_client`): a `t4g.nano` instance reached through Session Manager, with
  three Session Manager VPC endpoints, for running `psql` against the cluster.
- A free S3 gateway endpoint, so that instance can download packages without internet.
- Security groups, IAM and a KMS key.

**Region:** AWS Transform for SQL Server is only available in some regions. This stack
defaults to `eu-west-2` (London), which is supported. Create the Transform workspace in
the same region as the stack. Check the
[supported regions](https://docs.aws.amazon.com/transform/latest/userguide/sql-server-modernization.html)
before changing `aws_region`.

## 5. Setup

You need Terraform (1.6 or newer), the AWS CLI, [just](https://github.com/casey/just),
a free [Terraform Cloud](https://app.terraform.io) account, and an AWS account where you
can create IAM roles.

1. **Create the Terraform Cloud org and workspace.** In Terraform Cloud create an
   organization (lowercase letters, numbers, `-` and `_`, no spaces) and a workspace named
   `workshop-aurora-pg`. Choose the CLI-driven workflow.
2. **Set your org name in two places.** Replace the org in the `cloud {}` block in
   `01-providers.tf`. The default in `bootstrap/main.tf` (`tfc_organization`) must match,
   or pass it in step 5 with `-var tfc_organization=<org>`.
3. **Copy the variables file.** `cp example.tfvars workshop.tfvars` and edit it: region,
   AZs, CIDRs and instance class. The AZs must belong to the region. `workshop.tfvars` is
   git-ignored. `just workshop` passes it to the remote run with `-var-file`, so you don't
   enter the values in Terraform Cloud.
4. **Get AWS admin credentials for the bootstrap step only.** Terraform Cloud can't deploy
   anything until the role exists, so bootstrap runs once from your machine. Use an IAM
   user with `AdministratorAccess` and an access key, then
   `aws configure --profile transform-workshop` and `export AWS_PROFILE=transform-workshop`.
   Check it with `aws sts get-caller-identity`. Don't use root keys. If you do, delete the
   key straight after the apply.
5. **Create the Terraform Cloud OIDC provider, if your account lacks one.** Bootstrap
   looks it up and fails with "no matching IAM OpenID Connect Provider found" if it's
   missing. Check with `aws iam list-open-id-connect-providers` and look for
   `app.terraform.io`. If it's absent:
   ```
   aws iam create-open-id-connect-provider \
     --url https://app.terraform.io \
     --client-id-list aws.workload.identity
   ```
6. **Bootstrap (once):**
   ```
   cd bootstrap
   terraform init
   terraform apply
   ```
   Review the plan. It creates one IAM role, `tfc-oidc-workshop`, with
   `AdministratorAccess`, trusted only by your org and workspace. Copy the `role_arn` output.
   Keep `bootstrap/terraform.tfstate`: you need it to tear down.
7. **Remove the bootstrap credentials.** Delete the access key in the AWS console and run
   `unset AWS_PROFILE`.
8. **Set two environment variables** (not Terraform variables) in the Terraform Cloud
   workspace: `TFC_AWS_PROVIDER_AUTH=true` and `TFC_AWS_RUN_ROLE_ARN=<role_arn>`.
9. **Deploy.** `terraform login`, then `just workshop` (or
   `terraform init && terraform apply -var-file=workshop.tfvars`). The first run
   asks to set up the workspace state. Answer `yes`.

## 6. Load the converted schema into Aurora

Transform gives you SQL files. This step runs them against the private cluster, using a small
instance you reach with Session Manager (no SSH, no public IP, no internet).

1. In `workshop.tfvars` set `enable_ssm_client = true` (it is already set in `example.tfvars`),
   then `just workshop`. It adds a `t4g.nano` instance, three Session Manager VPC endpoints and
   the security-group rules it needs. Note the `ssm_client_instance_id`, `writer_endpoint` and
   `secret_arn` outputs.
2. Open a shell on the instance. In the console: EC2, select the instance, Connect, Session
   Manager. Or from your terminal (needs the Session Manager plugin):
   `aws ssm start-session --target <ssm_client_instance_id> --region eu-west-2`
3. Install the PostgreSQL client. The VPC has no internet, but the package repository is served
   from S3 through the VPC endpoint:
   `sudo dnf install -y postgresql16`
4. Get the database password. In the console: Secrets Manager, open the `secret_arn`, Retrieve
   secret value, copy `password`. Or, from your own terminal:
   `aws secretsmanager get-secret-value --secret-id <secret_arn> --query SecretString --output text`
5. In the Session Manager shell, connect (the user is `postgres_admin`, the database is `workshop`):
   ```
   export PGPASSWORD='<password>'
   psql "host=<writer_endpoint> port=5432 dbname=workshop user=postgres_admin sslmode=require"
   ```
6. Check the "before". Type `\dn`. It lists only `public`, so the database is empty.
7. Try the original SQL Server table on PostgreSQL. Paste the contents of
   [sample-ddl/RetailDemo/tables.sql](sample-ddl/RetailDemo/tables.sql) at the prompt. It
   fails with `ERROR:  syntax error at or near "["`, and the `GO` line fails too. Nothing is
   created. Square brackets around names, `IDENTITY(1,1)`, `NVARCHAR` and `BIT` are all SQL
   Server only. Every object in a real database has this problem. The prompt changes to
   `workshop->` because the stray `GO` is still waiting in the buffer. Type `\r` to clear it
   before you paste anything else.
8. Read Transform's output before you run it. Open
   [sample-ddl/RetailDemo-converted.sql](sample-ddl/RetailDemo-converted.sql) next to the source
   ([sample-ddl/RetailDemo/](sample-ddl/RetailDemo/)) and find three things:
   - the schema name: `sales` became `retaildemo_sales` (Transform adds the database name);
   - the `IsActive` column: `BIT ... DEFAULT ((1))` became `BOOLEAN ... DEFAULT TRUE`, because
     the plan asked for it;
   - the email procedure: the body is now a `RAISE EXCEPTION` and the original lines are
     commented out. Transform would not guess at Database Mail.
9. Paste the whole file at the `workshop=>` prompt. You should get four lines back:
   `CREATE SCHEMA`, `CREATE TABLE`, `ALTER TABLE`, `CREATE PROCEDURE`.
10. Check the "after":
   ```
   \dn
   \d retaildemo_sales.customer
   ```
   `\dn` now lists `retaildemo_sales`. `\d` shows the table: `customerid` is an identity column,
   `fullname` is `varchar(100)`, `email` is `varchar(255)`, `isactive` is a `boolean` defaulting
   to `true`, and `pk_customer` is the primary key.

11. Load the one row of data. Paste
    [sample-ddl/RetailDemo-data.sql](sample-ddl/RetailDemo-data.sql), then:
    ```
    SELECT * FROM retaildemo_sales.customer;
    ```
    You should see one row: `customerid` 1 and `isactive` as `t`. The `customerid` filled itself
    in, which is the identity column Transform converted.

**Not covered here:** moving real data at scale with AWS DMS, and application code. See
"What we do not cover today" above.

## 7. Teardown

Deletion protection is on for the Aurora cluster. Turn it off first: RDS console, select the
cluster, Modify. Then run `just destroy`, then `cd bootstrap && terraform destroy`.
