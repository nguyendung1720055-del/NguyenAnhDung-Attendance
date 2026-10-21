-- Additive upgrade only: choose the attendance database before execution.
-- Safe to run again; preserves all existing attendance, accounts and reviews.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @lockResult int; EXEC @lockResult = sys.sp_getapplock @Resource = N'NguyenAnhDung.AttendanceIncidents.Schema', @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;
IF @lockResult < 0 THROW 51000, 'Could not acquire attendance incident schema lock.', 1;
IF OBJECT_ID(N'dbo.AttendanceIncidents', N'U') IS NULL
BEGIN
CREATE TABLE [AttendanceIncidents] (
    [Id] uniqueidentifier NOT NULL,
    [ErrorCode] nvarchar(32) NOT NULL,
    [OfficeSnapshotKey] nvarchar(64) NOT NULL,
    [OfficeName] nvarchar(160) NOT NULL,
    [FirstOccurredAtUtc] datetime2 NOT NULL,
    [LastOccurredAtUtc] datetime2 NOT NULL,
    [Status] nvarchar(16) NOT NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_AttendanceIncidents] PRIMARY KEY ([Id])
);
END;
IF OBJECT_ID(N'dbo.AttendanceFailureAttempts', N'U') IS NULL
BEGIN
CREATE TABLE [AttendanceFailureAttempts] (
    [Id] uniqueidentifier NOT NULL,
    [EmployeeId] uniqueidentifier NOT NULL,
    [IncidentId] uniqueidentifier NULL,
    [OfficeSnapshotKey] nvarchar(64) NOT NULL,
    [ErrorCode] nvarchar(32) NOT NULL,
    [OfficeName] nvarchar(160) NOT NULL,
    [Operation] nvarchar(16) NOT NULL,
    [OccurredAtUtc] datetime2 NOT NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_AttendanceFailureAttempts] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_AttendanceFailureAttempts_AttendanceIncidents_IncidentId] FOREIGN KEY ([IncidentId]) REFERENCES [AttendanceIncidents] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_AttendanceFailureAttempts_Employees_EmployeeId] FOREIGN KEY ([EmployeeId]) REFERENCES [Employees] ([Id]) ON DELETE NO ACTION
);
END;
IF OBJECT_ID(N'dbo.AttendanceIncidentParticipants', N'U') IS NULL
BEGIN
CREATE TABLE [AttendanceIncidentParticipants] (
    [Id] uniqueidentifier NOT NULL,
    [IncidentId] uniqueidentifier NOT NULL,
    [EmployeeId] uniqueidentifier NOT NULL,
    [FirstAttemptAtUtc] datetime2 NOT NULL,
    [LastAttemptAtUtc] datetime2 NOT NULL,
    [AttemptCount] int NOT NULL,
    [Status] nvarchar(16) NOT NULL,
    [ReviewNote] nvarchar(1000) NULL,
    [ReviewerId] uniqueidentifier NULL,
    [ReviewedAtUtc] datetime2 NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_AttendanceIncidentParticipants] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_AttendanceIncidentParticipants_AttendanceIncidents_IncidentId] FOREIGN KEY ([IncidentId]) REFERENCES [AttendanceIncidents] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_AttendanceIncidentParticipants_Employees_EmployeeId] FOREIGN KEY ([EmployeeId]) REFERENCES [Employees] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_AttendanceIncidentParticipants_Employees_ReviewerId] FOREIGN KEY ([ReviewerId]) REFERENCES [Employees] ([Id]) ON DELETE NO ACTION
);
END;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AttendanceFailureAttempts') AND name = N'IX_AttendanceFailureAttempts_EmployeeId')
CREATE INDEX [IX_AttendanceFailureAttempts_EmployeeId] ON [AttendanceFailureAttempts] ([EmployeeId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AttendanceFailureAttempts') AND name = N'IX_AttendanceFailureAttempts_IncidentId')
CREATE INDEX [IX_AttendanceFailureAttempts_IncidentId] ON [AttendanceFailureAttempts] ([IncidentId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AttendanceFailureAttempts') AND name = N'IX_AttendanceFailureAttempts_OfficeSnapshotKey_ErrorCode_OccurredAtUtc')
CREATE INDEX [IX_AttendanceFailureAttempts_OfficeSnapshotKey_ErrorCode_OccurredAtUtc] ON [AttendanceFailureAttempts] ([OfficeSnapshotKey], [ErrorCode], [OccurredAtUtc]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AttendanceIncidentParticipants') AND name = N'IX_AttendanceIncidentParticipants_EmployeeId')
CREATE INDEX [IX_AttendanceIncidentParticipants_EmployeeId] ON [AttendanceIncidentParticipants] ([EmployeeId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AttendanceIncidentParticipants') AND name = N'IX_AttendanceIncidentParticipants_IncidentId_EmployeeId')
CREATE UNIQUE INDEX [IX_AttendanceIncidentParticipants_IncidentId_EmployeeId] ON [AttendanceIncidentParticipants] ([IncidentId], [EmployeeId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AttendanceIncidentParticipants') AND name = N'IX_AttendanceIncidentParticipants_ReviewerId')
CREATE INDEX [IX_AttendanceIncidentParticipants_ReviewerId] ON [AttendanceIncidentParticipants] ([ReviewerId]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.AttendanceIncidents') AND name = N'IX_AttendanceIncidents_OfficeSnapshotKey_ErrorCode_LastOccurredAtUtc')
CREATE INDEX [IX_AttendanceIncidents_OfficeSnapshotKey_ErrorCode_LastOccurredAtUtc] ON [AttendanceIncidents] ([OfficeSnapshotKey], [ErrorCode], [LastOccurredAtUtc]);
COMMIT TRANSACTION;
