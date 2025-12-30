# Phase 0 polish checklist

Use this to finish the Phase 0 experience before deploying staging.

## UX
- [ ] Clear error messages for:
  - [ ] transcript unavailable
  - [ ] daily limit
  - [ ] paste too short
- [ ] Loading spinner on Generate button
- [ ] Disable Generate when invalid input

## Share
- [ ] Copy link button works
- [ ] Share page renders full bullets list

## Cost / safety
- [ ] Rate limit enabled in prod/stage (2/day)
- [ ] Mock mode works when no GEMINI_API_KEY

## Code quality
- [ ] `ruff check` passes
- [ ] `pytest` passes
- [ ] `next lint` passes

## Done means
- Local works end-to-end
- Ready for staging: `staging.threadbrief.com`
