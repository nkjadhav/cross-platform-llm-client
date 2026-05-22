# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**PrivateLM** (`pubspec.yaml` name: `privatelm`) — a Flutter cross-platform AI chat client. Runs LLMs locally on Android/iOS via custom plugins, falls back to cloud APIs (OpenAI, Anthropic, Google Gemini, Kimi/Moonshot, Stability, NVIDIA, OpenRouter, custom OpenAI-compatible) on web or when the user opts in. Dart SDK `>=3.3.0 <4.0.0`.

## Common Commands

```bash
flutter pub get                      # fetch deps + path-overrides to local_plugins/
flutter analyze                      # static analysis (uses analysis_options.yaml)
flutter test                         # run tests in test/
flutter test test/widget_test.dart   # run a single test file
flutter test --name "<pattern>"      # run tests matching a name

# Run / build
flutter run                          # debug on attached device
flutter build apk --release          # Android release APK
flutter build ios --release          # iOS (requires `cd ios && pod install` first)
flutter build web --release          # Web (cloud-only — local engine is stubbed)

# Android via gradle directly (from android/)
cd android && ./gradlew assembleDebug
```

The web build is deployed via Firebase Hosting (`firebase.json`, `.firebaserc` → `ai-chat-orailnoor`); `firebase deploy --only hosting` after `flutter build web --release`.

`analysis_options.yaml` enables `prefer_const_constructors` / `prefer_const_declarations` and **disables** `avoid_print` (print calls are intentional for log output piped through `AppLogService`).

## Architecture

### Layering (GetX)

```
views/ (StatelessWidgets, Obx)  →  controllers/ (GetxController, reactive .obs)  →  services/ (GetxService singletons)
```

Bootstrapping happens in `lib/main.dart`: `HiveService` and `DeviceInfoService` use `Get.putAsync`; the rest (`SettingsController`, `CloudModelController`, `InferenceService`, `CloudService`, `DownloadService`, `LocalImageService`, `AppLogService`, `ServerController`, `ModelController`) are eagerly `Get.put`. Per-route controllers are wired through `BindingsBuilder` in `lib/core/routes.dart`. There are only three routes: `/`, `/chat`, `/task` — other "views" (`model_view`, `settings_view`, `server_view`, `log_view`) are surfaced inside `HomeView`.

### Cross-platform inference (critical pattern)

Local inference is **conditionally compiled** via Dart's `if (dart.library.html)` import:

```dart
// lib/services/inference_service.dart
import 'inference_android.dart' if (dart.library.html) 'inference_stub.dart' as platform;
```

The same pattern is used for `device_info_*`, `download_*`, and `openai_server_service_*`. When adding a new platform-dependent surface, follow the trio: `*_service.dart` (public API + cross-platform code) + `*_native.dart` / `*_io.dart` (mobile/desktop impl) + `*_web.dart` / `*_stub.dart` (web fallback). The native side must expose `supportsLocalInference` (or equivalent capability flag) so the UI can hide unsupported features.

The active local runtime is one of `llama` (llama.cpp via `local_plugins/llama_flutter_android`) or `litert` (LiteRT-LM via `local_plugins/flutter_litert_lm`); image gen uses `local_plugins/sd_flutter_android`. `pubspec.yaml` uses `dependency_overrides` to force `llama_flutter_android` to the local checkout — the published version exists but the local plugin is authoritative. **A single native model can be loaded per app session**, and switching between `llama` and `litert` requires an app restart (`InferenceService.requiresAppRestartForRuntime`).

LiteRT-LM GPU loads are crash-tolerant: `InferenceService._loadModelOnEngine` writes a `litert_gpu_load_pending` flag before each GPU attempt, sets `litert_gpu_crash_detected` on next launch if it didn't clear, and auto-falls-back to CPU. Don't remove that handshake without understanding it.

### Persistence

All state lives in four Hive boxes (`lib/core/constants.dart`): `chat_sessions`, `chat_messages`, `tasks`, `settings`. `HiveService.deleteSession` cascades message deletion. All settings keys are centralized as `AppConstants.key*` constants — read/write Hive through them, never with raw strings. First-launch auto-config in `main.dart::_autoConfigureForDevice` writes context size / max tokens based on detected RAM and is guarded by `device_auto_configured`.

### Cloud provider abstraction

`CloudService` (`lib/services/cloud_service.dart`) normalizes ~8 provider shapes behind one `sendMessage()` interface. The provider switch threads through `_provider`, `_apiKey`, `_model` getters reading Hive — adding a provider means: new key constants in `AppConstants`, new branches in those getters, and a new request-builder branch in `sendMessage`. Anthropic uses a separate `system` param; Gemini takes inline base64 images; OpenAI-compatible providers (Kimi, NVIDIA, OpenRouter, custom) share the `/v1/chat/completions` shape.

### Local OpenAI-compatible server + tunneling

`ServerController` + `openai_server_service` expose a local HTTP server that mirrors the OpenAI Chat Completions API against the loaded local model, optionally fronted by `tunnel_service` (Cloudflare Tunnel or ngrok) so other devices can hit the phone. The server is `permanent: true` in DI because it must outlive route changes.

### Command execution channel

`ExecutionService` parses LLM output for a strict first-line `CMD: <command>` pattern and executes whitelisted commands — review `_isValidCommand` carefully before extending. The model is steered toward CMD-emission via the system prompt set in `TaskController`, distinct from the chat system prompt in `AppConstants.systemPrompt` / `uncensoredSystemPrompt` (the latter is auto-selected when `AppConstants.isUncensoredModelName` matches the loaded model).

## Branch policy

All development for this session must land on `claude/project-initialization-ebUFb`. Push with `git push -u origin claude/project-initialization-ebUFb`. Do not open PRs unless asked.
