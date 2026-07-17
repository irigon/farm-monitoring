# 7. Segurança

## 7.0 Modelo de Confiança (como o sistema é usado)

O sistema roda em **redes confiáveis**: a rede local da sede (casa) e a rede local da
agrofloresta. Nesses ambientes, quem tem acesso à rede é controlado fisicamente pelo
proprietário.

**Acesso externo (fora da propriedade) é feito exclusivamente via SSH.** Um túnel SSH
(`ssh -L`) encaminha as portas necessárias (ex.: Grafana em 3000) para a máquina do
usuário. Consequência prática:

- Nenhuma porta de serviço (InfluxDB, Grafana, MinIO, Redpanda) fica exposta à internet.
- O **SSH é o perímetro de segurança real** — protege todos os serviços de uma vez.
- Autenticação interna adicional (ex.: token no InfluxDB) seria uma segunda camada
  dentro de um perímetro que já está fechado (defesa em profundidade), não a barreira
  principal.

**Onde investir segurança, na prática:**

1. **SSH com chave** (não senha); considerar `fail2ban` e não expor a porta 22
   diretamente na internet.
2. **Não abrir portas de serviço no roteador** — apenas a do SSH. O restante fica
   acessível só na LAN ou via túnel SSH.

## 7.1 Rede

- **Local / LAN:** todos os serviços acessíveis apenas na rede local. Sem acesso externo
  direto.
- **Acesso remoto:** via túnel SSH para as portas desejadas. Sem exposição pública.

## 7.2 Autenticação

| Serviço | Autenticação |
|---------|-------------|
| Mosquitto | Username/password (arquivo `password_file`, gerado a partir do `.env`) |
| InfluxDB 3 | **Sem auth em modo local** (`--without-auth`). Token opcional como hardening. |
| MinIO | Access key / Secret key (S3 API) |
| Grafana | Login local (admin, credenciais via `.env`) |
| Frigate | Sem auth nativo — protegido pela rede/SSH |
| Redpanda | Sem auth em modo local — protegido pela rede |

> O InfluxDB roda com `--without-auth` **por decisão consciente**: no modelo de
> confiança acima (LAN confiável + acesso externo só via SSH), ele nunca está
> acessível de fora. Isso mantém o debug e a iteração simples. Habilitar token é um
> passo de hardening opcional, útil caso o Grafana/InfluxDB venha a ser exposto por
> um proxy público ou caso outras pessoas passem a ter acesso à rede.

## 7.3 Credenciais

Todas as credenciais são gerenciadas via arquivo `.env` no Docker Compose.
O `.env` **não** é versionado no Git (está no `.gitignore`).
Um arquivo `.env.example` com valores placeholder é versionado como referência.
