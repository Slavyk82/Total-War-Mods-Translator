# Steam Workshop API Service

Implementation of Steam Web API's `GetPublishedFileDetails` endpoint for retrieving Workshop mod metadata.

## Features

- **Single Mod Query**: `getModInfo()` - Fetch metadata for one mod
- **Batch Query**: `getMultipleModInfo()` - Fetch up to 100 mods simultaneously
- **Existence Check**: `modExists()` - Quick validation without full fetch
- **Update Detection**: `checkForUpdates()` - Compare timestamps to detect updates
- **Database Integration**: `WorkshopMetadataService` - Automatic storage to database

## Data Retrieved

Each Workshop mod query retrieves:

- `workshopId`: Steam Workshop item ID
- `title`: Mod title
- `appId`: Steam app ID (e.g., 594570 for Total War: Warhammer II)
- `workshopUrl`: Direct URL to Workshop page
- `fileSize`: File size in bytes
- `timeCreated`: Creation timestamp (Unix epoch)
- `timeUpdated`: Last update timestamp (Unix epoch)
- `subscriptions`: Number of subscribers
- `tags`: Categories/tags assigned to mod

## Usage Examples

### 1. Fetch Single Mod Metadata

```dart
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/steam/workshop_metadata_service.dart';

final service = ServiceLocator.get<WorkshopMetadataService>();

// Fetch and store in database
final result = await service.fetchAndStore(
  workshopId: '1234567890',
  appId: 594570, // Total War: Warhammer II
);

result.when(
  ok: (workshopMod) {
    print('Title: ${workshopMod.title}');
    print('Subscribers: ${workshopMod.subscriptions}');
  },
  err: (error) {
    print('Error: ${error.message}');
  },
);
```

### 2. Fetch Multiple Mods (Batch)

```dart
final workshopIds = [
  '1234567890',
  '0987654321',
  '1111111111',
];

final result = await service.fetchAndStoreBatch(
  workshopIds: workshopIds,
  appId: 594570,
);

result.when(
  ok: (workshopMods) {
    print('Fetched ${workshopMods.length} mods');
    for (final mod in workshopMods) {
      print('- ${mod.title}');
    }
  },
  err: (error) {
    print('Error: ${error.message}');
  },
);
```

### 3. Check for Updates

```dart
// Get local mods
final modsResult = await service.getModsByApp(appId: 594570);

if (modsResult is Ok) {
  final localMods = modsResult.value;
  
  // Extract workshop IDs
  final workshopIds = localMods.map((m) => m.workshopId).toList();
  
  // Check for updates
  final updateResult = await service.checkAndUpdateMods(
    workshopIds: workshopIds,
    appId: 594570,
  );
  
  updateResult.when(
    ok: (updatedIds) {
      print('${updatedIds.length} mods have updates');
      for (final id in updatedIds) {
        print('- Workshop ID: $id');
      }
    },
    err: (error) {
      print('Error checking updates: ${error.message}');
    },
  );
}
```

### 4. Check if Mod Exists

```dart
final result = await service.modExistsOnSteam(
  workshopId: '1234567890',
  appId: 594570,
);

result.when(
  ok: (exists) {
    if (exists) {
      print('Mod exists on Steam Workshop');
    } else {
      print('Mod not found or removed');
    }
  },
  err: (error) {
    print('Error: ${error.message}');
  },
);
```

### 5. Get Metadata from Database

```dart
// Single mod
final modResult = await service.getModMetadata(
  workshopId: '1234567890',
);

// Multiple mods
final modsResult = await service.getMultipleModMetadata(
  workshopIds: ['1234567890', '0987654321'],
);

// All mods for specific app
final appModsResult = await service.getModsByApp(
  appId: 594570,
);
```

## Low-Level API Access

For direct API access without database storage:

```dart
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/steam/i_workshop_api_service.dart';

final apiService = ServiceLocator.get<IWorkshopApiService>();

// Single query
final modInfo = await apiService.getModInfo(
  workshopId: '1234567890',
  appId: 594570,
);

// Batch query
final modInfoList = await apiService.getMultipleModInfo(
  workshopIds: ['1234567890', '0987654321'],
  appId: 594570,
);

// Check for updates
final updateMap = await apiService.checkForUpdates(
  modsWithTimestamps: {
    '1234567890': 1699564800, // Local timestamp
    '0987654321': 1699478400,
  },
  appId: 594570,
);
```

## Rate Limiting

The service includes automatic rate limiting:
- **100 requests per minute**
- Automatically queued and throttled
- Batch requests count as 1 request

## Error Handling

All methods return `Result<T, ServiceException>`:

```dart
final result = await service.fetchAndStore(
  workshopId: '1234567890',
  appId: 594570,
);

result.when(
  ok: (mod) {
    // Success
  },
  err: (error) {
    // Error types:
    // - InvalidWorkshopIdException
    // - WorkshopModNotFoundException
    // - WorkshopApiException
    // - TWMTDatabaseException
  },
);
```

## Database Schema

Workshop mods are stored in the `workshop_mods` table:

```sql
CREATE TABLE workshop_mods (
  id TEXT PRIMARY KEY,              -- Internal UUID
  workshop_id TEXT NOT NULL UNIQUE, -- Steam Workshop ID
  title TEXT NOT NULL,
  app_id INTEGER NOT NULL,
  workshop_url TEXT NOT NULL,
  file_size INTEGER,
  time_created INTEGER,
  time_updated INTEGER,
  subscriptions INTEGER,
  tags TEXT,                        -- JSON encoded
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  last_checked_at INTEGER
);
```

## Performance

- **Batch requests**: Up to 100 mods per request
- **Database caching**: Avoid redundant API calls
- **Indexed queries**: Fast lookups by workshop_id, app_id, timestamps
- **Rate limiting**: Prevents API throttling

## Testing

```dart
// In tests, inject mock services
final mockApi = MockWorkshopApiService();
final mockRepo = MockWorkshopModRepository();

final service = WorkshopMetadataService(
  apiService: mockApi,
  repository: mockRepo,
);
```

## See Also

- `IWorkshopApiService`: Low-level API interface
- `WorkshopModRepository`: Database repository
- `WorkshopMod`: Domain model
- `WorkshopModInfo`: API response model

