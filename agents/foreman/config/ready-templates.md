# Ready Checklist Templates

## Base Checklist (every item, regardless of type)
- [ ] Goal is one sentence
- [ ] Acceptance criteria are numbered and testable
- [ ] "Done" is defined — what does a human verify?
- [ ] Size estimated (XS/S/M/L)
- [ ] Files affected listed

## Type: UI Change
Add to base:
- [ ] Current screenshot or description of what exists
- [ ] Redline mockup (green dashed = added, red dashed = removed) approved by David

## Type: Data Model
Add to base:
- [ ] Schema change described (new tables/fields)
- [ ] Migration strategy (additive? breaking?)
- [ ] What existing data is affected

## Type: Integration
Add to base:
- [ ] External API/service documented
- [ ] Auth/credentials identified
- [ ] Failure mode described (what if the API is down?)
