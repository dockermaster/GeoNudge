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

### Permissions & Reliability
- Prompts for **Always On** location access (required for background geofencing)
- Permission banners guide the user to Settings if access is denied or limited
- Warning shown when approaching iOS's 20-region geofencing limit

## Requirements

- iOS 26+
- Xcode 26+

## Architecture

```
GeoNudgeApp
├── NotificationManager   @Observable @MainActor
└── LocationManager       @Observable @MainActor
      ├── alerts: [GeoAlert]       ← single source of truth
      └── collections: [GeoCollection]

Views
  ContentView  →  AddAlertView (sheet)  →  MapPickerView (fullScreenCover)
```

Both managers are injected as `@Environment` objects. All mutations persist to `UserDefaults` and reconcile the active `CLCircularRegion` set immediately.

## Project Structure

```
GeoNudge/
├── Models/
│   ├── GeoAlert.swift        # Codable alert model
│   └── GeoCollection.swift   # Codable collection model
├── Managers/
│   ├── LocationManager.swift    # CLLocationManager, region monitoring, CRUD
│   └── NotificationManager.swift # UNUserNotificationCenter wrapper
├── Views/
│   ├── AddAlertView.swift    # Add / edit alert form
│   └── MapPickerView.swift   # Full-screen map picker with search
├── ContentView.swift         # Alerts list with collection filter
├── GeoNudgeApp.swift
└── Info.plist
```

## Roadmap

- [ ] Import collections from Google Maps (via Google Takeout JSON)
- [ ] iCloud sync across devices
