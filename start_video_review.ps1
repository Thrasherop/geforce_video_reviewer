# Activate the virtual environment
. .\.venv\Scripts\Activate.ps1


# Open the site in Chrome (adjust the URL/port if needed)
Start-Process "chrome.exe" "http://127.0.0.1:5000"

# Start the app in the background
python app.py

