package fr.telemach.telecaisse;

import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

@Path("/")
@Produces(MediaType.APPLICATION_JSON)
public class CaisseResource {

    private static final Logger LOG = Logger.getLogger(CaisseResource.class.getName());

    @Inject
    Base base;

    @Inject
    Catalogue catalogue;

    public record Vente(int produit, int quantite) {
    }

    @GET
    @Path("info")
    public Map<String, String> info() {
        return Map.of("service", "telecaisse", "version", Configuration.VERSION, "caisse", Configuration.caisse(),
                "telemarche", Configuration.telemarcheApi());
    }

    @GET
    @Path("tickets")
    public Response tickets() {
        try {
            List<Base.Ticket> t = base.tickets();
            return Response.ok(t).build();
        } catch (Exception e) {
            LOG.log(Level.WARNING, "lecture des tickets", e);
            return erreur(Response.Status.SERVICE_UNAVAILABLE, "base de la caisse indisponible");
        }
    }

    @POST
    @Path("ventes")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response vendre(Vente v) {
        if (v == null || v.quantite() < 1) {
            return erreur(Response.Status.BAD_REQUEST, "quantité invalide");
        }
        long prix;
        try {
            prix = catalogue.prix(v.produit());
        } catch (Exception e) {
            LOG.log(Level.WARNING, "appel à Télémarché", e);
            return erreur(Response.Status.BAD_GATEWAY, "Télémarché injoignable : " + e.getMessage());
        }
        if (prix < 0) {
            return erreur(Response.Status.NOT_FOUND, "produit inconnu de Télémarché");
        }
        try {
            Base.Ticket t = base.enregistrer(v.produit(), v.quantite(), prix * v.quantite(), Configuration.caisse());
            LOG.info("vente enregistrée : ticket " + t.id());
            return Response.status(Response.Status.CREATED).entity(t).build();
        } catch (Exception e) {
            LOG.log(Level.WARNING, "enregistrement du ticket", e);
            return erreur(Response.Status.SERVICE_UNAVAILABLE, "base de la caisse indisponible");
        }
    }

    /** Vivant : le serveur répond. Ne dépend de rien d'extérieur. */
    @GET
    @Path("sante/vivant")
    @Produces(MediaType.TEXT_PLAIN)
    public String vivant() {
        return "ok";
    }

    /** Prête : la base de la caisse répond. */
    @GET
    @Path("sante/prete")
    @Produces(MediaType.TEXT_PLAIN)
    public Response prete() {
        try {
            base.verifier();
            return Response.ok("prête").build();
        } catch (Exception e) {
            return Response.status(Response.Status.SERVICE_UNAVAILABLE).entity("base : " + e.getMessage()).build();
        }
    }

    private static Response erreur(Response.Status s, String message) {
        return Response.status(s).entity(Map.of("erreur", message)).build();
    }
}
