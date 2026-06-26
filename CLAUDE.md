# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

GastroRouteAI is a Flutter mobile app for motorcyclists ("moteros"): plan and generate motorcycle
routes (with AI assistance), save/share routes with friends, browse a public feed of routes, manage
a friends system, and receive notifications. This repo contains only the **Flutter client**. The
backend is a separate Laravel API at `..\proyecto` (sibling directory under `Herd\`), running at
`http://192.168.1.23:8000/api/v1` (see `lib/core/api/api_client.dart` for the base URL — update it if
the backend host/IP changes).

## Commands

```
flutter pub get              # install dependencies
flutter run                  # run on a connected device/emulator
flutter analyze              # static analysis (flutter_lints via analysis_options.yaml)
flutter test                 # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter build apk            # Android release build
flutter build ios            # iOS release build
```

Backend (Laravel, in `..\proyecto`) is started separately via:
```
cd C:\Users\nparaled.SGVAD\Herd\proyecto
"C:\wamp64\bin\php\php8.3.14\php.exe" artisan serve --host=0.0.0.0 --port=8000
```
(or run `start.bat` in that directory).

## Architecture

**Feature-based structure** under `lib/`:
- `lib/core/` — cross-cutting infrastructure:
  - `api/api_client.dart` — shared `Dio` instance; injects `Authorization: Bearer <token>` and
    `Accept-Language` headers via interceptor. Token is read from `flutter_secure_storage`.
  - `api/auth_service.dart` — auth API calls.
  - `storage/auth_storage.dart` — login-state checks used by router redirects.
  - `router.dart` — single `go_router` `GoRouter` instance with all app routes; auth-gating is done
    in its top-level `redirect` callback (unauthenticated users are bounced to `/login` unless on
    an auth screen or `/splash`).
  - `theme/app_theme.dart` — app-wide `AppTheme.dark` Material theme.
- `lib/features/auth/` — login, register, role selection, password reset, splash.
- `lib/features/rider/` — the rider role's screens and providers: profile, motos (bikes), route
  creation/generation/import/result, my-routes, friends, friend search.
  - Each feature's `providers/*_service.dart` wraps `ApiClient.dio` calls for that domain
    (e.g. `friendship_service.dart`, `route_service.dart`, `route_share_service.dart`,
    `route_import_service.dart`, `avatar_service.dart`, `app_notification_service.dart`).
- `lib/widgets/` — shared widgets (`rider_avatar.dart`, `route_waypoints_view.dart`) used across features.

**State management**: `flutter_riverpod`. **Navigation**: `go_router`, with screens passed data via
`state.extra` (a `Map<String, dynamic>`) rather than typed route arguments — check `router.dart` for
the expected keys when adding a route or screen parameters.

**Localization**: `easy_localization`, supported locales `es, en, fr, de, it, pt`, translation files in
`assets/translations/`, default/fallback locale is `es`. Route generator error messages, etc., should
go through the localization layer, not hardcoded strings.

**Backend integration points** (Laravel, `..\proyecto\routes\api.php` and `app/Services/`):
- AI route generation: `POST routes/generate` → `App\Services\RouteAIService`, which calls the
  Anthropic Messages API (model `claude-haiku-4-5-20251001`) to produce a route from rider params.
- Weather: `GET rider/routes/weather` → `App\Services\WeatherService` (OpenWeatherMap), current
  weather or forecast (forecast only available up to 5 days out).
- Maps/geocoding: `App\Services\GoogleMapsService`; public location search at `GET location/search`.
- Friends system: search, send/accept/reject requests, unfriend — `FriendshipController`.
- Route sharing: share/join/decline/dismiss/leave a shared route, list participants —
  `RouteShareController`.
- Most rider endpoints require `auth:api` + `role:rider` middleware; a handful (public route feed,
  public rider profile by nickname, location search) are unauthenticated.

When changing client-side request/response shapes, cross-check the corresponding Laravel controller
in `..\proyecto\app\Http\Controllers\Api\` and the route definition in `..\proyecto\routes\api.php`,
since the two codebases are developed in lockstep but live in separate git repositories.
