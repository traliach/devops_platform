# devops_platform

> Self-hosted DevOps platform — Jenkins CI/CD, Prometheus, Grafana via Docker Compose, provisioned with Terraform and configured with Ansible on AWS EC2

![CI](https://github.com/traliach/devops_platform/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/github/license/traliach/devops_platform)
![Tag](https://img.shields.io/github/v/tag/traliach/devops_platform)

## Overview

<!-- Brief description of the project and what it does -->

## Architecture

<!-- Add architecture diagram here -->

## Packages

| Package | Description |
|---------|-------------|
| `apps/web` | React + TypeScript frontend |
| `apps/api` | Node.js + Express backend |
| `packages/shared` | Shared TypeScript types |

## Quick start

```bash
git clone https://github.com/traliach/devops_platform.git
cd devops_platform
npm install
npm run dev
```

## Environment variables

```bash
cp apps/api/.env.example apps/api/.env
# fill in values
```

## CI/CD

Every push to `main` runs the full pipeline. PRs require all checks to pass before merge.

## License

[MIT](./LICENSE) © 2026 Achille Traore | [achille.tech](https://achille.tech)
