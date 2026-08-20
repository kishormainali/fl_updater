/// Global switch for `fl_updater` diagnostic logging (`enableLogging: true`).
///
/// Defaults to `false` so logs don't clutter production or debug output.
/// Mirrored by `FlUpdater.enableLogging`; every `enableLogging` parameter
/// throughout the package falls back to this when left unset (`null`).
bool flUpdaterLoggingEnabled = false;

/// The tag every `fl_updater` log line is emitted under via `package:fp_logger`.
const flUpdaterLogTag = 'fl_updater';
