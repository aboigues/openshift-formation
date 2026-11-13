# telemach-go-builder — l'image de construction S2I des services Go de Telemach.
#
# Elle part de l'image de construction de Red Hat et n'en change que les
# scripts : le compilateur, ses correctifs et la préparation à l'UID arbitraire
# restent ceux de go-toolset.
FROM registry.access.redhat.com/ubi10/go-toolset:10.3

LABEL io.k8s.display-name="Go pour Telemach" \
      io.k8s.description="Construit les services Go de Telemach : un dépôt, plusieurs programmes (variable COMPOSANT)" \
      io.openshift.tags="______,go,telemach" \
      io.openshift.expose-services="8080:http" \
      io.openshift.s2i.scripts-url="image://______"
# TODO 4 (ci-dessus) : le mot-clé qui range l'image parmi les images de construction dans la console,
#          puis le dossier de l'image où sont copiés les scripts S2I (voir COPY, plus bas).

# root seulement le temps de l'installation.
USER ______                        # TODO 5 : root, le temps de copier les scripts et de régler les droits
COPY s2i/bin/ /usr/libexec/s2i/
RUN chmod -R a+rx /usr/libexec/s2i \
 && chgrp -R 0 /opt/app-root && chmod -R g=u /opt/app-root
USER ______                        # TODO 6 : et l'on redevient un utilisateur ordinaire, numérique

EXPOSE 8080
# Lancée sans sources, l'image affiche son mode d'emploi.
CMD ["/usr/libexec/s2i/usage"]
