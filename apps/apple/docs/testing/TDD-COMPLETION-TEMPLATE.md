# TDD Todo Completion Template

Use this block when updating a testing todo before closing it.

```md
## TDD Evidence

### RED
- Test(s):
  - `...`
- Command:
  - `...`
- Expected failure observed:
  - `...`

### GREEN
- Minimal implementation added:
  - `...`
- Command:
  - `...`
- Pass result:
  - `...`

### REFACTOR
- Refactor performed:
  - `...`
- Focused verification command:
  - `...`
- Broader verification command:
  - `...`
- Final result:
  - `...`

## Files Changed
- `...`
- `...`

## Notes / Follow-ups
- `...`
```

## Example command pattern
- Focused test: `xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-iOS -only-testing:HealthMdTests/<TestClass>/<testMethod> -destination 'platform=iOS Simulator,name=iPhone 16 Pro'`
- Broader suite: `make test`
