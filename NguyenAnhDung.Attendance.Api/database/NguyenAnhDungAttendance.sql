-- NguyenAnhDungAttendance: SQL Server schema generated from the EF Core SQL Server model.
-- Run once on a fresh database. For existing databases use Upgrade-AttendanceIncidents.sql.

IF DB_ID(N'NguyenAnhDungAttendance') IS NULL
    CREATE DATABASE [NguyenAnhDungAttendance];
GO
USE [NguyenAnhDungAttendance];
GO

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
GO


CREATE TABLE [CompanySettings] (
    [Id] int NOT NULL,
    [OfficeName] nvarchar(160) NOT NULL,
    [Latitude] float NOT NULL,
    [Longitude] float NOT NULL,
    [RadiusMeters] float NOT NULL,
    [MaxAccuracyMeters] float NOT NULL,
    [QrLifetimeSeconds] int NOT NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_CompanySettings] PRIMARY KEY ([Id])
);
GO


CREATE TABLE [Departments] (
    [Id] uniqueidentifier NOT NULL,
    [Name] nvarchar(120) NOT NULL,
    [Description] nvarchar(600) NOT NULL,
    CONSTRAINT [PK_Departments] PRIMARY KEY ([Id])
);
GO


CREATE TABLE [Shifts] (
    [Id] uniqueidentifier NOT NULL,
    [Name] nvarchar(120) NOT NULL,
    [StartTime] time NOT NULL,
    [EndTime] time NOT NULL,
    [GraceMinutes] int NOT NULL,
    CONSTRAINT [PK_Shifts] PRIMARY KEY ([Id])
);
GO


CREATE TABLE [Employees] (
    [Id] uniqueidentifier NOT NULL,
    [Username] nvarchar(40) NOT NULL,
    [NormalizedUsername] nvarchar(40) NOT NULL,
    [Email] nvarchar(254) NOT NULL,
    [NormalizedEmail] nvarchar(254) NOT NULL,
    [FullName] nvarchar(160) NOT NULL,
    [PasswordHash] nvarchar(max) NOT NULL,
    [Role] nvarchar(16) NOT NULL,
    [DepartmentId] uniqueidentifier NULL,
    [ShiftId] uniqueidentifier NULL,
    [IsActive] bit NOT NULL,
    [EmailVerified] bit NOT NULL,
    [FailedLoginAttempts] int NOT NULL,
    [LockedUntilUtc] datetime2 NULL,
    [CreatedAtUtc] datetime2 NOT NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_Employees] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_Employees_Departments_DepartmentId] FOREIGN KEY ([DepartmentId]) REFERENCES [Departments] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_Employees_Shifts_ShiftId] FOREIGN KEY ([ShiftId]) REFERENCES [Shifts] ([Id]) ON DELETE NO ACTION
);
GO


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
GO


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
GO


CREATE TABLE [Attendances] (
    [Id] uniqueidentifier NOT NULL,
    [EmployeeId] uniqueidentifier NOT NULL,
    [WorkDate] date NOT NULL,
    [CheckInAtUtc] datetime2 NOT NULL,
    [CheckOutAtUtc] datetime2 NULL,
    [IsLate] bit NOT NULL,
    [Latitude] float NOT NULL,
    [Longitude] float NOT NULL,
    [AccuracyMeters] float NOT NULL,
    [MotionScore] float NOT NULL,
    [CheckoutLatitude] float NULL,
    [CheckoutLongitude] float NULL,
    [CheckoutAccuracyMeters] float NULL,
    [CheckoutMotionScore] float NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_Attendances] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_Attendances_Employees_EmployeeId] FOREIGN KEY ([EmployeeId]) REFERENCES [Employees] ([Id]) ON DELETE NO ACTION
);
GO


CREATE TABLE [EmailChallenges] (
    [Id] uniqueidentifier NOT NULL,
    [EmployeeId] uniqueidentifier NOT NULL,
    [Purpose] nvarchar(20) NOT NULL,
    [CodeHash] nvarchar(64) NOT NULL,
    [CreatedAtUtc] datetime2 NOT NULL,
    [ExpiresAtUtc] datetime2 NOT NULL,
    [Attempts] int NOT NULL,
    [Consumed] bit NOT NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_EmailChallenges] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_EmailChallenges_Employees_EmployeeId] FOREIGN KEY ([EmployeeId]) REFERENCES [Employees] ([Id]) ON DELETE CASCADE
);
GO


CREATE TABLE [LeaveRequests] (
    [Id] uniqueidentifier NOT NULL,
    [EmployeeId] uniqueidentifier NOT NULL,
    [Type] nvarchar(16) NOT NULL,
    [StartDate] date NOT NULL,
    [EndDate] date NOT NULL,
    [Reason] nvarchar(2000) NOT NULL,
    [Status] nvarchar(16) NOT NULL,
    [ReviewNote] nvarchar(1000) NULL,
    [ReviewerId] uniqueidentifier NULL,
    [CreatedAtUtc] datetime2 NOT NULL,
    [ReviewedAtUtc] datetime2 NULL,
    [Version] rowversion NOT NULL,
    CONSTRAINT [PK_LeaveRequests] PRIMARY KEY ([Id]),
    CONSTRAINT [FK_LeaveRequests_Employees_EmployeeId] FOREIGN KEY ([EmployeeId]) REFERENCES [Employees] ([Id]) ON DELETE NO ACTION,
    CONSTRAINT [FK_LeaveRequests_Employees_ReviewerId] FOREIGN KEY ([ReviewerId]) REFERENCES [Employees] ([Id]) ON DELETE NO ACTION
);
GO


CREATE INDEX [IX_AttendanceFailureAttempts_EmployeeId] ON [AttendanceFailureAttempts] ([EmployeeId]);
GO


CREATE INDEX [IX_AttendanceFailureAttempts_IncidentId] ON [AttendanceFailureAttempts] ([IncidentId]);
GO


CREATE INDEX [IX_AttendanceFailureAttempts_OfficeSnapshotKey_ErrorCode_OccurredAtUtc] ON [AttendanceFailureAttempts] ([OfficeSnapshotKey], [ErrorCode], [OccurredAtUtc]);
GO


CREATE INDEX [IX_AttendanceIncidentParticipants_EmployeeId] ON [AttendanceIncidentParticipants] ([EmployeeId]);
GO


CREATE UNIQUE INDEX [IX_AttendanceIncidentParticipants_IncidentId_EmployeeId] ON [AttendanceIncidentParticipants] ([IncidentId], [EmployeeId]);
GO


CREATE INDEX [IX_AttendanceIncidentParticipants_ReviewerId] ON [AttendanceIncidentParticipants] ([ReviewerId]);
GO


CREATE INDEX [IX_AttendanceIncidents_OfficeSnapshotKey_ErrorCode_LastOccurredAtUtc] ON [AttendanceIncidents] ([OfficeSnapshotKey], [ErrorCode], [LastOccurredAtUtc]);
GO


CREATE UNIQUE INDEX [IX_Attendances_EmployeeId_WorkDate] ON [Attendances] ([EmployeeId], [WorkDate]);
GO


CREATE UNIQUE INDEX [IX_Departments_Name] ON [Departments] ([Name]);
GO


CREATE INDEX [IX_EmailChallenges_EmployeeId_Purpose_CreatedAtUtc] ON [EmailChallenges] ([EmployeeId], [Purpose], [CreatedAtUtc]);
GO


CREATE INDEX [IX_Employees_DepartmentId] ON [Employees] ([DepartmentId]);
GO


CREATE UNIQUE INDEX [IX_Employees_NormalizedEmail] ON [Employees] ([NormalizedEmail]);
GO


CREATE UNIQUE INDEX [IX_Employees_NormalizedUsername] ON [Employees] ([NormalizedUsername]);
GO


CREATE INDEX [IX_Employees_ShiftId] ON [Employees] ([ShiftId]);
GO


CREATE INDEX [IX_LeaveRequests_EmployeeId_StartDate] ON [LeaveRequests] ([EmployeeId], [StartDate]);
GO


CREATE INDEX [IX_LeaveRequests_ReviewerId] ON [LeaveRequests] ([ReviewerId]);
GO


CREATE UNIQUE INDEX [IX_Shifts_Name] ON [Shifts] ([Name]);
GO



