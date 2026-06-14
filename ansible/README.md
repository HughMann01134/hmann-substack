# Ubuntu Gold Image — Ansible

A single Ansible playbook that turns a fresh Ubuntu install into a consistent, hardened baseline — a "Gold Image" — that every later deployment can build on. It installs a small set of baseline tools, hardens SSH, sets up a firewall, enables automatic security updates, and applies a few sensible server defaults.

This playbook accompanies the *Keeping Gold Images Organized* article series. <!-- add your Substack link here -->

## What it does

Running the playbook applies the following to the target machine:

- **Baseline packages** — installs `curl`, `wget`, `vim`, `htop`, `net-tools`, `unzip`, `ca-certificates`, `git`, and `ufw`.
- **SSH hardening** — disables root login and password authentication, limits authentication attempts, shortens the login grace time, and disables X11 forwarding in `/etc/ssh/sshd_config`, then restarts SSH.
- **Firewall (UFW)** — denies all incoming traffic by default, allows outgoing, permits SSH, and enables the firewall.
- **Automatic security updates** — installs and enables `unattended-upgrades`, with automatic reboots turned off.
- **Timezone** — sets the system clock to UTC.
- **Snapd** — stops, disables, and masks `snapd`.

Every task is idempotent: run the playbook as many times as you like and it only changes what actually needs changing.

## Prerequisites

- **Ansible** installed on the machine you run it from (the control node).
- An **Ubuntu/Debian** target. The playbook uses `apt` and Ubuntu-specific paths, so it will not run on non-Debian distributions as-is.
- **sudo** access on the target, since the playbook uses privilege escalation.

> [!WARNING]
> This playbook hardens the machine it runs on. It disables SSH password authentication and enables a firewall. If you run it against a server you reach over SSH with a password, you can lock yourself out. **Run it on a fresh or throwaway server, not your daily machine**, until you are confident it does what you expect.

## Usage

The inventory targets `localhost`, so the playbook configures the machine you run it on. Work from inside this directory so `ansible.cfg` is picked up automatically:

```bash
cd ansible
```

Validate the playbook's structure without touching anything:

```bash
ansible-playbook gold-image/gold-image.yml --syntax-check
```

Run it, supplying your sudo password when prompted:

```bash
ansible-playbook gold-image/gold-image.yml -K
```

The `-K` flag (`--ask-become-pass`) prompts once for your sudo password. If you would rather run it non-interactively — for example as part of a larger automated build — set up passwordless sudo for your user instead and drop the flag.

You can also preview every change before applying it with a dry run:

```bash
ansible-playbook gold-image/gold-image.yml --check
```

Note that `--check` can report errors on tasks that depend on something an earlier task would have installed (for instance the firewall steps before `ufw` is present), because check mode does not actually apply the earlier tasks. Those resolve on a real run, where tasks execute in order.

## Project structure

```
ansible/
├── ansible.cfg          # points Ansible at the inventory, disables host key prompts
├── inventory.ini        # currently targets localhost over a local connection
├── gold-image/
│   └── gold-image.yml   # the Gold Image playbook
└── README.md
```

## Customizing

- **Targeting a remote server** — edit `inventory.ini` to add your host and connection details, then point the play's `hosts:` at the matching group. Take care not to commit real host addresses, usernames, or secrets to a public repo.
- **Keeping snapd** — some tools (certbot, for example) install via snap. If you need snap on your target, remove the "Disable snapd" task.
