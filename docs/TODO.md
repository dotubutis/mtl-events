# TODO: Future Features

## Handle Multiple Events Per Image

**Status**: ✅ Completed (2026-01-28)
**Priority**: Medium  
**Complexity**: Medium

### Problem

Some event posters (like festival lineups) contain multiple events with different dates/venues. Example: "Everyday Ago - Festival of Time 2026" shows events across multiple dates (Feb 1, Feb 6, Feb 10, etc.).

Current behavior:
- Structured output schema only supports extracting a single event
- Prompt instructs Claude to extract the first event and mention others in the description field
- This workaround loses structured data for subsequent events

### What Would Need to Change

**1. Schema Modification (Low complexity)**
- `lib/vision_extractor.rb` lines 203-216: Change JSON schema to return array of events
- Wrap current single event structure in an array

**2. Return Type Change (Medium complexity)**
- `VisionExtractor#extract()` currently returns single `Event` object (line 61)
- Would need to return `Array<Event>` instead
- All callers need updating to handle arrays

**3. Downstream Impacts (Medium-High complexity)**
- Update `CalendarClient` or wherever `extract()` is called
- Data model: one image URL/block_id would map to multiple events
- Review filtering/deduplication logic

### Design Questions to Address

1. **Event relationships**: How to track that multiple events came from same poster?
   - Shared `block_id` but separate event records?
   - Add a `festival_name` or `parent_event` field?

2. **Confidence scoring**: Per-event or per-image?

3. **Festival context**: Should we preserve the overarching festival name/relationship?

### Current Workaround

The existing approach (extract first event, describe others in description field) is acceptable for now. It keeps all information accessible without requiring pipeline restructuring.

### Implementation Notes

**Implemented on 2026-01-28**

Changes made:
1. Updated `VisionExtractor` JSON schema to return `events` array instead of single event object
2. Modified `VisionExtractor#extract()` to return `Array<Event>` (empty array on failure)
3. Updated `main.rb` to iterate over multiple events per image block
4. Enhanced extraction prompt to explicitly request all events from multi-event posters
5. Added logging to show event count and progress for multi-event images

Test results:
- Successfully extracted 6 events from "Everyday Ago Festival of Time 2026" poster
- All events extracted with high confidence
- Proper venue, date, and artist information captured for each event
- Festival context preserved in event descriptions


- Test with block 42449718 - it's a multi-event poster, but it's not being extracted correctly.