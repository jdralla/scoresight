Test build of the USC fork (branch `usc/startup-shutdown-fixes`) for Apple Silicon Macs. **Not an official ScoreSight release.** Based on upstream v0.1.0 with fixes for slow launch and the hang on quit.

**Not yet verified:** camera capture, OCR and NDI output. That is what this test build is for. Keep the official v0.1.0 installed as a fallback.

### Install
1. Requires an Apple Silicon Mac (M1 or later).
2. Download the zip below and double-click it to unzip.
3. Rename the unzipped app (for example "ScoreSight USC test") so it doesn't replace your existing ScoreSight.
4. Double-click it. macOS will block it because it is not signed. Open System Settings > Privacy & Security, scroll down, and click **Open Anyway**. This is needed only once.
5. Allow camera access when asked.

It uses the same settings file as the official app. Quit the official app before opening this one (both use port 18099).

Please report: does the camera open, do the OCR boxes read, does http://localhost:18099/json update, and does it quit cleanly.
