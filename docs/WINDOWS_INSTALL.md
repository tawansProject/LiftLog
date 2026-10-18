# Installing LiftLog from a Windows PC

iPhone apps can only be compiled on a Mac, so GitHub builds LiftLog on one of its cloud Macs
(`.github/workflows/build-ipa.yml`). You download the result (`LiftLog.ipa`) and install it on your
iPhone from Windows with **Sideloadly** and your normal (free) Apple ID.

## One-time setup

1. **Install iTunes and iCloud from Apple's website, not the Microsoft Store.**
   Sideloadly needs Apple's desktop drivers. Get them from
   apple.com/itunes (scroll to "Looking for other versions? → Windows") and
   apple.com/icloud (iCloud for Windows, non-Store download). If you already have the Store versions,
   uninstall them first.
2. **Install Sideloadly** from sideloadly.io (Windows version).
3. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (the phone restarts).
   The option appears after the first sideload attempt if you don't see it yet.

## Every time you want a new build

1. On GitHub, open the repo → **Actions** → **Build iPhone app**. Every push to `main` builds
   automatically; the **Run workflow** button builds on demand.
2. Open the latest green run and download **LiftLog-ipa** under *Artifacts*. Unzip it to get
   `LiftLog.ipa`.
3. Plug the iPhone into the PC with a cable, unlock it and tap **Trust**.
4. Open Sideloadly, drag `LiftLog.ipa` in, enter your Apple ID, press **Start**.
   (Sideloadly signs it with a free certificate tied to your Apple ID.)
5. On the iPhone: **Settings → General → VPN & Device Management →** your Apple ID → **Trust**.
6. Open LiftLog. Allow Apple Health and notifications when asked.

## Things to know about free Apple ID installs

- **The app stops opening after 7 days.** Re-run step 4 with the same .ipa (your data stays on the
  phone). Sideloadly can also refresh automatically over Wi-Fi while its tray app is running and the
  PC and phone are on the same network.
- **Limits:** a free Apple ID can have 3 sideloaded apps at once and register 10 app IDs per week.
  LiftLog uses two (iPhone + Watch).
- **HealthKit:** Apple lists HealthKit as available to free accounts, so heart rate and calorie data
  should work. If signing ever fails on HealthKit, the app still runs; calories fall back to the
  duration-based estimate.
- **Apple Watch:** the Watch app is embedded inside the .ipa. Whether a free-certificate Watch app
  transfers to the Watch through Sideloadly isn't documented and is the least certain part of this setup.
  After installing, open the **Watch** app on the iPhone → scroll to **Available Apps** → **Install**
  next to LiftLog. If it says "could not be installed", the iPhone app works on its own and the
  Watch part needs either a Mac with Xcode or a paid Apple Developer account (TestFlight).

## If the GitHub build fails

Open the failed run and download **build-log**; the compiler errors are at the top of the step output.
