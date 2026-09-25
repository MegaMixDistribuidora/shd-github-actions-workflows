# Convenções do consumidor

## `.pipeline.yml` (raiz do repositório)

| Chave | Obrigatória | Uso |
| --- | --- | --- |
| `infra.terraform-version` | sim | versão instalada pelo `setup-terraform-aws` |
| `infra.working-path` | sim | diretório do Terraform |
| `environments.<ambiente>` | sim, um por ambiente | valores do ambiente, expostos como `pipe_environment_<chave>` |
| `environments.files-to-replace` | não | arquivos com tokens `${pipe_<chave>}` substituídos no CD |

Ambiente não declarado ou `terraform-version` ausente **falham** o job.

## GitHub Environments `dev` e `prod`

**Variables** (não secrets): `AWS_ROLE_ARN` e `TF_STATE_BUCKET`. O job declara `environment: <ambiente>` para lê-las.

## State

Bucket `TF_STATE_BUCKET` (um por conta), chave `<repositório>/terraform.tfstate`. **Nunca** uma pasta de ambiente na chave: o bucket já é do ambiente.

## OIDC

A role precisa confiar em `repo:MegaMixDistribuidora/<repositório>:environment:<ambiente>`. O job chamador declara `permissions: id-token: write`.

## Terraform

`environments/<ambiente>.tfvars` dentro do `working-path`. O CD aplica **o plano salvo** no mesmo job — nunca um `apply -auto-approve` sobre um plano novo.

## Plano Free

Repositórios privados não têm required reviewers nem rulesets no plano Free. A proteção de prod é o merge em `main` ser feito pelo usuário (regra 6 de `git.md`) e o hook `guard-git`.
