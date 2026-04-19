# 7. Segurança

## 7.1 Rede

- **Fase inicial:** Todos os serviços expostos apenas na rede local. Sem acesso
  externo.
- **Fase futura:** Reverse proxy (Traefik ou Caddy) com HTTPS e autenticação para
  acesso remoto ao Grafana e MinIO Console. VPN (WireGuard) para acesso seguro à
  rede interna.

## 7.2 Autenticação

| Serviço | Autenticação |
|---------|-------------|
| Mosquitto | Username/password (arquivo `password_file`) |
| Redpanda | SASL/SCRAM (quando exposto externamente) |
| InfluxDB 3 | Token-based |
| MinIO | Access key / Secret key (S3 API) |
| Grafana | Login local (admin + usuários) |
| Frigate | (sem auth nativo, proteger via rede/proxy) |

## 7.3 Credenciais

Todas as credenciais são gerenciadas via arquivo `.env` no Docker Compose.
O `.env` **não** é versionado no Git (adicionado ao `.gitignore`).
Um arquivo `.env.example` com valores placeholder é versionado como referência.
