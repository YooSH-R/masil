# Walk Log Feed Interaction & Data Enhancement Plan

This plan details the refinement of `WalkLogFeedScreen` (D7) to ensure data consistency, enhanced interactivity, and multi-month content support.

## User Review Required

> [!IMPORTANT]
> **Data Consistency**: The "Total X logs" label will now dynamically calculate the number of records for the visible month.
>
> [!NOTE]
> **Daily Summary Card**: A new high-fidelity summary card (Location, Distance, Duration) will be inserted between the calendar and the statistics section, appearing only when a log exists for the selected day.

## Proposed Changes

### 1. Presentation Layer (WalkLogFeedScreen)

#### [MODIFY] Mock Data Expansion
- **June 2026**: Add 4-5 mock records (e.g., June 10, 15, 20).
- **July 2026**: Add more records to reach a total of ~10-12 to match the "12 logs" feel.
- **August 2026**: Add 3-4 initial records (e.g., August 2, 5).

#### [MODIFY] Dynamic Calculation
- Update the build logic to count how many keys in `_mockLogs` start with `"${_currentYear}-${_currentMonth.toString().padLeft(2, '0')}"`.

#### [NEW] Daily Summary Widget
- **Function**: `_buildDailySummaryCard(log)`
- **UI**: A white card with three vertical stat columns:
  - **Location**: Icon + Text (e.g., "서울숲")
  - **Distance**: Icon + Text (e.g., "2.5km")
  - **Duration**: Icon + Text (e.g., "40분")
- **Placement**: Directly below the "Total Logs" indicator and above the "Weekly/Monthly Stats" section.

### 2. Logic Refinement
- Ensure `_selectedDate` remains within the visible month range when navigating months, or reset it to the 1st of the month for clarity.

## Verification Plan

### Manual Verification
- **Multi-Month Test**: Navigate to June/August and verify that dots and the "Total Logs" count update.
- **Summary Test**: Click on a dotted day and verify the new "Daily Summary Card" appears with correct data.
- **Consistency Check**: Count the dots in July and compare them with the "Total X logs" text.
