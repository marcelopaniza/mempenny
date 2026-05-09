# v0.9.0 Test Fixtures

These are synthetic test fixtures for v0.9.0 cluster scenarios.

## WARNING — Do NOT run `/mempenny:clean` on these directories

Passing any of these subdirectories to `/mempenny:clean --dir <path>` will modify the real
fixture files. This would corrupt the test data.

To exercise the cluster behavior against a fixture, copy it to a temp directory and run there:

```bash
cp -a /mnt/data/mempenny/tests/fixtures/v09/dedupe-3way /tmp/play
# then: /mempenny:clean --dir /tmp/play
```

## Subfixtures

| Directory | Expected cluster outcome |
|-----------|--------------------------|
| `dedupe-3way/` | DEDUPE — three feedback files about the same subject written at different times; the two older files are fully superseded by the newest |
| `merge-2way/` | MERGE — two project files covering the same project from complementary angles; each has unique content and together they form a complete picture |
| `conflict/` | FLAG — two project files about the same project with direct factual contradictions on version, status, and technology choice; cannot be auto-merged |
| `cross-type-no-cluster/` | NO CLUSTER — two clearly related files whose types differ (`feedback` vs `project`); the type rule prevents clustering across types |
| `singleton-no-cluster/` | NO CLUSTER — a single file with no peer; clustering requires at least two candidate files |

## Safety marker

Each subdirectory contains a `.mempenny-fixture` file. This is a deliberate safety guard: a
future version of `/mempenny:clean` will detect this marker and abort before modifying any
files in the directory. For v0.9.0, the marker is advisory — its presence combined with this
README is the protection.
