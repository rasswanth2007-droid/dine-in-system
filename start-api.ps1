$env:PATH += ";C:\Program Files\R\R-4.6.1\bin"
cd "d:\projects\dine-in system"
Write-Host "Starting R API server on port 8000..."
Write-Host "Press Ctrl+C to stop"
Rscript run.R