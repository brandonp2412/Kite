# Privacy

Kite connects directly to the Matrix homeserver selected by the user. That server and its federated peers handle Matrix communications and media under their own policies. Conversations may be encrypted, but network and room metadata may still be visible to the service providers.

Push notifications may use a UnifiedPush distributor. The bundled embedded FCM distributor uses SchildiChat’s gateway (`https://up.spiritcroc.de`), which receives push registration identifiers and notification delivery requests according to that provider's practices. Kite opens GitHub Issues for optional bug reports and never automatically uploads device logs to an upstream bug-report server. Information you choose to include in a public GitHub issue is public.

The Kite project does not provide a separate account service. Source: https://github.com/brandonp2412/Kite
