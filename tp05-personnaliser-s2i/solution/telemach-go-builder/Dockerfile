# telemach-go-builder — l'image de construction S2I des services Go de Telemach.
#
# Elle part de l'image de construction de Red Hat et n'en change que les
# scripts : le compilateur, ses correctifs et la préparation à l'UID arbitraire
# restent ceux de go-toolset.
FROM registry.access.redhat.com/ubi10/go-toolset:10.3

LABEL io.k8s.display-name="Go pour Telemach" \
      io.k8s.description="Construit les services Go de Telemach : un dépôt, plusieurs programmes (variable COMPOSANT)" \
      io.openshift.tags="builder,go,telemach" \
      io.openshift.expose-services="8080:http" \
      io.openshift.s2i.scripts-url="image:///usr/libexec/s2i"

# root seulement le temps de l'installation.
USER 0
COPY s2i/bin/ /usr/libexec/s2i/
RUN chmod -R a+rx /usr/libexec/s2i \
 && chgrp -R 0 /opt/app-root && chmod -R g=u /opt/app-root
USER 1001

EXPOSE 8080
# Lancée sans sources, l'image affiche son mode d'emploi.
CMD ["/usr/libexec/s2i/usage"]
