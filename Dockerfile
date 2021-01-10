FROM glitchcrab/arch-build-container:latest

USER root

COPY entrypoint.sh /entrypoint.sh

USER notroot

ENTRYPOINT ["/entrypoint.sh"]
