package fr.telemach.telecaisse;

import java.net.InetAddress;

/**
 * Ce que l'ancienne installation lisait dans standalone.xml et dans un fichier
 * de propriétés vient désormais de l'environnement du conteneur.
 */
final class Configuration {

    static final String VERSION = "2.0";

    private Configuration() {
    }

    /** L'API de Télémarché, qui fait foi pour les prix. */
    static String telemarcheApi() {
        String url = System.getenv("TELEMARCHE_API_URL");
        return url == null || url.isBlank() ? "http://api:8080" : url.replaceAll("/+$", "");
    }

    /** Le nom de la caisse : celui du pod. */
    static String caisse() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "inconnue";
        }
    }
}
