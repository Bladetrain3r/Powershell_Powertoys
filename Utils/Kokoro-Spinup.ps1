$response = Invoke-WebRequest -Uri "http://localhost:8880/web" -UseBasicParsing
if ($response.StatusCode -eq 200) {
    Write-Host "The server is running and accessible."
    exit 0
} else {
    Write-Host "The server is not accessible. Status code: $($response.StatusCode)"
    docker stop kokoro
    docker container rm kokoro
    Write-Host "Attempting to start the server..."
    docker run -p 8880:8880 --detach --name kokoro ghcr.io/remsky/kokoro-fastapi-cpu:latest 
    Write-Host "Waiting for the server to start..."
    Start-Sleep -Seconds 15
    $response = Invoke-WebRequest -Uri "http://localhost:8880/web" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        Write-Host "The server is now running and accessible."
    } else {
        Write-Host "The server is still not accessible. Status code: $($response.StatusCode)"
        exit 1
    }
}