/// Represents the update status determined by comparing version numbers.
enum UpdateStatus {
  /// No update is required or available.
  none,

  /// An optional update is available that can be dismissed or snoozed.
  soft,

  /// A mandatory update is required; the dialog cannot be dismissed.
  force,
}
