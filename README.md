# Fallow

A quiet monthly pause for iPhone: one intention for the month, a few small rhythms and a reflection at the end. Everything you write stays encrypted on your phone. English by default, Romanian available.

Fallow started as the "Răgaz" feature inside Kitchen Tales and is now its own app.

## Building without a Mac

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so only text files live in git.

- Every pull request is built and tested on a macOS runner in GitHub Actions (`.github/workflows/ci.yml`).
- TestFlight uploads come in a later PR, once the Apple Developer account is approved.

On a Mac, run `brew install xcodegen && xcodegen generate` and open `Fallow.xcodeproj`.

## Languages

Texts live in `Fallow/Resources/Localizable.xcstrings` (English source, Romanian translation). Users change the language from the app's page in iOS Settings.
