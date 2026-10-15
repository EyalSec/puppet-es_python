# es_python: es-python for Puppet

**Install es-python, the EyalSec Python runtime, on your Puppet-managed Linux nodes. One API key covers the fleet, and each node reports to your EyalSec dashboard as its own machine.**

[![Website](https://img.shields.io/badge/website-eyalsec.com-e8b04b)](https://eyalsec.com)
[![Docs](https://img.shields.io/badge/docs-install-2a2c27)](https://eyalsec.com/docs/install)

Your nodes are already described in Puppet. This module adds one class to that
description: it installs es-python for the user your Python service runs as,
the same way the install command on the EyalSec Machines page does. Once a node
has es-python, later runs change nothing.

es-python runs your Python app unchanged and follows untrusted input to the SQL
query, shell command or file path that uses it. You choose, per machine,
whether it reports each flow or also stops it.

**For:** teams with an EyalSec account that includes es-python, on Linux nodes
(x86_64 or aarch64), Python 3.9 to 3.14, Puppet 7 or 8. No module dependencies.

## Quick start

1. On your EyalSec dashboard, open **Settings > API access** and create a
   full-access key ([API keys](https://eyalsec.com/docs/api-keys)).
2. Keep it in Hiera, encrypted with hiera-eyaml, as `es_python::api_key`.
3. Classify your nodes:

   ```puppet
   class { 'es_python':
     api_key    => Sensitive(lookup('es_python::api_key')),
     authorized => true,     # see "Authorization" below
     user       => 'app',    # the user your service runs as
   }
   ```

Then start your service with `/home/app/.local/bin/es-python` where it ran
`python`. See [Running es-python](https://eyalsec.com/docs/running-es-python).

Install the module from this repository until it is listed on the Forge, for
example in your `Puppetfile`:

```ruby
mod 'eyalsec-es_python',
  git: 'https://github.com/EyalSec/puppet-es_python.git',
  ref: 'v1.0.0'
```

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `api_key` | `undef` | `Sensitive[String]`. A full-access API key. One key serves every node. |
| `install_secret` | `undef` | `Sensitive[String]`. Instead of a key: a one-time install secret for one machine. It works once and expires 10 minutes after it was issued. |
| `authorized` | `false` | Required with an API key. See [Authorization](#authorization). |
| `user` | `'root'` | The user es-python is installed for. |
| `machine_name` | `$trusted['certname']` | The machine name this node reports under. Each node needs its own. |
| `python_version` | `undef` | `'3.9'` to `'3.14'`. `undef` matches the node's own `python3`. |
| `url` | `'https://eyalsec.com'` | Your EyalSec address. |
| `manage_dependencies` | `true` | Install `curl` (Debian family) and CA certificates when they are missing. |
| `helper_path` | `/usr/local/libexec/eyalsec/es-python-fleet-install.sh` | Where the install helper is placed. |

## How it works

The class places a small install helper on the node and runs it as `user`,
unless the helper's `--check` says es-python is already installed for that
user. The helper finds the machine named `machine_name` on your account, adds
it the first time with its build left to detection (as **Add machine** does by
default), gets a fresh one-time install secret, and runs the EyalSec installer.
The installer's progress appears in the run's output as plain text.

es-python installs into the user's home (`~/opt/`, `~/.local/bin/es-python`,
`~/.eyalsec/`) and changes nothing system-wide. See
[What it installs](https://eyalsec.com/docs/install#what-it-installs).

## Keeping the key secret

The key reaches the helper in its environment, never on a command line, and
Puppet does not log an exec's environment, at `--debug` included. Like any
value in a catalog, the key travels in the compiled catalog to the node; keep
it `Sensitive`, encrypted at rest in Hiera, or fetch it on the agent with a
`Deferred` lookup from your secret store.

## Authorization

`authorized => true` is your confirmation that you own these nodes or are
authorized to monitor them, that you will not use es-python to surveil third
parties, and that you are not located in or a national of an embargoed
destination and not on a denied-party list. It is the same statement as the
tick box on the Machines page. es-python may capture values from your program's
memory, including secrets and personal data, when untrusted data reaches a
monitored operation, so only run it on systems you are authorized to monitor.

## Things to know

- **Each node is one machine** and counts toward your
  [machine limit](https://eyalsec.com/docs/plans#machine-limit). When a node is
  retired, delete its machine on the Machines page so it stops counting.
- **Machine names must be unique.** Two nodes with the same `machine_name`
  share one machine, and the second install stops the first from reporting.
- **Updating.** To reinstall the newest build on a node, remove the user's
  launcher (`~/.local/bin/es-python`, or `es-python3.X` when `python_version`
  is set) and let the next run install again; the machine keeps its name,
  settings and events.

## Getting es-python

es-python needs an EyalSec account. To get one,
[book a live demo](https://eyalsec.com/contact); pricing is at
[eyalsec.com/pricing](https://eyalsec.com/pricing).

## License

MIT. See [LICENSE](LICENSE).
