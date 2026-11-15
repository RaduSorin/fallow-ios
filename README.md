# Fallow

A quiet monthly pause for iPhone: one intention for the month, a few small rhythms and a reflection at the end. Everything you write stays encrypted on your phone. English by default, Romanian available.

Fallow started as the "Răgaz" feature inside Kitchen Tales and is now its own app.

## Building without a Mac

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so only text files live in git.

- Every pull request is built and tested on a macOS runner in GitHub Actions (`.github/workflows/ci.yml`).
- The QA unit tests (`FallowQATests`) and the UI tests on the Simulator (`FallowUITests`) run only when started by hand: Actions › Full tests (`.github/workflows/full-tests.yml`, scheme `FallowFullTests`).
- TestFlight builds are started by hand: Actions › TestFlight (`.github/workflows/testflight.yml`). See below.

On a Mac, run `brew install xcodegen && xcodegen generate` and open `Fallow.xcodeproj`.

## TestFlight

One-time setup, once the Apple Developer account is approved:

1. **App IDs** (developer.apple.com › Certificates, Identifiers & Profiles › Identifiers):
   - `app.fallow.ios` with iCloud (container `iCloud.app.fallow.ios`, CloudKit not needed), App Groups (`group.app.fallow.ios`), HealthKit and Journaling Suggestions.
   - `app.fallow.ios.widgets` with App Groups (`group.app.fallow.ios`).
2. **The app** in App Store Connect › Apps › + › New App: iOS, bundle id `app.fallow.ios`, SKU `fallow-ios`. If the name "Fallow" is taken, pick another listing name; the name on the home screen stays Fallow.
3. **API key** in App Store Connect › Users and Access › Integrations › App Store Connect API: a team key with the **Admin** role (automatic signing needs it to create the distribution certificate and profiles). Download the `.p8` once.
4. **Secrets** in this repo (Settings › Secrets and variables › Actions):
   - `ASC_KEY_ID`: the key's ID.
   - `ASC_ISSUER_ID`: the Issuer ID shown above the keys.
   - `ASC_KEY_P8`: the whole content of the `.p8` file.
   - `APPLE_TEAM_ID`: the 10-character Team ID (developer.apple.com › Account › Membership).

Then run Actions › TestFlight › Run workflow. The build number is the workflow run number, so every run uploads a new build. Add testers in App Store Connect › TestFlight.

## Languages

Texts live in `Fallow/Resources/Localizable.xcstrings` (English source, Romanian translation). Users change the language from the app's page in iOS Settings.
