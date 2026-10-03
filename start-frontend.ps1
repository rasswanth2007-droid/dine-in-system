cd "d:\projects\dine-in system"
Write-Host "Starting frontend server on port 5500..."
Write-Host "Open http://localhost:5500 in your browser"
Write-Host "Press Ctrl+C to stop"
python -m http.server 5500 --directory frontend