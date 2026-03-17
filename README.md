# GeoNudge

A location-based alerts app for iOS. Set up named places with custom messages — GeoNudge notifies you the moment you arrive, even when the app is closed.

## Features

### Alerts
- Add alerts with a name, custom notification message, and adjustable radius (100–1000m)
- Swipe left to **edit** an alert (name, message, location, radius, collection)
- Swipe right to **delete**
- Toggle alerts on/off per-row — inactive alerts are dimmed and won't fire

### Location Picking
- **Search** for any address or business name
- **Long press** on the map to drop a pin anywhere
- Map opens centered on your current location
- Full pan, pinch-zoom, and pin repositioning

### Collections
- Organize alerts into named collections (e.g. *Home*, *Trip to LA*, *Work*)
- A default **General** collection catches all unassigned alerts
- Create new collections inline when adding or editing an alert
- Filter the alerts list by collection using the chip bar at the top

### Google Maps Import
- Tap **+** → *Import from Google Maps* to import saved places from a Google Takeout JSON file
- Signs in with Google (persists across app launches until disconnected)
- Parses the GeoJSON exported by Google Takeout and creates a new collection with 200m-radius alerts
- Manage the connected account via the **gear icon** → Settings → Disconnect

### Permissions & Reliability
- Prompts for **Always On** location access (required for background geofencing)
- Permission banners guide the user to Settings if access is denied or limited
- Warning shown when approaching iOS's 20-region geofencing limit

## Requirements

- iOS 26+
- Xcode 26+

## Setup: Google Sign-In (required for Google Maps import)

1. Go to [console.cloud.google.com](https://console.cloud.google.com) → **APIs & Services → Credentials**
2. Click **+ Create Credentials → OAuth client ID**
3. Application type: **iOS**, Bundle ID: `geonudge.GeoNudge`
4. Copy the generated client ID (e.g. `123456789-abcdefghij.apps.googleusercontent.com`)
5. Open `GeoNudge/Info.plist` and replace both placeholders:
   - `GIDClientID` → the full client ID
   - `CFBundleURLSchemes` → the *reversed* client ID: strip `.apps.googleusercontent.com` and prepend `com.googleusercontent.apps.`
     - Example: `123456789-abcdefghij.apps.googleusercontent.com` → `com.googleusercontent.apps.123456789-abcdefghij`

Without these values the app will crash when tapping *Import from Google Maps*.

## Architecture

```
GeoNudgeApp
├── NotificationManager   @Observable @MainActor
├── LocationManager       @Observable @MainActor
│     ├── alerts: [GeoAlert]       ← single source of truth
│     └── collections: [GeoCollection]
└── GoogleAuthManager     @Observable @MainActor

Views
  ContentView  →  AddAlertView (sheet)  →  MapPickerView (fullScreenCover)
             →  SettingsView (sheet)
             →  .fileImporter (Google Takeout JSON)
```

Both managers are injected as `@Environment` objects. All mutations persist to `UserDefaults` and reconcile the active `CLCircularRegion` set immediately.

## Project Structure

```
GeoNudge/
├── Models/
│   ├── GeoAlert.swift        # Codable alert model
│   ├── GeoCollection.swift   # Codable collection model
│   └── TakeoutParser.swift   # Google Takeout GeoJSON → GeoCollection + [GeoAlert]
├── Managers/
│   ├── LocationManager.swift    # CLLocationManager, region monitoring, CRUD
│   ├── NotificationManager.swift # UNUserNotificationCenter wrapper
│   └── GoogleAuthManager.swift  # GIDSignIn wrapper
├── Views/
│   ├── AddAlertView.swift    # Add / edit alert form
│   ├── MapPickerView.swift   # Full-screen map picker with search
│   └── SettingsView.swift    # Google account + disconnect
├── ContentView.swift         # Alerts list with collection filter
├── GeoNudgeApp.swift
└── Info.plist                # Requires GIDClientID + CFBundleURLSchemes (see Setup above)
```

## Roadmap

- [x] Import collections from Google Maps (via Google Takeout JSON)
- [ ] iCloud sync across devices
