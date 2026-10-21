# NguyenAnhDung Attendance API contract

Base URL: `http://localhost:5080/api`. JSON uses camelCase; identifiers are UUID strings; dates are ISO 8601. Money is not involved. Times returned as `...Utc` are UTC. Business dates use UTC+07:00. Roles: `Admin`, `Manager`, `Employee`.

Errors use `{ "message": "Vietnamese explanation" }`. Authorized endpoints require `Authorization: Bearer <accessToken>`. Authentication failures return 401; permission failures 403; validation failures 400; missing records 404; conflicts 409. Lists return JSON arrays (no pagination for this coursework scope).

## Authentication
- `POST /auth/register`: `{ username,email,fullName,password }` -> `{ message }`; creates unverified Employee. Password >=10 chars with upper/lower/digit. Username 3-40 characters letters/digits/underscore/dot.
- `POST /auth/verify-email`: `{ email,code }` -> `{ message }`.
- `POST /auth/resend-verification`: `{ email }` -> generic `{ message }`.
- `POST /auth/login`: `{ identifier,password }` (username OR email) -> `{ challengeId,maskedEmail,expiresAtUtc }` after email/password verification.
- `POST /auth/verify-otp`: `{ challengeId,code }` -> `{ accessToken,expiresAtUtc,user }`.
- `GET /auth/me` -> user.
- User: `{ id,username,email,fullName,role,departmentId,shiftId,isActive,emailVerified }`.
- Codes must be sent using SMTP. Explicit Development-only console email delivery can be configured, with clearly labelled logs. Never return verification or OTP codes through API responses. No preconfigured credentials in production.

## Departments (Admin writes; authenticated reads)
- `GET /departments` -> array of `{ id,name,description }`.
- `POST /departments`, `PUT /departments/{id}`: `{ name,description }` -> entity.
- `DELETE /departments/{id}` -> `{ message }`; reject when department has employees.

## Shifts (Admin writes; authenticated reads)
- `GET /shifts` -> array of `{ id,name,startTime,endTime,graceMinutes }`; `HH:mm` strings, overnight shifts excluded in this coursework.
- `POST /shifts`, `PUT /shifts/{id}`: `{ name,startTime,endTime,graceMinutes }` -> entity.
- `DELETE /shifts/{id}` -> `{ message }`; reject when assigned.

## Employees (Admin/Manager reads; Admin writes)
- `GET /employees` -> user array.
- `POST /employees`: `{ username,email,fullName,password,role,departmentId,shiftId }` -> user. Send verification email for new account.
- `PUT /employees/{id}`: `{ fullName,role,departmentId,shiftId,isActive }` -> user. Protect last active Admin and own deactivation/demotion.
- `DELETE /employees/{id}` -> `{ message }`; soft deactivate (retain attendance/audit history); protect own account and last active Admin.

## Attendance
- `GET /attendance`: Employee own records; Admin/Manager all. Optional `from=YYYY-MM-DD&to=YYYY-MM-DD` (inclusive), `employeeId=UUID`.
- Record: `{ id,employeeId,employeeName,departmentName,workDate,checkInAtUtc,checkOutAtUtc,isLate,latitude,longitude,accuracyMeters,motionScore,workedMinutes }`.
- `GET /attendance/summary`: own summary `{ todayStatus,checkedInAtUtc,checkedOutAtUtc,totalDaysThisMonth,lateDaysThisMonth,totalHoursThisMonth,missingCheckoutCount }`. `todayStatus`: `NotCheckedIn`, `Working`, `Completed`.
- `POST /attendance/qr` (Admin/Manager): no body -> `{ token,expiresAtUtc }`; short-lived signed QR, restricted audience/purpose.
- `POST /attendance/check-in`: `{ qrToken,latitude,longitude,accuracyMeters,motionScore }` -> record. Validate signed QR expiry/purpose, geofence and GPS accuracy on server. Only one record per employee per business day. Users require assigned shift; Admin/Manager may also clock attendance if assigned.
- `POST /attendance/check-out`: `{ latitude,longitude,accuracyMeters,motionScore }` -> record. Requires today's open attendance and valid geofence. Motion is measured sensor telemetry only, not proof against spoofing.

## Leave requests (CRUD + review)
- `GET /leave-requests`: Employee own; Admin/Manager all.
- Entity: `{ id,employeeId,employeeName,type,startDate,endDate,reason,status,reviewNote,reviewerName,createdAtUtc }`; status `Pending`, `Approved`, `Rejected`; type `Annual`, `Sick`, `Unpaid`, `Correction`.
- `POST /leave-requests`, `PUT /leave-requests/{id}`: `{ type,startDate,endDate,reason }` -> entity; edit own Pending only. Correction requests support missing clock-out suggestions; they do not silently change attendance.
- `DELETE /leave-requests/{id}` -> `{ message }`; own Pending only.
- `PATCH /leave-requests/{id}/review` (Admin/Manager): `{ status,reviewNote }` -> entity. Never self-approve; Manager reviews Employee only; Admin reviews others.

## Company settings
- `GET /company-settings` -> `{ officeName,latitude,longitude,radiusMeters,maxAccuracyMeters,qrLifetimeSeconds }`.
- `PUT /company-settings` (Admin): same object -> entity. Persist settings in SQL Server; reject nonfinite coordinates, invalid ranges, radius outside 20..5000m, maxAccuracy outside 5..500m, QR lifetime outside 15..300 seconds.

## Collective attendance incidents
- Only eligible, authenticated failures received by the server count: invalid/expired QR, insufficient GPS accuracy, or outside-office location. Missing permissions, offline requests that never reach the API, malformed measurements, missing shifts and duplicate attendance do not establish a shared incident.
- At least **3 distinct employees** with the same failure and office-settings snapshot within a rolling **5-minute** window create an incident. Repeated requests from one employee cannot meet the threshold. This is a suspected shared problem for human review, not a determination that employees were present.
- `GET /attendance-incidents`: array of `{ id,errorCode,errorLabel,officeName,firstOccurredAtUtc,lastOccurredAtUtc,affectedEmployeeCount,pendingCount,status,myReviewStatus }`. Status is `Open` or `Resolved`; `myReviewStatus` is null, `Pending`, `Approved` or `Rejected`.
- `GET /attendance-incidents/{id}`: summary fields plus `participants`: `{ id,employeeId,employeeName,username,firstAttemptAtUtc,lastAttemptAtUtc,attemptCount,status,reviewNote,reviewedAtUtc,reviewerName }`.
- Admin/Manager can read incidents for their review scope; Employee sees only incidents involving them and only their own participant details. Other employees' names and review notes must not be exposed.
- `POST /attendance-incidents/{id}/review` (Admin/Manager): `{ participantIds:[UUID],status:"Approved"|"Rejected",reviewNote }`; note is 5–1000 characters. Review selected Pending participants atomically, reject self-review, unknown membership and repeat review. Returns updated detail.
- Approval records an accepted explanation. It does **not** create attendance, backdate a punch, change `IsLate`, or waive late penalties automatically. Original server attempt times, attendance times and review history remain available for comparison. No raw QR tokens are stored in incident logs.

## Extra feature and run expectations
The main proposed extra feature is collective attendance incident detection and batch explanation review, documented in `docs/INCIDENTS.md`. Flutter also suggests a pending Correction request when an older attendance record lacks checkout; always requires a person to submit/review. Do not claim market uniqueness.
App supports a visible configurable API base URL (`--dart-define=API_BASE_URL=...` default Android emulator `http://10.0.2.2:5080/api`). Never store passwords/OTP; store session in platform secure storage. Sign out on API 401. Logout clears local token.
