param(
  [string]$AdminBaseUrl = "http://localhost:3001",
  [string]$ApiBaseUrl = "http://localhost:3000",
  [string]$AdminEmail = $env:TEST_ADMIN_EMAIL,
  [string]$AdminPassword = $env:TEST_ADMIN_PASSWORD,
  [switch]$SkipDockerCheck
)

$ErrorActionPreference = "Stop"

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param(
    [string]$Name,
    [bool]$Passed,
    [string]$Expected,
    [string]$Actual,
    [string]$Details = ""
  )

  $results.Add([pscustomobject]@{
    Name = $Name
    Passed = $Passed
    Expected = $Expected
    Actual = $Actual
    Details = $Details
  })
}

function Read-ResponseBody {
  param([object]$Response)

  if ($null -eq $Response) {
    return ""
  }

  try {
    $stream = $Response.GetResponseStream()
    if ($null -eq $stream) {
      return ""
    }
    $reader = New-Object System.IO.StreamReader($stream)
    $body = $reader.ReadToEnd()
    $reader.Dispose()
    return $body
  } catch {
    return ""
  }
}

function Invoke-JsonRequest {
  param(
    [string]$Method,
    [string]$Url,
    [object]$Body = $null,
    [hashtable]$Headers = @{}
  )

  $jsonBody = $null
  if ($null -ne $Body) {
    $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress
  }

  try {
    $resp = Invoke-WebRequest -Method $Method -Uri $Url -UseBasicParsing -TimeoutSec 30 -Headers $Headers -ContentType "application/json" -Body $jsonBody
    return [pscustomobject]@{
      StatusCode = [int]$resp.StatusCode
      Body = [string]$resp.Content
      Error = ""
    }
  } catch {
    if ($_.Exception.Response) {
      $statusCode = [int]$_.Exception.Response.StatusCode
      $body = Read-ResponseBody -Response $_.Exception.Response
      return [pscustomobject]@{
        StatusCode = $statusCode
        Body = $body
        Error = "HTTP_ERROR"
      }
    }

    return [pscustomobject]@{
      StatusCode = -1
      Body = ""
      Error = $_.Exception.Message
    }
  }
}

function Test-StatusCode {
  param(
    [string]$Name,
    [string]$Method,
    [string]$Url,
    [int[]]$ExpectedCodes,
    [object]$Body = $null,
    [hashtable]$Headers = @{},
    [string]$Details = ""
  )

  $resp = Invoke-JsonRequest -Method $Method -Url $Url -Body $Body -Headers $Headers
  $passed = $ExpectedCodes -contains $resp.StatusCode
  Add-Result -Name $Name -Passed $passed -Expected (($ExpectedCodes -join "/")) -Actual ([string]$resp.StatusCode) -Details $Details
  return $resp
}

Write-Host ""
Write-Host "============================================="
Write-Host " ScoutAI Admin Auth Smoke Test"
Write-Host "============================================="
Write-Host "AdminBaseUrl: $AdminBaseUrl"
Write-Host "ApiBaseUrl:   $ApiBaseUrl"
Write-Host ""

# 1) Infrastructure check
if (-not $SkipDockerCheck) {
  $runningServices = @()
  try {
    $runningServices = @(docker compose ps --services --filter "status=running" 2>$null)
  } catch {
    $runningServices = @()
  }

  $backendRunning = $runningServices -contains "backend"
  $adminRunning = $runningServices -contains "admin"

  Add-Result -Name "Docker backend running" -Passed $backendRunning -Expected "running" -Actual ($(if ($backendRunning) { "running" } else { "not running" })) -Details "docker compose ps"
  Add-Result -Name "Docker admin running" -Passed $adminRunning -Expected "running" -Actual ($(if ($adminRunning) { "running" } else { "not running" })) -Details "docker compose ps"
}

# 2) Frontend route checks
Test-StatusCode -Name "Route /login reachable" -Method "GET" -Url "$AdminBaseUrl/login" -ExpectedCodes @(200)
Test-StatusCode -Name "Route /forgot-password reachable" -Method "GET" -Url "$AdminBaseUrl/forgot-password" -ExpectedCodes @(200)
Test-StatusCode -Name "Route /reset-password reachable" -Method "GET" -Url "$AdminBaseUrl/reset-password?email=test%40example.com&token=dummy" -ExpectedCodes @(200)

# 3) Public backend auth checks
Test-StatusCode -Name "POST /auth/admin-google-login validates payload" -Method "POST" -Url "$ApiBaseUrl/auth/admin-google-login" -ExpectedCodes @(400) -Body @{}
Test-StatusCode -Name "POST /auth/forgot-password accepts request" -Method "POST" -Url "$ApiBaseUrl/auth/forgot-password" -ExpectedCodes @(201) -Body @{ email = "nobody+smoke@local.test" }
Test-StatusCode -Name "POST /auth/reset-password rejects invalid token" -Method "POST" -Url "$ApiBaseUrl/auth/reset-password" -ExpectedCodes @(400) -Body @{ email = "nobody+smoke@local.test"; token = "invalid"; newPassword = "12345678" }
Test-StatusCode -Name "GET /auth/me requires auth" -Method "GET" -Url "$ApiBaseUrl/auth/me" -ExpectedCodes @(401)

# 4) Optional authenticated checks (requires TEST_ADMIN_EMAIL and TEST_ADMIN_PASSWORD)
$token = ""
if (-not [string]::IsNullOrWhiteSpace($AdminEmail) -and -not [string]::IsNullOrWhiteSpace($AdminPassword)) {
  $loginResp = Test-StatusCode -Name "POST /auth/admin-login with test credentials" -Method "POST" -Url "$ApiBaseUrl/auth/admin-login" -ExpectedCodes @(200, 201) -Body @{ email = $AdminEmail; password = $AdminPassword }

  if ($loginResp.StatusCode -eq 200 -or $loginResp.StatusCode -eq 201) {
    try {
      $loginJson = $loginResp.Body | ConvertFrom-Json
      $token = [string]$loginJson.accessToken
    } catch {
      $token = ""
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($token)) {
    $authHeaders = @{ Authorization = "Bearer $token" }
    Test-StatusCode -Name "GET /auth/me with token" -Method "GET" -Url "$ApiBaseUrl/auth/me" -ExpectedCodes @(200) -Headers $authHeaders
    Test-StatusCode -Name "PATCH /auth/me/password validation" -Method "PATCH" -Url "$ApiBaseUrl/auth/me/password" -ExpectedCodes @(400) -Headers $authHeaders -Body @{}
  } else {
    Add-Result -Name "Authenticated checks" -Passed $false -Expected "JWT token" -Actual "missing" -Details "admin-login did not return accessToken"
  }
} else {
  Add-Result -Name "Authenticated checks" -Passed $true -Expected "optional" -Actual "skipped" -Details "Set TEST_ADMIN_EMAIL and TEST_ADMIN_PASSWORD to enable"
}

# Summary
Write-Host ""
Write-Host "Results"
Write-Host "-------"
$results | Format-Table -AutoSize

$total = $results.Count
$passed = @($results | Where-Object { $_.Passed }).Count
$failed = $total - $passed

Write-Host ""
Write-Host "Passed: $passed / $total"
Write-Host "Failed: $failed / $total"

if ($failed -gt 0) {
  Write-Host ""
  Write-Host "Failed checks:"
  $results | Where-Object { -not $_.Passed } | ForEach-Object {
    Write-Host "- $($_.Name) (expected: $($_.Expected), actual: $($_.Actual))"
  }
  exit 1
}

exit 0