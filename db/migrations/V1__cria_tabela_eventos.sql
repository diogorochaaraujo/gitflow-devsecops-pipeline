-- Eventos de auditoria da aplicacao de exemplo.
-- Migracao publicada nunca muda: correcao entra como V<n+1>__*.sql.
CREATE TABLE eventos (
    id         BIGSERIAL PRIMARY KEY,
    tipo       VARCHAR(40)  NOT NULL,
    detalhe    TEXT,
    criado_em  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_eventos_criado_em ON eventos (criado_em);
