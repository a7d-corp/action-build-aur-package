FROM glitchcrab/arch-build-container:latest

USER root
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
