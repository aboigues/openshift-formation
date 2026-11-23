package fr.telemach.telecaisse;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;

/** Toutes les ressources REST de la caisse sont sous /api. */
@ApplicationPath("/api")
public class TelecaisseApplication extends Application {
}
