# ci-terraform-module.yml

Valida só os módulos alterados no PR (`modules/<nome>` ou `examples/<nome>`; mudança em `.github/` valida todos): `fmt`, `validate`, `tflint`, `terraform test`, `validate` do exemplo e checkov em relatório.

| Input | Tipo | Obrigatório | Padrão |
| --- | --- | --- | --- |
| `terraform-version` | string | não | `1.14.9` |

Permissões do job chamador: `contents: read`. Job: `Validate Modules`.
