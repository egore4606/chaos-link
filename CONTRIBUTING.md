# Contributing to Chaos Link

Thanks for helping improve Chaos Link. Keep changes focused, transparent, and safe for the consenting gaming-PC host.

## Before opening a pull request

1. Create a short branch from the current `main`.
2. Do not commit generated installers, runtime credentials, logs, custom screamer media, or deployment output.
3. Keep all commands on the agent side allow-listed. Changes that add arbitrary command execution, stealth, persistence, or anti-cheat bypasses are out of scope.
4. Update documentation when behavior or configuration changes.

## Local checks

```powershell
dotnet restore ChaosLink.sln
dotnet build ChaosLink.sln --configuration Release --no-restore

cd apps/web
npm ci
npm run lint
npm run build
```

For protocol changes, start the server and run the synchronization smoke test:

```powershell
node scripts/smoke-test.mjs
```

## Pull requests

Explain what changed, why it is needed, how it was tested, and any security or host-input impact. Include a screenshot for visible UI changes. Keep secrets and real room URLs out of screenshots and logs.
