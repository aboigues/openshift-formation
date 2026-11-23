package fr.telemach.telecaisse;

import jakarta.annotation.Resource;
import jakarta.enterprise.context.ApplicationScoped;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import javax.sql.DataSource;

/**
 * La base de la caisse. Elle n'a pas déménagé : elle reste dans le système
 * d'information, hors du cluster. La source de données est celle que crée la
 * couche Galleon postgresql-datasource, réglée par les variables POSTGRESQL_*.
 */
@ApplicationScoped
public class Base {

    @Resource(lookup = "java:jboss/datasources/PostgreSQLDS")
    DataSource ds;

    public record Ticket(long id, int produit, int quantite, long montantCentimes, String caisse, String creeLe) {
    }

    public void verifier() throws SQLException {
        try (Connection c = ds.getConnection(); Statement s = c.createStatement()) {
            s.setQueryTimeout(2);
            s.executeQuery("SELECT 1 FROM tickets LIMIT 1").close();
        }
    }

    public List<Ticket> tickets() throws SQLException {
        String sql = "SELECT id, produit, quantite, montant_centimes, caisse, cree_le FROM tickets ORDER BY id";
        List<Ticket> liste = new ArrayList<>();
        try (Connection c = ds.getConnection(); PreparedStatement ps = c.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                liste.add(lire(rs));
            }
        }
        return liste;
    }

    public Ticket enregistrer(int produit, int quantite, long montant, String caisse) throws SQLException {
        String sql = "INSERT INTO tickets (produit, quantite, montant_centimes, caisse) VALUES (?, ?, ?, ?) "
                + "RETURNING id, produit, quantite, montant_centimes, caisse, cree_le";
        try (Connection c = ds.getConnection(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setInt(1, produit);
            ps.setInt(2, quantite);
            ps.setLong(3, montant);
            ps.setString(4, caisse);
            try (ResultSet rs = ps.executeQuery()) {
                rs.next();
                return lire(rs);
            }
        }
    }

    private static Ticket lire(ResultSet rs) throws SQLException {
        return new Ticket(rs.getLong(1), rs.getInt(2), rs.getInt(3), rs.getLong(4), rs.getString(5),
                rs.getObject(6, java.time.OffsetDateTime.class).toString());
    }
}
