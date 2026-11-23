package fr.telemach.telecaisse;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.json.Json;
import jakarta.json.JsonObject;
import jakarta.json.JsonReader;
import java.io.StringReader;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/**
 * Les prix ne sont plus recopiés dans la caisse : elle les demande à l'API de
 * Télémarché, par le nom de son Service.
 */
@ApplicationScoped
public class Catalogue {

    private final HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();

    /** Le prix d'un produit, en centimes ; -1 s'il n'existe pas. */
    public long prix(int produit) throws Exception {
        HttpRequest req = HttpRequest.newBuilder(URI.create(Configuration.telemarcheApi() + "/api/products/" + produit))
                .timeout(Duration.ofSeconds(3)).GET().build();
        HttpResponse<String> rep = client.send(req, HttpResponse.BodyHandlers.ofString());
        if (rep.statusCode() == 404) {
            return -1;
        }
        if (rep.statusCode() != 200) {
            throw new IllegalStateException("Télémarché a répondu " + rep.statusCode());
        }
        try (JsonReader r = Json.createReader(new StringReader(rep.body()))) {
            JsonObject p = r.readObject();
            return p.getJsonNumber("prix_centimes").longValue();
        }
    }
}
