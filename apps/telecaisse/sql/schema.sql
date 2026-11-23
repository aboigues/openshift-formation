-- La base de la caisse, telle qu'elle existe dans le système d'information.
-- Elle ne déménage pas avec l'application : Télécaisse s'y connecte à distance.
CREATE TABLE IF NOT EXISTS tickets (
    id               BIGSERIAL PRIMARY KEY,
    produit          INTEGER     NOT NULL,
    quantite         INTEGER     NOT NULL CHECK (quantite > 0),
    montant_centimes BIGINT      NOT NULL,
    caisse           TEXT        NOT NULL,
    cree_le          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- L'historique : les ventes passées par l'ancienne caisse, avant la migration.
INSERT INTO tickets (produit, quantite, montant_centimes, caisse, cree_le)
SELECT * FROM (VALUES
    (1, 2, 700,  'caisse-magasin-1', TIMESTAMPTZ '2026-10-02 09:14:00+02'),
    (3, 1, 1250, 'caisse-magasin-1', TIMESTAMPTZ '2026-10-02 10:41:00+02'),
    (2, 4, 1000, 'caisse-magasin-2', TIMESTAMPTZ '2026-10-03 17:05:00+02')
) AS historique(produit, quantite, montant_centimes, caisse, cree_le)
WHERE NOT EXISTS (SELECT 1 FROM tickets);
