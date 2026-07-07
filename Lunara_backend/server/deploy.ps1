# Lunara Backend Deployment Script
Write-Host "Deploying Lunara Backend to IIS Server..." -ForegroundColor Green

# Build the application
Write-Host "Building application..." -ForegroundColor Yellow
npm run build

# Copy dist files to server
Write-Host "Copying dist files to server..." -ForegroundColor Yellow
$sourceDist = "$PSScriptRoot\dist"
$destDist = "\\103.224.247.22\C$\inetpub\vhosts\lunara_backend\server\dist"

if (Test-Path $sourceDist) {
    Copy-Item -Path $sourceDist -Destination $destDist -Recurse -Force
    Write-Host "Dist files copied successfully" -ForegroundColor Green
} else {
    Write-Host "Dist directory not found!" -ForegroundColor Red
}

# Copy web.config to server
Write-Host "Copying web.config to server..." -ForegroundColor Yellow
$sourceConfig = "$PSScriptRoot\web.config"
$destConfig = "\\103.224.247.22\C$\inetpub\vhosts\lunara_backend\server\web.config"

if (Test-Path $sourceConfig) {
    Copy-Item -Path $sourceConfig -Destination $destConfig -Force
    Write-Host "Web.config copied successfully" -ForegroundColor Green
} else {
    Write-Host "Web.config not found!" -ForegroundColor Red
}

# Copy package.json for dependencies
Write-Host "Copying package.json to server..." -ForegroundColor Yellow
$sourcePackage = "$PSScriptRoot\package.json"
$destPackage = "\\103.224.247.22\C$\inetpub\vhosts\lunara_backend\server\package.json"

if (Test-Path $sourcePackage) {
    Copy-Item -Path $sourcePackage -Destination $destPackage -Force
    Write-Host "Package.json copied successfully" -ForegroundColor Green
} else {
    Write-Host "Package.json not found!" -ForegroundColor Red
}

# Copy package-lock.json for dependencies
Write-Host "Copying package-lock.json to server..." -ForegroundColor Yellow
$sourceLock = "$PSScriptRoot\package-lock.json"
$destLock = "\\103.224.247.22\C$\inetpub\vhosts\lunara_backend\server\package-lock.json"

if (Test-Path $sourceLock) {
    Copy-Item -Path $sourceLock -Destination $destLock -Force
    Write-Host "Package-lock.json copied successfully" -ForegroundColor Green
} else {
    Write-Host "Package-lock.json not found!" -ForegroundColor Red
}

# Copy .env file
Write-Host "Copying .env to server..." -ForegroundColor Yellow
$sourceEnv = "$PSScriptRoot\.env"
$destEnv = "\\103.224.247.22\C$\inetpub\vhosts\lunara_backend\server\.env"

if (Test-Path $sourceEnv) {
    Copy-Item -Path $sourceEnv -Destination $destEnv -Force
    Write-Host ".env copied successfully" -ForegroundColor Green
} else {
    Write-Host ".env not found!" -ForegroundColor Red
}

# Copy test script
Write-Host "Copying test script to server..." -ForegroundColor Yellow
$sourceTest = "$PSScriptRoot\test-env-server.js"
$destTest = "\\103.224.247.22\C$\inetpub\vhosts\lunara_backend\server\test-env-server.js"

if (Test-Path $sourceTest) {
    Copy-Item -Path $sourceTest -Destination $destTest -Force
    Write-Host "Test script copied successfully" -ForegroundColor Green
} else {
    Write-Host "Test script not found!" -ForegroundColor Red
}

Write-Host "Deployment finished. Please log into the server and run 'npm ci' in the project directory to update dependencies." -ForegroundColor Cyan