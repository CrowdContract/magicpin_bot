@echo off
echo Starting Vera Bot on port 8080...
echo Make sure .env has your OPENAI_API_KEY set!
echo.
cd /d "%~dp0"
python -m uvicorn main:app --host 0.0.0.0 --port 8080
pause
