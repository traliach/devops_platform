# Contributing to devops_platform

Thank you for your interest in contributing!

## Workflow

1. Fork the repository
2. Create a branch from `main`: `git checkout -b feat/your-feature`
3. Make your changes, following the conventions below
4. Open a Pull Request against `main`
5. All CI checks must pass before merging

## Branch naming

| Type        | Pattern                  |
|-------------|--------------------------|
| Feature     | `feat/short-description` |
| Bug fix     | `fix/short-description`  |
| Infrastructure | `infra/short-description` |
| CI/CD       | `ci/short-description`   |
| Docs        | `docs/short-description` |
| Refactor    | `refactor/short-description` |

## Commit messages (Conventional Commits)

```
feat: add visitor counter Lambda function
fix: resolve CloudFront cache invalidation timing
infra: add S3 bucket versioning
ci: add terraform plan step to PR workflow
docs: update architecture diagram
```

## Pull Request checklist

- [ ] Tests pass locally
- [ ] No `.env` or secrets committed
- [ ] CHANGELOG.md updated if user-facing change
- [ ] PR description explains what and why

## Questions?

Open an issue or reach out at [achille.tech](https://achille.tech)
