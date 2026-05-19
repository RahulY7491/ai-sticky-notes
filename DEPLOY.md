# AI Sticky Notes API – Render Deployment

## Render.com (Free tier, HTTPS included)

### 1. Push backend to GitHub
```bash
cd C:\Users\poona\.gemini\antigravity\scratch\ai-sticky-notes\backend
git init
git add .
git commit -m "Initial backend commit"
# Push to your GitHub repo
```

### 2. Create a new Web Service on render.com
- **Build Command:** `dotnet publish -c Release -o out`
- **Start Command:** `dotnet out/AIStickyNotes.API.dll`
- **Environment:** `DOTNET_VERSION = 8.0`

### 3. Set environment variable
In Render Dashboard → Environment → Add:
```
Gemini__ApiKey = YOUR_GEMINI_API_KEY
```

### 4. Note your Render URL
After deploy, Render gives you: `https://ai-sticky-notes-api.onrender.com`

Update Flutter's `AppConstants.baseUrl` to this URL.
