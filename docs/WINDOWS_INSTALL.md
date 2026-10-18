# Installing LiftLog from a Windows PC (AltStore)

iPhone apps can only be compiled on a Mac, so GitHub builds LiftLog on one of its cloud Macs
(`.github/workflows/build-ipa.yml`). You download the result (`LiftLog.ipa`) and install it on your
iPhone from Windows with **AltStore** and your normal (free) Apple ID.

**Route:** AltStore. It's free and open source, it works with your normal Apple ID, and it uses the
iTunes and iCloud already installed on your PC. You don't need Sideloadly.

**Already done for you:** the app is built and compiles, with the Watch app included. iTunes and iCloud must be
the versions downloaded from apple.com, not the Microsoft Store ones (on your PC these are already installed).

**Before you start, be honest with yourself about three things:**
- **Every 7 days** the app stops opening until AltStore refreshes it. AltStore does that by itself when the PC is on
  and on the same Wi-Fi as the phone. Your workout data is kept either way.
- **Apple Health:** Apple says free Apple IDs are allowed to use HealthKit, so heart rate and calories should
  work. If they don't, the app still runs and estimates calories from workout time.
- **Apple Watch:** this is the least certain part. AltStore isn't known to put Watch apps onto a Watch. Step 21 tells you how to
  check. If it doesn't work, the iPhone app works on its own.

---

## Part A: Get the app file (on the PC)

1. **Restart the PC** if you haven't since installing iCloud. The iCloud installer asked for a restart.
2. On the PC, open https://github.com/tawansProject/LiftLog/actions/runs/39109238081 and sign in to GitHub.
   (For a newer build: repo → **Actions** → **Build iPhone app** → latest green run. Every push to `main` builds.)
   - You should see: a green tick and **Artifacts** at the bottom.
3. Click **LiftLog-ipa** to download it. Right-click the zip, choose **Extract All**, and put it on the Desktop.
   - You should see: a file called **LiftLog.ipa**.
   - If the link says "expired" or 404, tell Claude "rebuild the app". Each build is kept for 30 days.

## Part B: Install AltServer (on the PC)

4. Go to https://altstore.io and download **AltStore Classic, AltServer for Windows**. You'll get `altinstaller.zip`.
5. Extract it and double-click **Setup.exe**. Click **Yes** on the Windows prompt and finish the setup.
6. Press the Windows key, type **AltServer**, right-click it, and choose **Run as administrator**. Click **Allow** if
   the firewall asks, and tick **Private networks**.
   - You should see: a small diamond icon in the bottom-right taskbar. It may be hidden under the **^** arrow.
   - If nothing appears, run it as administrator once more.

## Part C: Connect the iPhone

7. Plug the iPhone into the PC with a cable. Unlock it and tap **Trust**, then enter your passcode.
8. Open **iTunes** and sign in (**Account → Sign In**) with your Apple ID.
9. In iTunes, click the small **phone icon** at the top left, then go to **Summary**, tick
   **Sync with this iPhone over Wi-Fi**, and click **Apply**.
   - This is what lets AltStore refresh the app every week without the cable.

## Part D: Put AltStore on the iPhone

10. Click the **AltServer diamond icon** in the taskbar, choose **Install AltStore**, and pick your iPhone.
11. Type your **Apple ID email and password**. This is only sent to Apple. If you use two-factor, enter the code
    that appears on your phone.
    - You should see: a Windows notification that says "Installation Succeeded".
    - If it says it can't find iCloud, restart the PC (step 1) and try again.
12. On the iPhone, go to **Settings → General → VPN & Device Management**, tap your Apple ID, then tap **Trust**.
13. On the iPhone, go to **Settings → Privacy & Security → Developer Mode**, turn it **On**, and let the phone restart.
    Then tap **Turn On** once more.
    - If you can't find Developer Mode, do step 14 first. The option shows up after you try opening AltStore once.
14. Open **AltStore** on the iPhone.
    - You should see: the AltStore app with **Browse / My Apps / Settings** at the bottom.

## Part E: Install LiftLog

15. Get **LiftLog.ipa** onto the iPhone. The easiest way is to open Safari on the iPhone, go to the same GitHub page
    as step 2, sign in, and tap **LiftLog-ipa**. It saves to **Files → Downloads**. Tap the zip once to unzip it.
    - Another way: put LiftLog.ipa in iCloud Drive or Google Drive on the PC and open it in **Files** on the iPhone.
16. Keep the PC on with **AltServer running**, and keep the iPhone on the **same Wi-Fi** (or plugged in).
17. In AltStore, tap **My Apps**, tap **+** at the top left, and pick **LiftLog.ipa** from Files.
    - Type your Apple ID again if it asks.
    - You should see: LiftLog under My Apps with "7 DAYS" next to it, and the LiftLog icon on your Home Screen.
    - If it says "Could not find AltServer", check AltServer is running, the PC and phone are on the same Wi-Fi,
      and the firewall allowed AltServer (step 6). Or just plug the cable in and try again.
    - If it mentions an app limit, delete another sideloaded app first. A free Apple ID can have 3 at once,
      counting AltStore itself.
18. Open **LiftLog**. When it asks for **Apple Health**, tap **Turn On All → Allow**. Then allow **Notifications**.
    - If Health access fails, tell Claude. The app still works without it.

## Part F: Check the Watch

19. Make sure the Watch is paired with this iPhone and updated to watchOS 10 or newer.
20. On the iPhone, open the **Watch** app, scroll down to **Available Apps**, and tap **Install** next to LiftLog.
21. Look at the Watch.
    - **It works** if LiftLog appears on the Watch and shows your current set when you start a workout on the phone.
    - **It doesn't work** if you see "could not be installed", or LiftLog never shows up. Then the Watch part needs a
      Mac with Xcode or a paid Apple Developer account (99 USD/year, then it's installed through TestFlight). The iPhone
      app keeps working. Tell Claude which one you'd prefer.

## Every week

22. Do nothing if the PC is often on with AltServer running. AltStore refreshes in the background.
    If LiftLog stops opening, open AltStore → **My Apps** → **Refresh All** while the PC is on.

## Optional cleanup

23. On the PC, go to **Settings → Apps → Installed apps**, find **Sideloadly** and click **Uninstall**. You won't need it.
    You can also delete `SideloadlySetup64.exe`, `iTunes64Setup.exe` and `iCloudSetup.exe` from the Desktop.
    Keep iTunes and iCloud themselves, because AltServer needs them.

## If the GitHub build fails

Open the failed run and download **build-log**; the compiler errors are at the top of the step output.
