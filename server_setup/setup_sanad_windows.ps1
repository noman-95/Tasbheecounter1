$ErrorActionPreference = 'Stop'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git install karein: https://git-scm.com/download/win' }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { throw 'Python 3.11+ install karein.' }

$root = Join-Path $PSScriptRoot 'sanad'
if (-not (Test-Path $root)) {
  git clone https://github.com/harounRhim/sanad.git $root
}
Set-Location $root
python -m venv .venv
& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
Write-Host ''
Write-Host 'Sanad backend installed.'
Write-Host 'Next: download the Hugging Face model as described in server_setup/README.md, then start uvicorn.'
