# Helm Charts — Claude Guidance

## Standards
All charts must follow `docs/standard.md`. That file is authoritative. This file covers behavioral rules and repo-specific context only — do not duplicate the standard here.

## Migration Policy
Whenever you touch an existing chart — even for a one-line fix — bring the **entire chart** into compliance with `docs/standard.md` before closing the task. Do not leave partial migrations.

## Unit Testing
See `docs/unit-testing.md` for the unit test philosophy and guidelines.

After any template or values change, run both commands and fix all errors before reporting the task done:

```
helm lint charts/<chart>
helm template <release-name> charts/<chart> | kubectl apply --dry-run=client -f -
```

## Integration Testing
See `docs/chart-testing.md` for the integration testing guidlines.
