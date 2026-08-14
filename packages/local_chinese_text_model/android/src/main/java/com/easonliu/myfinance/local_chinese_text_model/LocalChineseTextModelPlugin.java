package com.easonliu.myfinance.local_chinese_text_model;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * No-op plugin whose Android library dependency bundles the ML Kit Chinese text
 * recognition model into the application runtime.
 */
public final class LocalChineseTextModelPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    // No platform channel is required. The dependency is consumed by ML Kit.
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    // No resources are retained.
  }
}
