# RCA: Library Search Focus Loss

## Timeline

- T+0 ms: User types; `searchText` changes.
- T+0 ms: pending-search state inserts progress text and changes intrinsic width.
- T+280 ms: debounced navigation changes the active section and loads results.
- During layout: `ViewThatFits` can select another candidate and rebuild the search subtree.
- Result: AppKit resigns the old text field as first responder.

## 5 Whys

1. Why did typing stop? The text field lost first-responder status.
2. Why did it lose first-responder status? Its SwiftUI subtree was replaced.
3. Why was the subtree replaced? `ViewThatFits` changed candidates.
4. Why did the candidate change? Conditional progress content and section controls changed intrinsic width.
5. Why did that affect the search field? The search field itself was duplicated inside both adaptive-layout candidates and had no parent-owned focus state.

## Fishbone

- Layout: flexible field width; candidate switching.
- State: pending/loading and section changes occur during typing.
- View identity: duplicate search instances in adaptive branches.
- Focus: focus state was owned only by AppKit, not stable SwiftUI state.
- Testing: no regression assertion covered stable search identity and geometry.

## Root cause

The focused control was placed inside an adaptive branch whose selection depended on state-driven intrinsic size.
