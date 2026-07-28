# MYSIL Project Implementation Plan (FRS v0.1)

This plan details the end-to-end implementation of the MYSIL project based on the Functional Requirements Specification (FRS) v0.1, excluding FR-09 (Video features).

## User Review Required

> [!IMPORTANT]
> **FR-09 (Walk Video)** is excluded as per user request.
>
> [!NOTE]
> I will use **Provider** for state management and **Dio** for API communication as they are industry standards for Flutter projects of this scale. If you have a preference for BLoC or GetX, please let me know.
>
> [!WARNING]
> For **FR-10 (Walk Path)**, I will assume the use of a Kakao Map plugin. You will need to provide a Kakao Native App Key for full functionality.

## Proposed Changes

### 1. Foundation & Architecture
- **Architecture**: MVVM (Model-View-ViewModel) with a Repository pattern for clean separation of concerns.
- **State Management**: `provider` for reactive UI updates.
- **Networking**: `dio` with interceptors for JWT (Access/Refresh Token) management and error handling (CR-01, CR-02, CR-10).
- **Navigation**: `go_router` for robust routing and deep link support (FR-19).
- **Storage**: `flutter_secure_storage` for sensitive data like tokens (CR-06).

### 2. Module Implementation Breakdown

#### [Section 1] Member & Pet Management
- **FR-01 (Signup)**: Implement email/phone verification flow, nickname duplication checks.
- **FR-02 (Login/Logout)**: Implement standard & SSO login, auto-login using Refresh Tokens, and password reset.
- **FR-03 (Member Info)**: Inquiry, update, and withdrawal with re-authentication for sensitive actions.
- **FR-04 (Pet Management)**: CRUD operations for pet profiles.
- **FR-05 (Robot Registration)**: QR code scanning logic and connection status monitoring.

#### [Section 2] Walk Feature
- **FR-07 (Walk Suggestion)**: Notification handling and accept/decline logic.
- **FR-08 (Walk Session)**: Real-time walk progress UI, duration tracking, and reconnection handling.
- **FR-10 (Walk Path)**: Map integration using GPS coordinates, handling path exceptions (GPS loss).
- **FR-11 (Walk Dashboard)**: Statistical visualization (Daily/Weekly/Monthly).
- **FR-12 (Emotional Walk Log)**: Feed UI for AI-generated logs.

#### [Section 3] Emotional Interaction
- **FR-13 to FR-15**: Indoor status management (Autonomous roaming, Charging/Sleep animations).
- **FR-16 (Play Request)**: Proactive interaction settings and notifications.
- **FR-17 (Intimacy/Mood)**: Intimacy level dashboard and history.
- **FR-18 (Welcome Home)**: Geofencing logic (GPS-based) to trigger robot movement.

#### [Section 4] Admin & Common
- **FR-06 (Admin)**: Member/Robot management with search, filters, and audit logs.
- **CR (Common Requirements)**: Global error handling, network status UI, and debouncing on buttons (CR-11, CR-12).

## Verification Plan

### Automated Tests
- Unit tests for Repositories and ViewModels.
- Widget tests for critical screens (Login, Signup).

### Manual Verification
- Testing the full app flow from Splash -> Login -> Home.
- Mocking API responses to verify error handling and edge cases (e.g., 401 Unauthorized, Network Disconnection).
