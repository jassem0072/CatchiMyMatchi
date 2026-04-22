param(
  [string]$EnvFile = ".env",
  [string]$ApiBaseUrl = "http://localhost:3000",
  [string]$BackendContainer = "scoutai-backend",
  [switch]$SkipDockerEnvCheck,
  [switch]$SkipLiveApiChecks
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

function Parse-DotEnv {
  param([string]$Path)

  $map = @{}
  if (-not (Test-Path $Path)) {
    return $map
  }

  $lines = Get-Content -Path $Path
  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    if ($trimmed.StartsWith("#")) { continue }

    $idx = $trimmed.IndexOf("=")
    if ($idx -lt 1) { continue }

    $key = $trimmed.Substring(0, $idx).Trim()
    $value = $trimmed.Substring($idx + 1).Trim()

    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
      $value = $value.Substring(1, $value.Length - 2)
    }

    $map[$key] = $value
  }

  return $map
}

function Mask-Value {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return "empty"
  }

  if ($Value.Length -le 4) {
    return "****"
  }

  return "{0}****{1}" -f $Value.Substring(0, 2), $Value.Substring($Value.Length - 2, 2)
}

Write-Host ""
Write-Host "============================================="
Write-Host " ScoutAI Env + Auth Verification Test"
Write-Host "============================================="
Write-Host "EnvFile:        $EnvFile"
Write-Host "ApiBaseUrl:     $ApiBaseUrl"
Write-Host "BackendContainer: $BackendContainer"
Write-Host ""

$envMap = Parse-DotEnv -Path $EnvFile
if ($envMap.Count -eq 0) {
  Add-Result -Name "Load .env file" -Passed $false -Expected "existing .env with key=value pairs" -Actual "not found or empty" -Details $EnvFile
} else {
  Add-Result -Name "Load .env file" -Passed $true -Expected "existing .env" -Actual "loaded" -Details "$($envMap.Count) keys"
}

$requiredKeys = @(
  "SMTP_HOST",
  "SMTP_PORT",
  "SMTP_USER",
  "SMTP_PASS",
  "SMTP_FROM",
  "APP_BASE_URL",
  "GOOGLE_CLIENT_SECRET"
)

foreach ($key in $requiredKeys) {
  $value = ""
  if ($envMap.ContainsKey($key)) {
    $value = [string]$envMap[$key]
  }
  $present = -not [string]::IsNullOrWhiteSpace($value)
  Add-Result -Name ".env $key present" -Passed $present -Expected "non-empty" -Actual (Mask-Value -Value $value)
}

if (-not $SkipDockerEnvCheck) {
  $containerExists = $false
  try {
    $containerName = (docker ps --filter "name=^/$BackendContainer$" --format "{{.Names}}" 2>$null)
    if ($containerName -eq $BackendContainer) {
      $containerExists = $true
    }
  } catch {
    $containerExists = $false
  }

  Add-Result -Name "Docker backend container running" -Passed $containerExists -Expected "running" -Actual ($(if ($containerExists) { "running" } else { "not running" }))

  if ($containerExists) {
    foreach ($key in $requiredKeys) {
      $liveValue = ""
      try {
        $liveValue = (docker exec $BackendContainer /bin/sh -lc "printenv $key" 2>$null | Out-String).Trim()
      } catch {
        $liveValue = ""
      }
      $ok = -not [string]::IsNullOrWhiteSpace($liveValue)
      Add-Result -Name "Container $key present" -Passed $ok -Expected "non-empty" -Actual (Mask-Value -Value $liveValue)
    }
  }
}

if (-not $SkipLiveApiChecks) {
  $docsResp = Invoke-JsonRequest -Method "GET" -Url "$ApiBaseUrl/docs"
  Add-Result -Name "GET /docs" -Passed ($docsResp.StatusCode -eq 200) -Expected "200" -Actual ([string]$docsResp.StatusCode)

  $meResp = Invoke-JsonRequest -Method "GET" -Url "$ApiBaseUrl/auth/me"
  Add-Result -Name "GET /auth/me route exists" -Passed (($meResp.StatusCode -eq 401) -or ($meResp.StatusCode -eq 200)) -Expected "401 or 200" -Actual ([string]$meResp.StatusCode)

  $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $testEmail = "smtpcheck+$stamp@example.com"
  $testPassword = "Abc12345"

  $signupResp = Invoke-JsonRequest -Method "POST" -Url "$ApiBaseUrl/auth/signup" -Body @{
    email = $testEmail
    password = $testPassword
    role = "player"
    displayName = "SMTP Check"
  }

  $signupPass = ($signupResp.StatusCode -eq 200 -or $signupResp.StatusCode -eq 201)
  Add-Result -Name "POST /auth/signup" -Passed $signupPass -Expected "200 or 201" -Actual ([string]$signupResp.StatusCode)

  $signinResp = Invoke-JsonRequest -Method "POST" -Url "$ApiBaseUrl/auth/signin" -Body @{
    email = $testEmail
    password = $testPassword
  }

  $signinBody = ""
  try {
    $signinJson = $signinResp.Body | ConvertFrom-Json
    if ($null -ne $signinJson.message) {
      $signinBody = [string]$signinJson.message
    }
  } catch {
    $signinBody = ([string]$signinResp.Body).Trim()
  }

  $signinLooksGood = $signinResp.StatusCode -eq 401
  $signinExpected = "401 (verification flow)"
  if (-not [string]::IsNullOrWhiteSpace($signinBody)) {
    $signinExpected = "401 with verification hint"
  }
  Add-Result -Name "POST /auth/signin verification flow" -Passed $signinLooksGood -Expected $signinExpected -Actual ([string]$signinResp.StatusCode) -Details $signinBody

  $resendResp = Invoke-JsonRequest -Method "POST" -Url "$ApiBaseUrl/auth/resend-code" -Body @{ email = $testEmail }
  $resendPass = ($resendResp.StatusCode -eq 200 -or $resendResp.StatusCode -eq 201)
  Add-Result -Name "POST /auth/resend-code" -Passed $resendPass -Expected "200 or 201" -Actual ([string]$resendResp.StatusCode)
}

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
    if (-not [string]::IsNullOrWhiteSpace($_.Details)) {
      Write-Host "  details: $($_.Details)"
    }
  }
  exit 1
}

exit 0
