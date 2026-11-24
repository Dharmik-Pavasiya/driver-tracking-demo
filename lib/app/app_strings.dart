/// Screen text is kept here so wording does not get scattered through widgets.
abstract final class AppStrings {
  static const title = 'Driver Location';
  static const online = 'Internet connected';
  static const offline = 'No internet connection';
  static const tracking = 'Tracking active';
  static const stopped = 'Tracking stopped';
  static const noLocation = 'No location captured yet.';
  static const start = 'Start tracking';
  static const stop = 'Stop tracking';
  static const permission = 'Requesting permission...';
  static const uploading = 'Uploading locations...';
  static const demoControls = 'Demo controls';
  static const simulateOffline = 'Simulate offline';
  static const simulateLocation = 'GPS every 3 seconds';
  static const simulationHint = 'Uses latest real GPS coordinates';
  static const mockApi = 'On-device mock API';
  static const healthy = 'Healthy';
  static const failBefore = 'Fail before saving';
  static const failAfter = 'Fail after saving';
  static const retry = 'Retry pending uploads';
  static const recent = 'Recent locations';
  static const empty = 'Saved points will appear here.';

  /// Formats the three upload counts consistently on the tracking screen.
  static String counts(int pending, int synced, int blocked) =>
      'Pending: $pending   Synced: $synced   Blocked: $blocked';
}
