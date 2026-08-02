## What's New — v2.0.6

### New AI models
- **OpenAI:** added GPT-5.6 Terra and GPT-5.4 nano.
- **Anthropic:** added Claude Sonnet 5 and Claude Opus 5.
- **Google Gemini:** added Gemini 3.6 Flash, Gemini 3.5 Flash and Gemini 3.5 Flash-Lite.
- Retired the Gemini 3 Pro and Gemini 3 Flash previews, now superseded. If one of them was your selected model, Gemini 3.6 Flash takes over; any other model you had starred is left untouched.

### Backups
- The automatic startup backup no longer blocks the app: it now runs in the background and shows its progress in a card on the home screen.
- Restoring a database backup now applies pending migrations, so a backup taken on an older version restores cleanly.

### Fixes
- Fixed a random failure that could prevent translation from starting at all.
- Stop/Cancel now aborts translation requests already in flight, instead of waiting for them to finish.
- A batch whose parallel chunk failed outright is no longer reported as completed with zero failures.
- Update checks are now bounded by a timeout and can no longer delay the startup backup.
- Various bug fixes and stability improvements.
