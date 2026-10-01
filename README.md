# krueger benchmark history

This branch holds the results of benchmark runs of moonrockz/krueger, one
JSON file per run under `runs/YYYY/MM/`. The Benchmarks workflow adds a
file for each run on `main`. Do not merge this branch into another branch.

To compare a local run with the latest `main` run, run `mise run bench`
and then `mise run bench:compare`. See AGENTS.md > Benchmarks.
