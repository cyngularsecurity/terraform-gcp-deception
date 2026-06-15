# terraform-gcp-deception

Terraform module that plants **inert GCP decoy (honeytoken) resources** into a client environment, the GCP counterpart of [`terraform-aws-deception`](https://github.com/cyngularsecurity/terraform-aws-deception).

> **Status: deferred scaffolding.** Per [Track D](https://github.com/cyngularsecurity) the GCP epic is **deferred until the AWS shape is proven**. This repo exists as a placeholder with the provider pinned and a stub contract; the resource design is not yet locked.

## Design (inherited from AWS, to be confirmed for GCP)

- **Freely reachable, externally-unreachable** decoys — any interaction is the signal.
- **Inert by policy, lured by name** — no usable permissions; intriguing names + believable lure tags/labels.
- **No Cyngular reference anywhere in the environment** (cover protection).
- **Attribution = created resource IDs (outputs) + a caller-supplied tracking tag/label.**

## Candidate resource kinds

Service Account, GCS Bucket, Secret Manager Secret — see the per-cloud resource spec (§GCP) in the Deception background reference.

## Releasing

Pushes to `main` trigger `.github/workflows/publish_tf_module.yml` (auto `vX.Y.Z` tag + release). The [Terraform Registry](https://registry.terraform.io) auto-publishes new tags once the repo is connected (one-time UI step). Requires a `PA_TOKEN` secret.
