# SPIRE TPM Node Attestation Example with Raspberry Pi 4

# Overview

This is a demonstrational project to aid learning about the node attestation mechanisms leveraging TPM. The architecture consists of a [SPIRE][spire] server running on the workstation (laptop) and a SPIRE agent running on Raspberry Pi, with a clean image of 64bit Raspberry Pi OS, and a [LetsTrust][letstrust] TPM (Infineon Optiga SLB9672, Firmware v15.24 Spec. Rev.: 1.59)

It is assumed that the Raspberry Pi board is configured to be reachable over SSH, and that the corresponding SSH identity is loaded in the local chain. The default host name assigned to Pi is `zero-trust` and user name is `spire`.

Many of the configuration steps are automated with Ansible and Docker Compose, in a mostly idempotent manner, thus enabling quick and safe iterations.

# Enabling the TPM

The playbook [enable-tpm.yml](./ansible/enable-tpm.yml) encodes the steps required to enable TPM on a freshly imaged board.

# spire-tpm-plugin

The first scenario of the project makes use of [spire-tpm-plugin]. It relies on pre-registration of the TPM EK hash by creating an empty file under [tpm-hashes](./tpm-hashes/).

The sequence goes essentially like this:

```
copy tpm_attestor_agent
        ↓
copy get_tpm_pubhash
        ↓
query EK public-key hash
        ↓
validate 64-hex-character result
        ↓
touch tpm-hashes/<hash> on controller
```

## Pre-requisites

SPIRE server is run in a Docker container, which can be brought up by running 
```sh
docker compose up -d spire-server-tpm
```
Logs can be followed via 
```sh
docker logs -f spire-sever
```
in a separate terminal.

Next the server bundle must be exported locally, so it can be subsequently copied over to Pi and provided to the agent. A convenience script [extract_bundle.sh](./scripts/extract_bundle.sh) will save the file locally.

It is assumed that the following binaries are built separatelt (targeting the respective platforms) and copied under [bin/](./bin/):
 * `spire-agent` (`arm64`)
 * `spire-server` (`$GOARCH`)
 * `tpm_attestor_agent` (`arm64`)
 * `tpm_attestor_server` (`$GOARCH`)

Once all the above pre-requisites have been met, run

```sh
ansible-playbook -K \
  -i ansible/inventory.ini \
  ansible/site.yml \
  -e spire_server_address=${HOST_IP} \
  -e spire_attestor=tpm
```

to provision Raspberry PI. This will apply a composition of two playbooks: [enable-tpm.yml](./ansible/enable-tpm.yml) to enable TPM and [deploy-agent.yml](./ansible/deploy-agent.yml) to deploy, configure and start the agent. If all goes well, in a few minutes you should observe a successful attestation event in the server logs. You can also run [list-agents.sh](./scripts/list_agents.sh) to print the attributes of the attested agent.

Experiment with the various failure and recovery modes by stopping the agent on Pi (`sudo systemctl stop spire-agent`), moving the hash file `./tpm-hashes/<hash-value>` elsewhere, then restarting the agent and observing it fail attestation to the server.

# tpm_devid

This scenario makes use of the built-in [tpm-devid] plugin and largely follows the steps outlined in [tpm-deployment-walkthrough]. The LDevID provisioning process implemented here goes like this:

```
Pi TPM
  │
  ├── create H-2-style SRK
  │
  ├── create ECC LDevID signing key
  │
  ├── save SPIRE public/private blobs
  │
  ├── temporarily persist LDevID key
  │
  └── OpenSSL TPM provider creates CSR
              │
              ▼
         Ansible fetch
              │
              ▼
          controller
              │
              ├── step ca token --cnf-file CSR
              │
              └── step ca sign CSR
                         │
                         ▼
                   LDevID cert
                         │
              + Device intermediate
                         │
                         ▼
                  Ansible copy
                         │
                         ▼
 /etc/spire-agent/devid/
 ├── devid.crt.pem
 ├── devid.priv.blob
 └── devid.pub.blob
```

## Pre-requisites

If you have the containers running from the previous scenario, bring them down first
```sh
docker compose down -v
```
In this scenario we need the SPIRE server to be configured differently, so it should be started with 
```sh
docker compose up -d spire-server-tpm-devid
```
Compose file intentionally forces collision of the container names, because the two flavours of the server are not intended to be run at the same time. If you have an existing bootstrap bundle in the project directory make sure to re-generate it at this point by running [exract_bundle.sh](./scripts/extract_bundle.sh).

Device certificates are signed by a locally running CA based on the [Step CA][step-ca] container image started with `docker compose up -d step-ca`. The one-time initial setup is performed by [create_device_ca.sh](./scripts/create_device_ca.sh).

Agent-side provisioning in this case is performed as follows:
```sh
ansible-playbook -K \
  -i ansible/inventory.ini \
  ansible/site.yml \
  -e spire_server_address=${HOST_IP} \
  -e spire_attestor=tpm_devid
```

## Remarks

Normally, if
```sh
devid.crt.pem
devid.priv.blob
devid.pub.blob
```
already exist, Ansible leaves the device identity alone. In order to force creating a completely new device identity, append the following variable override to the `ansible-playbook` inviocation above:

```sh
-e spire_reprovision_devid=true
```
That generates a new TPM LDevID key, new CSR and new Smallstep certificate. Since SPIRE's `tpm_devid` agent SPIFFE ID is derived from the SHA-1 fingerprint of the LDevID certificate, this naturally gives the node a new attested identity. If you only want to throw away SPIRE's cached SVID/bundle but preserve the LDevID, use the following override:

```sh
-e spire_reset_state=true
```

It is assumed that the endorsement bundle is assembled out-of-band from the manufacturer's root and intermediate certificates. For the TPM used in this demo the certificates can be obtained from [Infineon][infineon] website.

[spire]: https://github.com/spiffe/spire
[spire-tpm-plugin]: https://github.com/spiffe/spire-tpm-plugin/tree/master
[tpm2-tools]: https://tpm2-tools.readthedocs.io/en/latest/
[letstrust]: https://letstrust.de/
[tpm-devid]: https://github.com/spiffe/spire/blob/main/doc/plugin_agent_nodeattestor_tpm_devid.md
[tpm-deployment-walkthrough]: https://github.com/spiffe/spire/blob/main/doc/tpm_deployment_walkthrough.md
[step-ca]: https://smallstep.com/docs/step-ca/
[infineon]: https://www.infineon.com/design-resources/platforms/optiga-software-tools/optiga-tpm-and-trust-certificates?ftab=01