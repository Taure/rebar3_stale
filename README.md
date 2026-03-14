# rebar3_stale

A rebar3 plugin that runs only tests affected by code changes.

## Installation

Add the plugin to your `rebar.config`:

```erlang
{project_plugins, [rebar3_stale]}.
```

## Usage

Run only stale EUnit tests:

```shell
rebar3 stale eunit
```

Run only stale Common Test suites:

```shell
rebar3 stale ct
```

Force a full test run with `--all`:

```shell
rebar3 stale eunit --all
rebar3 stale ct --all
```

On the first run (no manifest exists), all tests are executed.

## How It Works

1. Computes MD5 checksums of all `.erl` and `.hrl` files
2. Builds a module dependency graph from compiled `.beam` files
3. Compares checksums against the stored manifest to find changed files
4. Resolves transitively affected modules
5. Filters to test modules (`*_tests`/`*_test` for EUnit, `*_SUITE` for CT) and runs only those

The manifest is stored at `_build/test/.rebar3_stale_manifest`.

## License

MIT
