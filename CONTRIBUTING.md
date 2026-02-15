# Contributing

Thanks for contributing.

## Local workflow

```bash
cp .env.example .env
make install
make start
```

Health check:

```bash
curl http://localhost:8888/health
```

## Pull requests

- Keep changes focused and small.
- Update docs when configuration changes.
- Avoid committing secrets (`.env` is ignored by default).
- Use clear commit messages that explain why the change is needed.
