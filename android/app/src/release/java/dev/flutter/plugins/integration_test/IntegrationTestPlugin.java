package dev.flutter.plugins.integration_test;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Release-only compatibility stub for Flutter 3.47's generated registrant.
 * The registrant references the dev-only integration_test plugin, while the
 * Flutter Gradle plugin intentionally excludes that dependency from release.
 * No test runner or test transport is packaged in the production APK.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
