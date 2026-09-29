# test/

| Directory | Contents |
|---|---|
| `attacks/` | The eleven attacks of Section 4.2. Each **passes only if the attack fails**. A red test here is a real finding. |
| `unit/` | Ordinary behavioural tests: registration, grant and revoke, anchoring, recovery authorisation, record CRUD. |

```bash
npm test
```

Helper contracts used only by tests live in `contracts/test/` and are never
deployed as part of the framework.
